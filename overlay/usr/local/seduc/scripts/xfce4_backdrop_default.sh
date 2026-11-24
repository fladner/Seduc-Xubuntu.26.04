#!/usr/bin/env bash

set -euo pipefail

# Wallpaper Lock (autostart do XFCE): papel de parede SEDUC em cada login.
# Desligado pela Central do Suporte ("Proteções da aparência"): com a marca
# /usr/local/seduc/flags/aparencia-livre, o papel de parede do usuário fica.
SCRIPT_VERSION="1.7-2"
[ -f /usr/local/seduc/flags/aparencia-livre ] && exit 0

# Wallpaper Padrão
WALLPAPER="/usr/share/xfce4/backdrops/default.png"

# Detecta monitores
mapfile -t MONITORES < <(
    xrandr --query |
    awk '/ connected/ {print $1}'
)

for MON in "${MONITORES[@]}"; do

    BASE="/backdrop/screen0/monitor${MON}/workspace0"

    xfconf-query \
        -c xfce4-desktop \
        -p "${BASE}/last-image" \
        -n -t string \
        -s "${WALLPAPER}" \
        >/dev/null 2>&1 || true

    xfconf-query \
        -c xfce4-desktop \
        -p "${BASE}/image-style" \
        -n -t int \
        -s 5 \
        >/dev/null 2>&1 || true

    xfconf-query \
        -c xfce4-desktop \
        -p "${BASE}/image-show" \
        -n -t bool \
        -s true \
        >/dev/null 2>&1 || true

done
