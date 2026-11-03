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
IMPRESSORA=""
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
    local TEXTO="<b>Ingressar este computador no domínio $DOMINIO</b>\nUse um usuário do AD com permissão para ingressar máquinas.\nImpressora no formato \\\\\\\\servidor\\\\fila."
    if no_dominio; then
        TEXTO="<b>Este computador já está no domínio $(wbinfo --own-domain 2>/dev/null).</b>\nPara refazer, ingresse de novo; para remover, use Sair do domínio."
        BOTOES=(--button="Cancelar:1" --button="Sair do domínio:3" --button="Ingressar de novo:0")
    fi

    "${YAD[@]}" --form --width=520 --text="$TEXTO" --separator=$'\n' \
        --field="Usuário administrador do AD" "" \
        --field="Senha:H" "" \
        --field="Nome do computador (até 15)" "$(nome_padrao)" \
        --field="OU do computador (opcional, ex.: Escolas/Computadores)" "" \
        --field="Impressora compartilhada (opcional)" "$IMPRESSORA" \
        "${BOTOES[@]}"
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
    IMPRESSORA_SEL="${CAMPOS[4]:-}"

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
    break
done

executar "$SENHA" entrar "$USUARIO" "$COMPUTADOR" "$OU" "$IMPRESSORA_SEL"
STATUS=$?
unset SENHA
mostrar_relatorio "$STATUS" entrar
