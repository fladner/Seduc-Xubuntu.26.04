#!/usr/bin/env bash

# Trava o perfil XFCE de todos os usuários: a cada boot, antes da tela de
# login, devolve o padrão da SEDUC para painel, menu, tema, ícones, bordas e
# efeitos das janelas, atalhos, energia, protetor de tela, teclado e idioma.
# Baseado no trava-tema.sh (Carlos Renê - CREDE16 / Tadeu Fladiner - ASTIN).
# O papel de parede fica com o xfce4_backdrop_monitor.
# Uso: trava_perfil.sh [raiz]   (raiz só para teste; padrão /)

set -euo pipefail

SCRIPT_VERSION="1.1-0"

#####################
## VARIABLE GLOBAL ##
#####################
RAIZ="${1:-}"
XDG_SEDUC="$RAIZ/etc/xdg/xdg-xubuntu/xfce4"
XDG_XFCE="$RAIZ/etc/xdg/xfce4"
ACCOUNTS="$RAIZ/var/lib/AccountsService/users"
LOG="$RAIZ/usr/local/seduc/logs/trava_perfil.log"

# Canais xfconf devolvidos ao padrão do sistema
CANAIS=(
    xsettings                   # tema, ícones, fontes, cursor
    xfwm4                       # bordas, tema e efeitos das janelas, bordas da tela
    xfce4-desktop               # ícones e menu da área de trabalho
    xfce4-keyboard-shortcuts    # atalhos de teclado
    xfce4-screensaver           # protetor de tela (60 minutos)
    xfce4-power-manager         # energia e desligamento da tela
    xfce4-notifyd               # notificações
    xfce4-session               # sessão
)

# Canais sem padrão no sistema: o arquivo do usuário é apagado
APAGAR=(
    keyboard-layout             # layout do teclado (volta ao /etc/default/keyboard)
)

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1

echo "===== $(date) - versão $SCRIPT_VERSION ====="

###############
## FUNCTIONS ##
###############
# Padrão do canal: xdg-xubuntu tem prioridade sobre o xfce4
padrao_canal() {
    local ARQ
    for ARQ in "$XDG_SEDUC/xfconf/xfce-perchannel-xml/$1.xml" \
               "$XDG_XFCE/xfconf/xfce-perchannel-xml/$1.xml"; do
        if [ -f "$ARQ" ]; then
            echo "$ARQ"
            return 0
        fi
    done
    return 1
}

# Padrão do painel: o perfil laboratório grava xfce4-panel.xml travado
padrao_painel() {
    padrao_canal xfce4-panel || {
        local ARQ
        for ARQ in "$XDG_SEDUC/panel/default.xml" "$XDG_XFCE/panel/default.xml"; do
            if [ -f "$ARQ" ]; then
                echo "$ARQ"
                return 0
            fi
        done
        return 1
    }
}

padrao_whisker() {
    local ARQ
    for ARQ in "$XDG_SEDUC/whiskermenu/defaults.rc" "$XDG_XFCE/whiskermenu/defaults.rc"; do
        if [ -f "$ARQ" ]; then
            echo "$ARQ"
            return 0
        fi
    done
    return 1
}

# Copia o padrão para o perfil com o dono certo
copiar() {
    local ORIGEM="$1" DESTINO="$2" DONO="$3"
    install -d -o "${DONO%%:*}" -g "${DONO##*:}" -m 755 "$(dirname "$DESTINO")"
    install -o "${DONO%%:*}" -g "${DONO##*:}" -m 644 "$ORIGEM" "$DESTINO"
}

# Idioma escolhido na tela de login (AccountsService e ~/.dmrc)
travar_idioma() {
    local U="$1" UHOME="$2"
    if [ -f "$ACCOUNTS/$U" ]; then
        sed -i '/^Language=/d;/^FormatsLocale=/d' "$ACCOUNTS/$U"
    fi
    if [ -f "$UHOME/.dmrc" ]; then
        sed -i '/^Language=/d;/^Langlist=/d' "$UHOME/.dmrc"
    fi
    if [ -f "$UHOME/.pam_environment" ]; then
        sed -i -E '/^(LANG|LANGUAGE|LC_[A-Z_]+)[[:space:]=]/d' "$UHOME/.pam_environment"
    fi
}

travar_usuario() {
    local U="$1" UHOME="$2" DONO="$3"
    local XFCE="$UHOME/.config/xfce4"
    local XML="$XFCE/xfconf/xfce-perchannel-xml"
    local C ORIGEM

    for C in "${CANAIS[@]}"; do
        if ORIGEM=$(padrao_canal "$C"); then
            copiar "$ORIGEM" "$XML/$C.xml" "$DONO"
        fi
    done

    for C in "${APAGAR[@]}"; do
        rm -f "$XML/$C.xml"
    done

    # Painel: os plugins antigos (lançadores, menu) saem junto
    if ORIGEM=$(padrao_painel); then
        rm -rf "$XFCE/panel"
        copiar "$ORIGEM" "$XML/xfce4-panel.xml" "$DONO"
        if ORIGEM=$(padrao_whisker); then
            copiar "$ORIGEM" "$XFCE/panel/whiskermenu-1.rc" "$DONO"
        fi
    fi

    travar_idioma "$U" "$UHOME"
    echo "$U: perfil restaurado"
}

##########
## MAIN ##
##########
if grep -q "casper" /proc/cmdline 2>/dev/null && [ -z "$RAIZ" ]; then
    echo "Ambiente Live detectado. Abortando..."
    exit 0
fi

while IFS=: read -r U _ UID_ GID_ _ UHOME _; do
    (( UID_ >= 1000 && UID_ < 60000 )) || continue
    UHOME="$RAIZ$UHOME"
    # Só perfis que já entraram no XFCE; os novos nascem com o padrão
    [ -d "$UHOME/.config/xfce4" ] || continue
    travar_usuario "$U" "$UHOME" "$UID_:$GID_" || echo "$U: falhou"
done < "$RAIZ/etc/passwd"
