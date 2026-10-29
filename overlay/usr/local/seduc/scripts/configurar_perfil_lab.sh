#!/usr/bin/env bash

set -euo pipefail

SCRIPT_VERSION="1.2-0"

#####################
## VARIABLE GLOBAL ##
#####################
CHROME_OLD="/usr/share/applications/google-chrome.desktop"
FLAG="/usr/local/seduc/flags/pos-install"

######################
## VARIABLE HERDADA ##
######################
LAB="$1"
LAB_ABREV="$2"
LAB_LABEL="$3"

###############
## FUNCTIONS ##
###############
# Função para criar o usuário e senha padrão
criar_user() {
    local USUARIO="aluno"
    local SENHA="aluno"
    local FULLNAME="Aluno"
    # Sem nopasswdlogin: o aluno entra com senha
    local GRUPOS="audio,bluetooth,dialout,netdev,video"

    # Se o usuário já existir ele atualiza.
    if id -u "$USUARIO" &>/dev/null; then
        echo "Usuário '$FULLNAME' já existe. Atualizando..."
    else
        echo "Criando usuário '$USUARIO'..."
        useradd -m -s /bin/bash -c "$FULLNAME" "$USUARIO"
    fi

    echo "${USUARIO}:${SENHA}" | chpasswd

    for g in ${GRUPOS//,/ }; do
        if getent group "$g" >/dev/null; then
            usermod -aG "$g" "$USUARIO"
        fi
    done

    # Instalações da v1.0 deixavam o aluno entrar sem senha
    if id -nG "$USUARIO" | tr ' ' '\n' | grep -qx nopasswdlogin; then
        gpasswd -d "$USUARIO" nopasswdlogin
    fi
}

# Função para definir o serial ou machine-id
get_serial() {
    local SERIAL=""

    for SRC in product_serial chassis_serial; do
        if [[ -r "/sys/class/dmi/id/$SRC" ]]; then
            SERIAL=$(tr -d ' \t\n\r' < "/sys/class/dmi/id/$SRC")

            case "$SERIAL" in
                ""|UNKNOWN|NONE|DEFAULT|TOBEFILLEDBYOEM|OEM)
                    SERIAL=""
                    ;;
                *)
                    break
                    ;;
            esac
        fi
    done

    SERIAL=${SERIAL:-UNKNOWN}

    # Fallback para serial unknown 
    if [[ "$SERIAL" == "UNKNOWN" ]]; then
        if [[ -f /etc/machine-id ]]; then
            SERIAL=$(cut -c1-8 /etc/machine-id)
        else
            SERIAL=$(uuidgen | cut -d- -f1)
        fi
    fi

    SERIAL=$(echo "$SERIAL" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')

    echo "$SERIAL"
}

# função para definir o hostname padronizado
conf_hostname() {
    local SERIAL
    SERIAL=$(get_serial)

    local HOST=$(echo "${LAB_LABEL}-${LAB_ABREV}-${SERIAL}" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cd 'a-z0-9-')
    
    [[ -z "$HOST" ]] && return 1
    
    hostnamectl hostname "$HOST"
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1   $HOST/" /etc/hosts
    fi
}

# Guarda a configuração original em <arquivo>.bkp (só na primeira vez e só se existir)
backup_conf() {
    if [ -f "$1" ] && [ ! -f "$1.bkp" ]; then
        cp "$1" "$1.bkp"
    fi
}

# Aplica as configurações personalizadas do XFCE
conf_desktop() {
       
    # Remove screensaver
    apt remove --purge -y xfce4-screensaver gnome-system-tools >/dev/null 2>&1

    # Backup xfce4-desktop
    local XFCE_DESKTOP_CONF="/etc/xdg/xdg-xubuntu/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    backup_conf "$XFCE_DESKTOP_CONF"
    
    # Backup lightdm-gtk-greeter
    local GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
    backup_conf "$GREETER_CONF"
    
    # Backup do xfce4-panel
    local PANEL_XML="/etc/xdg/xdg-xubuntu/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    local DEFAULT_XML="/etc/xdg/xdg-xubuntu/xfce4/panel/default.xml"
    # O Xubuntu 26.04 não traz xfce4-panel.xml: a marca .ausente avisa o
    # desativar_perfil_lab.sh para apagar o arquivo criado aqui
    if [ ! -f "$PANEL_XML" ] && [ ! -f "$PANEL_XML.bkp" ]; then
        touch "$PANEL_XML.ausente"
    fi
    if [ ! -f "$PANEL_XML.ausente" ]; then
        backup_conf "$PANEL_XML"
    fi
    backup_conf "$DEFAULT_XML"
    
    # Backup do Kiosk
    local KIOSK_FILE="/etc/xdg/xfce4/kiosk/kioskrc"
    backup_conf "$KIOSK_FILE"
    
    # O papel de parede da área de trabalho e o fundo da tela de login
    # continuam os da SEDUC (o laboratório não troca mais para os do aluno)

    # kiosk
    printf '%s\n' \
        '[xfce4-panel]' \
        'CustomizePanel=NONE' \
        '' \
        '[xfce4-session]' \
        'SaveSession=NONE' \
        > "$KIOSK_FILE"
    
    # xfce4-panel.xml    
    if [ -f "$PANEL_XML" ]; then
        sed -i 's|<channel name="xfce4-panel" version="1.0"[^>]*>|<channel name="xfce4-panel" version="1.0" locked="*" unlocked="root">|' "$PANEL_XML"
    else
        cp "$DEFAULT_XML" "$PANEL_XML"
        sed -i 's|<channel name="xfce4-panel" version="1.0"[^>]*>|<channel name="xfce4-panel" version="1.0" locked="*" unlocked="root">|' "$PANEL_XML"
    fi

    # Restart daemon xfsettingsd
    pkill xfsettingsd 2>/dev/null || true
}

# Aplica as configurações do navegador chrome devido a problema no gnome-keyrings
conf_chrome() {
    local CHROME_NEW="/usr/share/applications/com.google.Chrome.desktop"    
    local CHROME_OLD="/usr/share/applications/google-chrome.desktop"
    local CHROME_LOCAL="/usr/local/share/applications/com.google.Chrome.desktop"
    
   
    [ -f "$CHROME_OLD" ] && rm -rf $CHROME_OLD
        SOURCE_DESKTOP="$CHROME_OLD"

    # Atualiza padrão novo e o local se não existir
    cp "$CHROME_NEW" "$CHROME_LOCAL"
        
    # Garante password-store=basic
    if grep -q '^Exec=/usr/bin/google-chrome-stable' "$CHROME_LOCAL" && \
        ! grep -q -- '--password-store=basic' "$CHROME_LOCAL"; then
        sed -i '/^Exec=\/usr\/bin\/google-chrome-stable/ s|$| --password-store=basic|' "$CHROME_LOCAL"
    fi
}

# Limpa as configurações antigas do XFCE para iniciar a nova.
cleanup_homes() {
    for user_home in /home/*; do
        [ -d "$user_home" ] && rm -rf "$user_home/.config/xfce4"
    done
}

##########
## MAIN ##
##########
criar_user
conf_hostname
conf_desktop
conf_chrome
cleanup_homes

# cria flag
mkdir -p "$(dirname "$FLAG")"
touch "$FLAG"
