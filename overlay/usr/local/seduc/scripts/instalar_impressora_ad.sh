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
WRAPPER_KRB5="/usr/libexec/samba/smbspool_krb5_wrapper"
BACKEND_SMB="/usr/lib/cups/backend/smb"
BACKEND_SMB_ORIGINAL="/usr/lib/cups/smb.seduc-original"
APPARMOR_LOCAL="/etc/apparmor.d/local/usr.sbin.cupsd"

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

# Faz o CUPS imprimir com o ticket Kerberos de quem mandou o trabalho: o backend
# smb do pacote é o smbspool, que roda como lp e não enxerga o ticket; sem ele o
# trabalho fica retido pedindo "negotiate". O wrapper do Samba troca para o
# usuário antes do smbspool. Desvio com dpkg-divert para sobreviver às
# atualizações do smbclient; o caminho real do wrapper precisa de regra no
# AppArmor do cupsd.
preparar_backend_kerberos() {
    [[ -x "$WRAPPER_KRB5" ]] || { echo "Não encontrado: $WRAPPER_KRB5"; return 1; }

    if [[ "$(readlink -f "$BACKEND_SMB")" != "$WRAPPER_KRB5" ]]; then
        dpkg-divert --local --rename --divert "$BACKEND_SMB_ORIGINAL" --add "$BACKEND_SMB" || return 1
        ln -sf "$WRAPPER_KRB5" "$BACKEND_SMB" || return 1
        echo "Backend smb: $WRAPPER_KRB5"
    fi

    if ! grep -qsF "$WRAPPER_KRB5" "$APPARMOR_LOCAL"; then
        echo "$WRAPPER_KRB5 Cx -> third_party," >> "$APPARMOR_LOCAL"
    fi
    if [[ -d /sys/kernel/security/apparmor && -f /etc/apparmor.d/usr.sbin.cupsd ]]; then
        apparmor_parser -r /etc/apparmor.d/usr.sbin.cupsd || return 1
    fi
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

if [[ "$ACAO" == adicionar ]]; then
    preparar_backend_kerberos || { echo "Falha ao preparar o backend Kerberos"; exit 1; }
fi

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
                    -o auth-info-required=negotiate -o printer-is-shared=false \
                    -o PageSize=A4; then
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
