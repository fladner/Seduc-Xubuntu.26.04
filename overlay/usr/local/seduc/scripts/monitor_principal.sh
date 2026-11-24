#!/usr/bin/env bash

# Painel e ícones da área de trabalho no monitor principal (autostart do XFCE).
# Os usuários novos já nascem assim (default.xml do painel com output-name "Primary"
# e xfce4-desktop.xml com desktop-icons/primary). Para quem já existia, ajusta uma vez,
# no login, pelo xfconf (vale na hora): o painel 1 em "Primário" e "Mostrar ícones
# apenas na tela principal". Depois o usuário pode mudar (com as proteções da
# aparência desligadas, a mudança fica).

set -uo pipefail

SCRIPT_VERSION="1.7-3"

MARCA="${XDG_CONFIG_HOME:-$HOME/.config}/seduc/monitor-principal"

grep -q casper /proc/cmdline 2>/dev/null && exit 0
[ -f "$MARCA" ] && exit 0

# Espera o painel e a área de trabalho subirem (xfconfd pronto)
for _ in $(seq 1 30); do
    xfconf-query -c xfce4-panel -p /panels >/dev/null 2>&1 && break
    sleep 1
done

OK=1
# Primeiro painel da lista (normalmente o panel-1)
PAINEL=$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' | head -1)
if [ -n "$PAINEL" ]; then
    xfconf-query -c xfce4-panel -p "/panels/panel-$PAINEL/output-name" -n -t string -s Primary || OK=0
fi
xfconf-query -c xfce4-desktop -p /desktop-icons/primary -n -t bool -s true || OK=0

if (( OK )); then
    mkdir -p "$(dirname "$MARCA")"
    echo "$SCRIPT_VERSION $(date '+%F %T')" > "$MARCA"
fi
exit 0
