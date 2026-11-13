#!/usr/bin/env bash

# Define o nome do computador pela escola (INEP) ou CREDE, pelo ambiente e pelo serial,
# e grava a identificação em /usr/local/seduc/identificacao.conf (base para enviar
# atualizações por escola e ambiente).
#   Escola: <INEP>-<AMBIENTE>-<4 últimos do serial>   ex.: 23012345-LMAT-1234
#   CREDE:  CR<nn>-<AMBIENTE>-<4 últimos do serial>    ex.: CR05-INF-1234
# Se outra máquina da rede já responde por esse nome (DNS, NetBIOS ou mDNS), usa mais
# dígitos do serial (5, 6...). Chamado como root pelo criar_usuarios.sh.
# Uso: identificar_computador.sh escola <INEP> <AMBIENTE> [nome da escola]
#      identificar_computador.sh crede <número> <AMBIENTE>

set -euo pipefail

SCRIPT_VERSION="1.5-2"

#####################
## VARIABLE GLOBAL ##
#####################
SEDUC_DIR="/usr/local/seduc"
AMBIENTES="$SEDUC_DIR/ambientes.conf"
CONF="$SEDUC_DIR/identificacao.conf"
DMI_DIR="/sys/class/dmi/id"
DIGITOS_MIN=4

###############
## FUNCTIONS ##
###############

# Nome do ambiente (sigla do tipo) ou vazio se não existir em ambientes.conf
nome_ambiente() {
    local TIPO="$1" SIGLA="$2" T S NOME
    while IFS="|" read -r T S NOME; do
        [[ "$T" == "$TIPO" && "$S" == "$SIGLA" ]] && { echo "$NOME"; return 0; }
    done < <(grep -v '^[[:space:]]*#' "$AMBIENTES")
    return 1
}

