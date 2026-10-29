#!/usr/bin/env bash

set -euo pipefail

# Atualização 21/01/2026
SCRIPT_VERSION="1.2-0"

# Verifica se o ambiente é live
if grep -q "casper" /proc/cmdline; then
    echo "Ambiente Live detectado. Abortando..."
    exit 0
fi

# Rodar com pkexec se não for root
if [ "$EUID" -ne 0 ]; then
    export DISPLAY=$DISPLAY
    export XAUTHORITY=$XAUTHORITY
    SCRIPT_PATH="$(readlink -f "$0")"
    exec pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY bash "$SCRIPT_PATH" "$@"
fi

SPIN_PID=""

spin() {
    local spinner="/-\| "
    local i=0
    while :; do
        printf "\b${spinner:i++%${#spinner}:1}"
        sleep 0.1
    done
}

start_spinner() {
    if [ -z "$SPIN_PID" ]; then
        spin &
        SPIN_PID=$!
    fi
}

stop_spinner() {
    if [ -n "$SPIN_PID" ]; then
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
        SPIN_PID=""
        printf "\b" # Limpa a linha do spinner
    fi
}

cleanup() {
    stop_spinner
}
trap cleanup EXIT

echo -n "Restaurando o sistema... "
start_spinner
{
    LOCKED_PIDS=$(fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock 2>/dev/null || true)
    if [[ -n "$LOCKED_PIDS" ]]; then
        stop_spinner
        echo -e "\n❌ Erro: APT está bloqueado por processo(s): $LOCKED_PIDS"
        echo "Feche os processos que estejam usando o apt/dpkg e tente novamente."
        return 1
    fi

    # Reinstalando o bloqueio de tela
    apt install -y xfce4-screensaver > /dev/null 2>&1

    # Restaura o papel de parede
    GREETER_DESKTOP_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
    GREETER_BACKUP_CONF="${GREETER_DESKTOP_CONF}.bkp"
    XFCE_DESKTOP_CONF="/etc/xdg/xdg-xubuntu/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    XFCE_BACKUP_CONF="${XFCE_DESKTOP_CONF}.bkp"
    CHROME_LOCAL_CONF="/usr/local/share/applications/com.google.Chrome.desktop"
    PANEL_XML="/etc/xdg/xdg-xubuntu/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    PANEL_XML_BACKUP="${PANEL_XML}.bkp"
    DEFAULT_XML="/etc/xdg/xdg-xubuntu/xfce4/panel/default.xml"
    DEFAULT_XML_BACKUP="${DEFAULT_XML}.bkp"
    KIOSK_FILE="/etc/xdg/xfce4/kiosk/kioskrc"
    KIOSK_BACKUP="${KIOSK_FILE}.bkp"
    BACKDROP_SRC="/usr/local/seduc/backdrops/seduc/xubuntu-seduc.png"
    DEST="/usr/share/xfce4/backdrops/default.png"

    # Restaura o xfce4-desktop
    [ -f "$XFCE_BACKUP_CONF" ] && cp "$XFCE_BACKUP_CONF" "$XFCE_DESKTOP_CONF"

    # Restaura o Wallpaper
     ln -sf "$BACKDROP_SRC" "$DEST"
    
    # Restaura o lightdm-gtk-greeter
    [ -f "$GREETER_BACKUP_CONF" ] && cp "$GREETER_BACKUP_CONF" "$GREETER_DESKTOP_CONF"
    
    # Restaura o google-chrome
    [ -f "$CHROME_LOCAL_CONF" ] && rm "$CHROME_LOCAL_CONF"
    
    # Restaura o xfce4-panel.xml
    # .ausente: o arquivo não existia antes do perfil laboratório
    if [ -f "$PANEL_XML_BACKUP" ]; then
        cp "$PANEL_XML_BACKUP" "$PANEL_XML"
    elif [ -f "$PANEL_XML.ausente" ]; then
        rm -f "$PANEL_XML"
    fi
    [ -f "$DEFAULT_XML_BACKUP" ] && cp "$DEFAULT_XML_BACKUP" "$DEFAULT_XML"
    
    # Restaura o kiosk
    if [ -f "$KIOSK_BACKUP" ]; then
        cp "$KIOSK_BACKUP" "$KIOSK_FILE"
    fi

} || {
        stop_spinner
        echo "❌ Erro geral ao restaurar o sistema."
        exit 1
    }
stop_spinner
echo "✔ Ok"

echo -n "Limpando as configurações antiga... "
start_spinner

{  
    # Parando o daemon xdsettingsd
    pkill xfsettingsd 2>/dev/null || true

    # Ativando as configurações
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            rm -rf "$user_home/.config/xfce4"
        fi
    done
    sleep 3
} || {
        stop_spinner
        echo "❌ Erro geral ao restaurar o XFCE."
        exit 1
    }
stop_spinner
echo "✔ Ok"

echo -n "Removendo o usuário 'aluno'... "
start_spinner
{
    id -u aluno &>/dev/null && userdel -r aluno >/dev/null 2>&1
    sleep 3
} || {
        stop_spinner
        echo "❌ Erro geral ao remover o usuário 'aluno'."
        exit 1
    }
stop_spinner
echo "✔ Ok"

rm -f "/usr/local/seduc/flags/pos-install"
rm -f "$DEFAULT_XML_BACKUP" "$PANEL_XML_BACKUP" "$PANEL_XML.ausente" "$XFCE_BACKUP_CONF" "$GREETER_BACKUP_CONF" "$KIOSK_BACKUP"

echo "O sistema irá reiniciar em 10 segundos. Pressione Ctrl+C para cancelar."
sleep 10
echo "Reiniciando..."
reboot
