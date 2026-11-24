#!/usr/bin/env bash

# Proteções da aparência do computador inteiro (Central do Suporte, página aparencia):
#   papel     xfce4_backdrop_monitor (serviço de usuário): devolve o papel de parede SEDUC
#             na hora; Wallpaper Lock (autostart, xfce4_backdrop_default.sh): em cada login
#   tema      seduc-trava-perfil (boot): devolve tema, ícones, janelas, atalhos, energia,
#             idioma, painel e menu de todos os usuários
#   painel    perfil laboratório: kiosk (CustomizePanel=NONE) e canal xfce4-panel travado
# Uso:
#   protecoes_aparencia.sh estado      (sem root) "papel=ativa|desligada", "tema=...",
#                                       "painel=ativa|desligada|sem-laboratorio"
#   protecoes_aparencia.sh desativar   (root, via pkexec) libera as três
#   protecoes_aparencia.sh ativar      (root, via pkexec) volta as três
# O estado fica na marca $MARCA, que o trava_perfil.sh e a unidade do papel de parede
# (ConditionPathExists) consultam; as atualizações do sistema não a apagam.
# Saída: 0 feito | 1 erro | 2 uso errado

set -uo pipefail

SCRIPT_VERSION="1.7-2"

#####################
## VARIABLE GLOBAL ##
#####################
RAIZ="${PROTECOES_RAIZ:-}"
MARCA="$RAIZ/usr/local/seduc/flags/aparencia-livre"
LOG="$RAIZ/usr/local/seduc/logs/protecoes_aparencia.log"
KIOSK="$RAIZ/etc/xdg/xfce4/kiosk/kioskrc"
PANEL_XML="$RAIZ/etc/xdg/xdg-xubuntu/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
MONITOR="xfce4_backdrop_monitor.service"
TRAVA='locked="*" unlocked="root"'

###############
## FUNCTIONS ##
###############
log() { echo "$(date '+%F %T') - $*" >> "$LOG"; }

# Perfil laboratório configurado (as cópias .bkp/.ausente são do configurar_perfil_lab.sh
# e o desativar_perfil_lab.sh as apaga)
laboratorio() {
    [ -f "$KIOSK.bkp" ] || [ -f "$PANEL_XML.bkp" ] || [ -f "$PANEL_XML.ausente" ]
}

painel_travado() {
    grep -qx 'CustomizePanel=NONE' "$KIOSK" 2>/dev/null ||
        grep -qF "$TRAVA" "$PANEL_XML" 2>/dev/null
}

estado() {
    if [ -f "$MARCA" ]; then
        echo "papel=desligada"
        echo "tema=desligada"
    else
        echo "papel=ativa"
        echo "tema=ativa"
    fi
    if painel_travado; then
        echo "painel=ativa"
    elif laboratorio; then
        echo "painel=desligada"
    else
        echo "painel=sem-laboratorio"
    fi
}

# Sessões abertas: "UID usuário" de quem tem o gerenciador de serviços do usuário
# rodando (usuários locais e do domínio; o lightdm e outros do sistema ficam de fora)
sessoes() {
    local D UID_ U
    for D in /run/user/[0-9]*; do
        [ -S "$D/bus" ] || continue
        UID_="${D##*/}"
        (( UID_ >= 1000 )) || continue
        U=$(timeout 10 id -nu "$UID_" 2>/dev/null) || continue
        echo "$UID_ $U"
    done
}

# systemctl --user como o próprio usuário, no barramento da sessão dele (sem o
# systemd-machined, que a imagem não tem); no máximo 15 s por comando
systemctl_usuario() {
    local UID_="$1" U="$2"
    shift 2
    timeout 15 runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UID_" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_/bus" systemctl --user "$@"
}

# monitor_sessoes stop|start: o papel de parede nas sessões abertas
monitor_sessoes() {
    local UID_ U
    while read -r UID_ U; do
        [ -n "$U" ] || continue
        systemctl_usuario "$UID_" "$U" daemon-reload >/dev/null 2>&1 || true
        if systemctl_usuario "$UID_" "$U" "$1" "$MONITOR" >/dev/null 2>&1; then
            log "$U: $MONITOR $1"
        else
            log "$U: não foi possível $1 $MONITOR"
        fi
    done < <(sessoes)
}

liberar_painel() {
    sed -i '/^CustomizePanel=NONE$/d' "$KIOSK" 2>/dev/null || true
    [ -f "$PANEL_XML" ] && sed -i 's| locked="\*" unlocked="root"||' "$PANEL_XML"
    log "Painel do laboratório liberado"
}

# Mesmas travas do configurar_perfil_lab.sh
travar_painel() {
    if [ -f "$KIOSK" ] && grep -qx '\[xfce4-panel\]' "$KIOSK"; then
        grep -qx 'CustomizePanel=NONE' "$KIOSK" ||
            sed -i '/^\[xfce4-panel\]$/a CustomizePanel=NONE' "$KIOSK"
    else
        mkdir -p "$(dirname "$KIOSK")"
        printf '[xfce4-panel]\nCustomizePanel=NONE\n\n' >> "$KIOSK"
    fi
    if [ -f "$PANEL_XML" ] && ! grep -qF "$TRAVA" "$PANEL_XML"; then
        sed -i "s|<channel name=\"xfce4-panel\" version=\"1.0\"[^>]*>|<channel name=\"xfce4-panel\" version=\"1.0\" $TRAVA>|" "$PANEL_XML"
    fi
    log "Painel do laboratório travado"
}

desativar() {
    local PAINEL=0
    painel_travado && PAINEL=1
    mkdir -p "$(dirname "$MARCA")"
    {
        echo "# Proteções da aparência desligadas pela Central do Suporte"
        echo "DATA=$(date '+%d/%m/%Y %H:%M')"
        echo "POR=${PKEXEC_UID:+$(id -nu "$PKEXEC_UID" 2>/dev/null)}"
        echo "PAINEL=$PAINEL"
    } > "$MARCA"
    chmod 644 "$MARCA"
    log "Proteções desligadas (por ${PKEXEC_UID:+$(id -nu "$PKEXEC_UID" 2>/dev/null)})"
    monitor_sessoes stop
    (( PAINEL )) && liberar_painel
    return 0
}

ativar() {
    local PAINEL
    PAINEL=$(sed -n 's/^PAINEL=//p' "$MARCA" 2>/dev/null)
    rm -f "$MARCA"
    log "Proteções religadas (por ${PKEXEC_UID:+$(id -nu "$PKEXEC_UID" 2>/dev/null)})"
    # Só trava de novo se o laboratório continua configurado
    if [ "$PAINEL" = 1 ] && laboratorio; then
        travar_painel
    fi
    monitor_sessoes start
    return 0
}

##########
## MAIN ##
##########
case "${1:-}" in
    estado) estado; exit 0 ;;
    desativar|ativar) ;;
    *) echo "Uso: $0 estado|desativar|ativar" >&2; exit 2 ;;
esac

if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root." >&2
    exit 1
fi
mkdir -p "$(dirname "$LOG")"
INICIO=$(date +%s)
"$1"
log "$1 concluído em $(( $(date +%s) - INICIO )) s"
