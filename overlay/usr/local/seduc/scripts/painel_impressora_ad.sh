#!/usr/bin/env bash

# Painel "Impressoras SEDUC" (menu SEDUC), para o usuário do AD já logado:
# lista as filas compartilhadas no servidor de impressão do ad.conf com o
# ticket Kerberos do login e instala as escolhidas pelo
# instalar_impressora_ad.sh (pkexec sem senha, regra do polkit).

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.5-0"

#####################
## VARIABLE GLOBAL ##
#####################
AD_CONF="/usr/local/seduc/ad/ad.conf"
INSTALAR="/usr/local/seduc/scripts/instalar_impressora_ad.sh"
TITULO="Impressoras SEDUC"
ICONE="printer"

REALM="SEDUC.CE.GOV.BR"
IMPRESSORA_SERVIDOR=""
# shellcheck source=/dev/null
[ -r "$AD_CONF" ] && . "$AD_CONF"

YAD=(yad --title="$TITULO" --window-icon="$ICONE" --center --borders=12)

###############
## FUNCTIONS ##
###############
aviso() {
    "${YAD[@]}" --image="${2:-dialog-warning}" --text="$1" --button="OK:0" --width=460
}

# O usuário precisa ser do AD (winbind) e estar com ticket Kerberos
verificar_usuario() {
    if [[ -z "$IMPRESSORA_SERVIDOR" ]]; then
        aviso "Nenhum servidor de impressão configurado em $AD_CONF."
        exit 1
    fi
    if ! wbinfo -i "$USER" >/dev/null 2>&1; then
        aviso "As impressoras SEDUC são para usuários do domínio.\nEntre no computador com o seu usuário do AD."
        exit 0
    fi
    klist -s && return 0

    # Sem ticket (ex.: login com a senha em cache fora da rede): pede a senha
    local SENHA
    SENHA=$("${YAD[@]}" --entry --hide-text --width=420 \
        --text="Digite a sua senha do AD para acessar o servidor de impressão:" \
        --button="Cancelar:1" --button="OK:0") || exit 0
    if ! printf '%s\n' "$SENHA" | kinit "$USER@$REALM" >/dev/null 2>&1; then
        aviso "Senha recusada ou servidor do domínio fora de alcance."
        exit 1
    fi
}

listar_filas() {
    smbclient -L "//$IMPRESSORA_SERVIDOR" --use-kerberos=required -g 2>/dev/null \
        | awk -F'|' '$1 == "Printer" {print $2 "|" $3}'
}

nome_cups() {
    echo "SEDUC-$(echo "$1" | tr -c 'A-Za-z0-9_-' '_' | sed 's/_*$//')"
}

instalada() {
    lpstat -p "$(nome_cups "$1")" >/dev/null 2>&1
}

escolher() {
    local FILAS="$1" LINHAS=() FILA DESC SITUACAO
    while IFS='|' read -r FILA DESC; do
        [[ -n "$FILA" ]] || continue
        SITUACAO=""
        instalada "$FILA" && SITUACAO="instalada"
        LINHAS+=(FALSE "$FILA" "$FILA" "$DESC" "$SITUACAO")
    done <<< "$FILAS"

    "${YAD[@]}" --list --checklist --width=640 --height=420 \
        --text="<b>Impressoras de $IMPRESSORA_SERVIDOR</b>\nMarque as impressoras e escolha instalar ou remover:" \
        --column="" --column="fila:HD" --column="Impressora" --column="Descrição" --column="Situação" \
        --print-column=2 --separator="" \
        --button="Fechar:1" --button="Remover marcadas:3" --button="Instalar marcadas:0" \
        "${LINHAS[@]}"
}

# Modos para a Central do Suporte em web (rodam como o usuário, sem janela):
#   --listar        uma linha por informação, separada por "|":
#                     ERRO|<texto>  SERVIDOR|<servidor>  SEM_TICKET  FILA|<fila>|<descrição>|<1 se instalada>
#   --kinit         lê a senha do AD na entrada padrão e pede o ticket Kerberos
#   --padrao <fila> deixa a impressora como padrão só deste usuário
listar() {
    local FILAS FILA DESC
    if [[ -z "$IMPRESSORA_SERVIDOR" ]]; then
        echo "ERRO|Nenhum servidor de impressão configurado em $AD_CONF."
        return 0
    fi
    if ! wbinfo -i "$USER" >/dev/null 2>&1; then
        echo "ERRO|As impressoras SEDUC são para usuários do domínio. Entre no computador com o seu usuário do AD."
        return 0
    fi
    echo "SERVIDOR|$IMPRESSORA_SERVIDOR"
    klist -s || { echo "SEM_TICKET"; return 0; }
    FILAS=$(listar_filas)
    if [[ -z "$FILAS" ]]; then
        echo "ERRO|Não foi possível listar as impressoras de $IMPRESSORA_SERVIDOR. Confira se está na rede SEDUC."
        return 0
    fi
    while IFS='|' read -r FILA DESC; do
        [[ -n "$FILA" ]] || continue
        instalada "$FILA" && echo "FILA|$FILA|$DESC|1" || echo "FILA|$FILA|$DESC|0"
    done <<< "$FILAS"
}

##########
## MAIN ##
##########
case "${1:-}" in
    --listar) listar; exit 0 ;;
    --kinit)
        IFS= read -r SENHA || true
        printf '%s\n' "$SENHA" | kinit "$USER@$REALM" >/dev/null 2>&1
        exit $?
        ;;
    --padrao)
        lpoptions -d "$(nome_cups "${2:-}")" >/dev/null 2>&1
        exit $?
        ;;
esac

verificar_usuario

FILAS=$(listar_filas)
if [[ -z "$FILAS" ]]; then
    aviso "Não foi possível listar as impressoras de $IMPRESSORA_SERVIDOR.\nConfira se está na rede SEDUC."
    exit 1
fi

while :; do
    SELECAO=$(escolher "$FILAS"); RET=$?
    case "$RET" in
        0) ACAO=adicionar ;;
        3) ACAO=remover ;;
        *) exit 0 ;;
    esac

    MARCADAS=()
    while IFS= read -r F; do
        [[ -n "$F" ]] && MARCADAS+=("$F")
    done <<< "$SELECAO"
    if (( ${#MARCADAS[@]} == 0 )); then
        aviso "Marque pelo menos uma impressora." dialog-information
        continue
    fi

    if pkexec "$INSTALAR" "$ACAO" "${MARCADAS[@]}"; then
        if [[ "$ACAO" == adicionar ]]; then
            # Padrão só deste usuário (~/.cups/lpoptions): a primeira marcada
            lpoptions -d "$(nome_cups "${MARCADAS[0]}")" >/dev/null 2>&1 || true
            aviso "Impressora(s) instalada(s): ${MARCADAS[*]}\nA primeira ficou como padrão para você." dialog-information
        else
            aviso "Impressora(s) removida(s): ${MARCADAS[*]}" dialog-information
        fi
    else
        aviso "Não foi possível concluir.\nDetalhes em /usr/local/seduc/logs/instalar_impressora_ad.log"
    fi
done
