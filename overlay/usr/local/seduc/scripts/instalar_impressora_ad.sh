#!/usr/bin/env bash

# Parte root do painel de impressoras (painel_impressora_ad.sh), chamada via
# pkexec sem senha para o usuário da sessão ativa (polkit
# br.gov.ce.seduc.impressora-ad). Só instala ou remove filas do servidor de
# impressão do ad.conf: o usuário escolhe a fila, nunca o servidor ou o driver.
# Uso: instalar_impressora_ad.sh adicionar|remover <fila> [fila...]

set -uo pipefail

SCRIPT_VERSION="1.3-0"

#####################
## VARIABLE GLOBAL ##
#####################
AD_CONF="/usr/local/seduc/ad/ad.conf"
LOG="/usr/local/seduc/logs/instalar_impressora_ad.log"

IMPRESSORA_SERVIDOR=""
IMPRESSORA_DRIVER="drv:///sample.drv/generpcl.ppd"
# shellcheck source=/dev/null
. "$AD_CONF"

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "===== $(date) - versão $SCRIPT_VERSION - ${PKEXEC_UID:-?}: $* ====="

###############
## FUNCTIONS ##
###############
# Nome da impressora no CUPS: SEDUC-<fila> só com letras, números, _ e -
nome_cups() {
    echo "SEDUC-$(echo "$1" | tr -c 'A-Za-z0-9_-' '_' | sed 's/_*$//')"
}

# Espaço e outros caracteres da fila no endereço smb://
uri_fila() {
    local FILA="$1" SAIDA="" I C
    for (( I=0; I<${#FILA}; I++ )); do
        C="${FILA:I:1}"
        case "$C" in
            [A-Za-z0-9._-]) SAIDA+="$C" ;;
            *) SAIDA+=$(printf '%%%02X' "'$C") ;;
        esac
    done
    echo "smb://$IMPRESSORA_SERVIDOR/$SAIDA"
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

[[ -n "$IMPRESSORA_SERVIDOR" ]] || { echo "IMPRESSORA_SERVIDOR vazio em $AD_CONF"; exit 1; }

ACAO="${1:-}"
shift || true
[[ $# -gt 0 ]] || { echo "Nenhuma fila informada"; exit 1; }

ERROS=0
for FILA in "$@"; do
    if [[ ! "$FILA" =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]{0,63}$ ]]; then
        echo "Fila inválida: $FILA"
        ERROS=1
        continue
    fi
    NOME=$(nome_cups "$FILA")
    case "$ACAO" in
        adicionar)
            if lpadmin -p "$NOME" -E -v "$(uri_fila "$FILA")" -m "$IMPRESSORA_DRIVER" \
                    -D "$FILA" -L "$IMPRESSORA_SERVIDOR" \
                    -o auth-info-required=negotiate -o printer-is-shared=false; then
                echo "$NOME: instalada ($(uri_fila "$FILA"))"
            else
                ERROS=1
            fi
            ;;
        remover)
            lpadmin -x "$NOME" && echo "$NOME: removida" || ERROS=1
            ;;
        *)
            echo "Ação inválida: $ACAO"
            exit 1
            ;;
    esac
done

exit "$ERROS"
