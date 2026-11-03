#!/usr/bin/env bash

# Painel de ingresso no Active Directory SEDUC (menu SEDUC).
# Pede as credenciais de um administrador do AD e chama via pkexec o
# ingressar_ad.sh, que faz o ingresso, as pastas (pam_mount) e a impressora.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.3-0"

#####################
## VARIABLE GLOBAL ##
#####################
INGRESSAR="/usr/local/seduc/scripts/ingressar_ad.sh"
AD_CONF="/usr/local/seduc/ad/ad.conf"
LOG_ROOT="/usr/local/seduc/logs/ingressar_ad.log"
RELATORIO="/usr/local/seduc/logs/ingressar_ad.relatorio"
TITULO="Active Directory SEDUC"
ICONE="network-workgroup"

DOMINIO="seduc.ce.gov.br"
WORKGROUP="SEDUC"
IMPRESSORA=""
IMPRESSORA_SERVIDOR=""
# shellcheck source=/dev/null
[ -r "$AD_CONF" ] && . "$AD_CONF"

YAD=(yad --title="$TITULO" --window-icon="$ICONE" --center --borders=12)

###############
## FUNCTIONS ##
###############
erro() {
    "${YAD[@]}" --image=dialog-error --text="$1" --button="OK:0" --width=440
}

check_live() {
    if grep -q "casper" /proc/cmdline; then
        erro "O ingresso no domínio não funciona no modo de teste (Live).\nInstale o sistema primeiro."
        exit 0
    fi
}

no_dominio() {
    systemctl is-active --quiet winbind && wbinfo --own-domain >/dev/null 2>&1
}

# Nome NetBIOS: até 15 caracteres, letras, números e hífen
nome_padrao() {
    hostname -s | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9-' | cut -c1-15
}

formulario() {
    local BOTOES=(--button="Cancelar:1" --button="Ingressar:0")
    local TEXTO="<b>Ingressar este computador no domínio $DOMINIO</b>\nUse um usuário do AD com permissão para ingressar máquinas."
    if no_dominio; then
        TEXTO="<b>Este computador já está no domínio $(wbinfo --own-domain 2>/dev/null).</b>\nPara refazer, ingresse de novo; para remover, use Sair do domínio."
        BOTOES=(--button="Cancelar:1" --button="Sair do domínio:3" --button="Ingressar de novo:0")
    fi

    "${YAD[@]}" --form --width=520 --text="$TEXTO" --separator=$'\n' \
        --field="Usuário administrador do AD" "" \
        --field="Senha:H" "" \
        --field="Nome do computador (até 15)" "$(nome_padrao)" \
        --field="OU do computador (opcional, ex.: Escolas/Computadores)" "" \
        "${BOTOES[@]}"
}

# Filas compartilhadas no servidor de impressão; imprime \\servidor\fila ou nada
escolher_impressora() {
    local USUARIO="$1" SENHA="$2" FILAS LINHAS=() TIPO NOME COMENT ESCOLHA
    if [[ -n "$IMPRESSORA" ]]; then
        echo "$IMPRESSORA"
        return 0
    fi
    [[ -n "$IMPRESSORA_SERVIDOR" ]] || return 0

    FILAS=$(PASSWD="$SENHA" smbclient -L "//$IMPRESSORA_SERVIDOR" -U "$USUARIO" \
                -W "$WORKGROUP" -g 2>/dev/null | grep '^Printer|')
    if [[ -z "$FILAS" ]]; then
        "${YAD[@]}" --image=dialog-warning --width=460 \
            --text="Não foi possível listar as impressoras de $IMPRESSORA_SERVIDOR.\nContinuar o ingresso sem impressora?" \
            --button="Cancelar:1" --button="Continuar:0" || return 1
        return 0
    fi

    LINHAS+=(TRUE "" "Nenhuma" "")
    while IFS='|' read -r TIPO NOME COMENT; do
        LINHAS+=(FALSE "$NOME" "$NOME" "$COMENT")
    done <<< "$FILAS"

    ESCOLHA=$("${YAD[@]}" --list --radiolist --width=560 --height=360 \
        --text="<b>Impressora de $IMPRESSORA_SERVIDOR</b>\nEscolha a impressora deste computador:" \
        --column="" --column="fila:HD" --column="Impressora" --column="Descrição" \
        --print-column=2 --separator="" \
        --button="Cancelar:1" --button="Continuar:0" "${LINHAS[@]}") || return 1
    [[ -n "$ESCOLHA" ]] && printf '\\\\%s\\%s\n' "$IMPRESSORA_SERVIDOR" "$ESCOLHA"
    return 0
}