# Serial da máquina, só letras e números em maiúsculas. Sem serial de fábrica, usa o
# MAC da primeira placa de rede física.
get_serial() {
    local SRC SERIAL IF
    for SRC in product_serial chassis_serial board_serial; do
        [[ -r "$DMI_DIR/$SRC" ]] || continue
        SERIAL=$(tr -cd 'A-Za-z0-9' < "$DMI_DIR/$SRC" | tr '[:lower:]' '[:upper:]')
        case "$SERIAL" in
            ""|UNKNOWN|NONE|DEFAULT|DEFAULTSTRING|TOBEFILLEDBYOEM|OEM|SYSTEMSERIALNUMBER|CHASSISSERIALNUMBER|0|00000000|123456789) ;;
            *) echo "$SERIAL"; return 0 ;;
        esac
    done
    for IF in /sys/class/net/*; do
        [[ -e "$IF/device" ]] || continue
        tr -cd 'A-Fa-f0-9' < "$IF/address" | tr '[:lower:]' '[:upper:]'
        return 0
    done
    return 1
}

# Outra máquina responde por este nome na rede? (não conta este próprio computador)
nome_em_uso() {
    local NOME="$1" IPS PROPRIOS IP
    [[ "${NOME,,}" == "$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')" ]] && return 1
    PROPRIOS=" $(hostname -I 2>/dev/null) 127.0.0.1 127.0.1.1 ::1 "
    IPS="$(timeout 5 getent ahosts "$NOME" 2>/dev/null | awk '{print $1}' | sort -u) "
    IPS+="$(timeout 5 getent ahosts "$NOME.local" 2>/dev/null | awk '{print $1}' | sort -u) "
    if command -v nmblookup >/dev/null 2>&1; then
        IPS+="$(timeout 5 nmblookup "$NOME" 2>/dev/null | awk '/<00>/ {print $1}' | sort -u)"
    fi
    for IP in $IPS; do
        [[ "$PROPRIOS" == *" $IP "* ]] || { echo "Nome $NOME em uso por $IP"; return 0; }
    done
    return 1
}

# Primeiro nome livre: 4 últimos dígitos do serial, depois 5, 6...; com o serial
# inteiro em uso, acrescenta -2, -3...
escolher_nome() {
    local BASE="$1" SERIAL="$2" N NOME I
    NOME="$BASE-$SERIAL"
    for (( N=DIGITOS_MIN; N<=${#SERIAL}; N++ )); do
        NOME="$BASE-${SERIAL: -$N}"
        nome_em_uso "$NOME" >&2 || { echo "$NOME"; return 0; }
    done
    if (( ${#SERIAL} < DIGITOS_MIN )); then
        nome_em_uso "$NOME" >&2 || { echo "$NOME"; return 0; }
    fi
    for I in 2 3 4 5 6 7 8 9; do
        nome_em_uso "$NOME-$I" >&2 || { echo "$NOME-$I"; return 0; }
    done
    return 1
}

# Valor seguro para o arquivo de configuração (lido com "source" por outros scripts)
limpar() {
    printf '%s' "$1" | tr -d '"$`\\\n\r' | cut -c1-120
}

aplicar_nome() {
    local NOME="$1"
    hostnamectl hostname "$NOME"
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1   $NOME/" /etc/hosts
    else
        echo "127.0.1.1   $NOME" >> /etc/hosts
    fi
}

gravar_conf() {
    local TMP
    TMP=$(mktemp "$CONF.XXXXXX")
    {
        echo "# Identificação do computador (identificar_computador.sh $SCRIPT_VERSION)"
        echo "TIPO=\"$TIPO\""
        echo "INEP=\"$INEP\""
        echo "ESCOLA=\"$(limpar "$ESCOLA")\""
        echo "CREDE=\"$CREDE\""
        echo "AMBIENTE=\"$SIGLA\""
        echo "AMBIENTE_NOME=\"$(limpar "$AMBIENTE_NOME")\""
        echo "SERIAL=\"$SERIAL\""
        echo "COMPUTADOR=\"$NOME\""
        echo "DATA=\"$(date '+%d/%m/%Y %H:%M')\""
    } > "$TMP"
    chmod 644 "$TMP"
    mv -f "$TMP" "$CONF"
}

main() {
    TIPO="${1:-}"; CODIGO="${2:-}"; SIGLA="${3:-}"; ESCOLA="${4:-}"
    INEP=""; CREDE=""
    echo "Identificação pedida: $TIPO $CODIGO $SIGLA ${ESCOLA:+($ESCOLA)}"

    case "$TIPO" in
        escola)
            [[ "$CODIGO" =~ ^[0-9]{8}$ ]] || { echo "INEP inválido: $CODIGO"; return 1; }
            INEP="$CODIGO"; BASE="$INEP" ;;
        crede)
            [[ "$CODIGO" =~ ^[0-9]{1,2}$ ]] && (( 10#$CODIGO >= 1 && 10#$CODIGO <= 20 )) \
                || { echo "CREDE inválida: $CODIGO"; return 1; }
            CREDE=$(printf '%02d' "$((10#$CODIGO))"); BASE="CR$CREDE"; ESCOLA="CREDE $CREDE" ;;
        *)
            echo "Tipo inválido: $TIPO (escola ou crede)"; return 1 ;;
    esac
    AMBIENTE_NOME=$(nome_ambiente "$TIPO" "$SIGLA") || { echo "Ambiente inválido para $TIPO: $SIGLA"; return 1; }

    SERIAL=$(get_serial) || { echo "Sem serial nem placa de rede para o nome"; return 1; }
    echo "Serial: $SERIAL"
    NOME=$(escolher_nome "$BASE-$SIGLA" "$SERIAL") || { echo "Nenhum nome livre para $BASE-$SIGLA"; return 1; }
    echo "Nome do computador: $NOME"

    aplicar_nome "$NOME"
    gravar_conf
    echo "Identificação gravada em $CONF"
}

##########
## MAIN ##
##########
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "Este script precisa ser executado como root."
        exit 1
    fi
    main "$@"
fi
