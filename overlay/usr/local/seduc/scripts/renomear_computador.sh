#!/usr/bin/env bash

# Troca o nome do computador (Ferramentas de rede da Central do Suporte, via pkexec).
# Confere o nome, recusa se outra máquina da rede já usa o nome e, com o computador
# no domínio (AD), recusa: a conta do computador no AD ficaria com o nome antigo.
# Atualiza o hostname, a linha 127.0.1.1 do /etc/hosts e o COMPUTADOR do
# identificacao.conf.
# Uso: renomear_computador.sh <nome>
# Saída: 0 trocado | 2 nome inválido | 3 nome em uso na rede | 4 computador no domínio

set -euo pipefail

SCRIPT_VERSION="1.6-1"

#####################
## VARIABLE GLOBAL ##
#####################
SCRIPTS="/usr/local/seduc/scripts"
LOG="/usr/local/seduc/logs/renomear_computador.log"
SMB_CONF="/etc/samba/smb.conf"
IDENTIFICACAO="/usr/local/seduc/identificacao.conf"

###############
## FUNCTIONS ##
###############
# Nome de computador válido: letras sem acento, números e hífen, sem hífen nas pontas, até 63
nome_valido() {
    local LC_ALL=C   # sem isso, [A-Za-z] aceita letra acentuada no português
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

no_dominio() {
    grep -qiE '^[[:space:]]*security[[:space:]]*=[[:space:]]*ads' "$SMB_CONF" 2>/dev/null
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "===== $(date) - versão $SCRIPT_VERSION ====="

NOVO="${1:-}"
ATUAL=$(hostnamectl hostname 2>/dev/null || hostname)
echo "Nome atual: $ATUAL; pedido: $NOVO"

if ! nome_valido "$NOVO"; then
    echo "Nome inválido: use letras, números e hífen (sem hífen no começo ou no fim), até 63."
    exit 2
fi
if [[ "${NOVO,,}" == "${ATUAL,,}" ]]; then
    echo "O computador já se chama $ATUAL."
    exit 0
fi
if no_dominio; then
    echo "O computador está no domínio (AD): saia do domínio, troque o nome e ingresse de novo."
    exit 4
fi

# nome_em_uso e aplicar_nome do identificar_computador.sh (o main dele não roda no source)
# shellcheck source=/dev/null
. "$SCRIPTS/identificar_computador.sh"
if nome_em_uso "$NOVO"; then
    echo "Outra máquina da rede já usa o nome $NOVO."
    exit 3
fi

aplicar_nome "$NOVO"
if [[ -f "$IDENTIFICACAO" ]]; then
    sed -i "s/^COMPUTADOR=.*/COMPUTADOR=\"$NOVO\"/" "$IDENTIFICACAO"
fi
echo "Nome do computador trocado de $ATUAL para $NOVO"