executar() {
    local SENHA="$1"; shift
    local STATUS_ARQ STATUS
    STATUS_ARQ=$(mktemp)

    ( printf '%s\n' "$SENHA" | pkexec "$INGRESSAR" "$@"; echo "${PIPESTATUS[1]}" > "$STATUS_ARQ" ) \
        | "${YAD[@]}" --progress --auto-close --no-buttons \
            --width=500 --text="Aguarde..." --percentage=0

    STATUS=$(cat "$STATUS_ARQ" 2>/dev/null || echo 1)
    rm -f "$STATUS_ARQ"
    return "$STATUS"
}

mostrar_relatorio() {
    local STATUS="$1" ACAO="$2" IMAGEM TEXTO LINHAS=() ITEM SITUACAO
    case "$STATUS" in
        126|127) erro "A senha do administrador local não foi confirmada.\nNada foi alterado."; return 1 ;;
        0) IMAGEM=dialog-information
           TEXTO="<b>Pronto.</b>\nReinicie o computador para usar o login do domínio." ;;
        *) IMAGEM=dialog-warning
           TEXTO="<b>Algo deu errado.</b>\nDetalhes em $LOG_ROOT" ;;
    esac
    [[ "$ACAO" == "sair" && "$STATUS" == 0 ]] && TEXTO="<b>Computador fora do domínio.</b>\nReinicie para voltar só com os usuários locais."

    if [ -s "$RELATORIO" ]; then
        while IFS='|' read -r ITEM SITUACAO; do
            LINHAS+=("$ITEM" "$SITUACAO")
        done < "$RELATORIO"
    fi
    if (( ${#LINHAS[@]} )); then
        "${YAD[@]}" --list --image="$IMAGEM" --text="$TEXTO" --width=620 --height=320 \
            --no-selection --column="Item" --column="Resultado" \
            --button="Reiniciar agora:10" --button="Fechar:0" "${LINHAS[@]}"
    else
        "${YAD[@]}" --image="$IMAGEM" --text="$TEXTO" \
            --button="Reiniciar agora:10" --button="Fechar:0" --width=440
    fi
    [[ $? -eq 10 && "$STATUS" == 0 ]] && systemctl reboot
    return 0
}

##########
## MAIN ##
##########
check_live

while :; do
    DADOS=$(formulario); RET=$?
    [[ $RET -eq 0 || $RET -eq 3 ]] || exit 0

    mapfile -t CAMPOS <<< "$DADOS"
    USUARIO="${CAMPOS[0]:-}"
    SENHA="${CAMPOS[1]:-}"
    COMPUTADOR="${CAMPOS[2]:-}"
    OU="${CAMPOS[3]:-}"

    if [[ -z "$USUARIO" || -z "$SENHA" ]]; then
        erro "Informe o usuário e a senha do administrador do AD."
        continue
    fi

    if [[ $RET -eq 3 ]]; then
        "${YAD[@]}" --image=dialog-question --width=440 \
            --text="Remover este computador do domínio?\nOs usuários do AD não vão mais entrar nele." \
            --button="Cancelar:1" --button="Sair do domínio:0" || continue
        executar "$SENHA" sair "$USUARIO"
        mostrar_relatorio $? sair
        exit 0
    fi

    COMPUTADOR="${COMPUTADOR^^}"
    if [[ ! "$COMPUTADOR" =~ ^[A-Z0-9-]{1,15}$ ]]; then
        erro "Nome do computador inválido.\nUse até 15 letras, números ou hífen."
        continue
    fi
    IMPRESSORA_SEL=$(escolher_impressora "$USUARIO" "$SENHA") || continue
    break
done

executar "$SENHA" entrar "$USUARIO" "$COMPUTADOR" "$OU" "$IMPRESSORA_SEL"
STATUS=$?
unset SENHA
mostrar_relatorio "$STATUS" entrar
