#!/usr/bin/env bash

# Quando a instalação é feita sem cabo de rede, o instalador (subiquity) grava
# a placa cabeada no netplan sem dhcp4 nem endereço. O netplan transforma isso
# numa conexão "netplan-<placa>" com IPv4 "Apenas conexão local" (link-local).
# Se o arquivo do instalador não tiver nenhuma configuração real, ele é retirado
# e o NetworkManager volta a usar a conexão automática (DHCP).

set -euo pipefail

SCRIPT_VERSION="1.1-0"

#####################
## VARIABLE GLOBAL ##
#####################
ARQUIVO="${1:-/etc/netplan/00-installer-config.yaml}"
BACKUP_DIR="/usr/local/seduc/backup"
LOG="/usr/local/seduc/logs/fix_netplan_instalador.log"

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1

echo "===== $(date) - versão $SCRIPT_VERSION ====="

##########
## MAIN ##
##########
if [ ! -f "$ARQUIVO" ]; then
    echo "$ARQUIVO não existe. Nada a fazer."
    exit 0
fi

# IP fixo, DHCP explícito ou Wi-Fi configurado na instalação: respeita
if grep -qE '^[[:space:]]*(dhcp4|dhcp6|addresses|routes|gateway4|gateway6|nameservers|access-points)[[:space:]]*:' "$ARQUIVO"; then
    echo "$ARQUIVO tem configuração de rede real. Mantido."
    exit 0
fi

mkdir -p "$BACKUP_DIR"
mv -f "$ARQUIVO" "$BACKUP_DIR/$(basename "$ARQUIVO").$(date +%Y%m%d%H%M%S)"
echo "$ARQUIVO sem configuração de rede: movido para $BACKUP_DIR"

# Refaz /run/NetworkManager/system-connections sem a conexão netplan-<placa>
netplan generate
echo "netplan generate concluído"
