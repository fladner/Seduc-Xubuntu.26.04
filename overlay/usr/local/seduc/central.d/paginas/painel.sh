#!/usr/bin/env bash

# Página "Restaurar painel e tela" da Central do Suporte: devolve o padrão SEDUC do
# painel e menu, da área de trabalho, da aparência e dos monitores do usuário, na hora,
# sem sair da sessão.
#   pagina     opções
#   restaurar  tarefa: guarda ~/.config/xfce4 em ~/.local/share/seduc-backup-painel/<data>/,
#              copia os padrões (os mesmos do trava_perfil.sh, que faz isso a cada boot
#              só para os usuários locais; os do AD não passam por ele) e reinicia o
#              painel, a área de trabalho, o xfsettingsd e o xfwm4
# Roda como o próprio usuário: só mexe no perfil dele. Antes, pede a senha do
# administrador (técnico da CREDE) pelo confirmar_tecnico.sh.

set -uo pipefail
. "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/central_pagina.sh"

XDG_SEDUC="${PADRAO_RAIZ:-}/etc/xdg/xdg-xubuntu/xfce4"
XDG_XFCE="${PADRAO_RAIZ:-}/etc/xdg/xfce4"
XFCE="$HOME/.config/xfce4"
XML="$XFCE/xfconf/xfce-perchannel-xml"
BACKUP_BASE="$HOME/.local/share/seduc-backup-painel"
BACKUPS_GUARDADOS=3

# Aparência: os canais do trava_perfil.sh que o usuário enxerga
APARENCIA=(xsettings xfwm4 xfce4-keyboard-shortcuts xfce4-notifyd)

###############
## FUNCTIONS ##
###############

# Padrão de um canal xfconf: xdg-xubuntu tem prioridade sobre o xfce4
padrao_canal() {
    local ARQ
    for ARQ in "$XDG_SEDUC/xfconf/xfce-perchannel-xml/$1.xml" \
               "$XDG_XFCE/xfconf/xfce-perchannel-xml/$1.xml"; do
        [ -f "$ARQ" ] && { echo "$ARQ"; return 0; }
    done
    return 1
}

# Painel: no laboratório o xfce4-panel.xml travado; senão, o default.xml do painel
padrao_painel() {
    padrao_canal xfce4-panel && return 0
    local ARQ
    for ARQ in "$XDG_SEDUC/panel/default.xml" "$XDG_XFCE/panel/default.xml"; do
        [ -f "$ARQ" ] && { echo "$ARQ"; return 0; }
    done
    return 1
}

padrao_whisker() {
    local ARQ
    for ARQ in "$XDG_SEDUC/whiskermenu/defaults.rc" "$XDG_XFCE/whiskermenu/defaults.rc"; do
        [ -f "$ARQ" ] && { echo "$ARQ"; return 0; }
    done
    return 1
}

# Canal do usuário volta ao padrão (sem padrão no sistema, o do usuário sai)
restaurar_canal() {
    local ORIGEM
    mkdir -p "$XML"
    if ORIGEM=$(padrao_canal "$1"); then
        cp "$ORIGEM" "$XML/$1.xml" && echo "  $1: padrão SEDUC"
    else
        rm -f "$XML/$1.xml" && echo "  $1: padrão do sistema"
    fi
}

meu() { pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1; }

# Programa da sessão, solto da tarefa (continua depois que ela termina)
iniciar() { setsid -f "$@" >/dev/null 2>&1 < /dev/null; }

# O xfconfd grava no disco o que tem na memória quando sai: encerrar antes de trocar
# os arquivos (ele volta sozinho, pelo D-Bus, no primeiro pedido)
parar_xfconfd() {
    local I
    pkill -u "$(id -u)" -x xfconfd 2>/dev/null || return 0
    for I in $(seq 1 10); do
        meu xfconfd || return 0
        sleep 0.5
    done
}

limpar_backups() {
    [ -d "$BACKUP_BASE" ] || return 0
    find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | head -n -"$BACKUPS_GUARDADOS" |
        while IFS= read -r D; do rm -rf "$D"; done
}

pagina() {
    p "Devolve o padrão da SEDUC para o painel, a área de trabalho e a aparência, para quando o painel some, o menu fica errado, os ícones da área de trabalho bagunçam ou a tela fica com a resolução errada. Vale na hora, sem sair da sessão."
    formulario_tarefa restaurar
    grupo "O que restaurar"
    marcar painel "Painel e menu" 1
    marcar area "Área de trabalho: ícones e papel de parede" 1
    marcar aparencia "Aparência: tema, ícones, fontes, janelas e atalhos de teclado" 1
    marcar monitores "Monitores: resolução recomendada de cada tela (com dois monitores, a mesma imagem nos dois)"
    fim_grupo
    secundario "Só o técnico da CREDE restaura: o sistema pede a senha do administrador. Os lançadores e itens que você acrescentou ao painel saem. A configuração atual é guardada em $BACKUP_BASE (as $BACKUPS_GUARDADOS últimas restaurações)."
    botao "Restaurar"
    fim_formulario
}

restaurar() {
    local PAINEL AREA APAR MON DESTINO ORIGEM C NOMES=()
    PAINEL=$(campo painel); AREA=$(campo area); APAR=$(campo aparencia); MON=$(campo monitores)
    if [ "$PAINEL$AREA$APAR$MON" = "" ]; then
        aviso_fim "Marque pelo menos uma opção."
        return 1
    fi

    confirmar_tecnico restaurar-painel || return 1
    mensagem "Guardando a configuração atual..."; progresso 5
    DESTINO="$BACKUP_BASE/$(date +%Y%m%d-%H%M%S)"
    if [ -d "$XFCE" ]; then
        mkdir -p "$DESTINO" && cp -a "$XFCE" "$DESTINO/" && echo "Cópia em $DESTINO"
    fi

    mensagem "Parando o painel..."; progresso 20
    [ "$PAINEL" = 1 ] && meu xfce4-panel && { xfce4-panel --quit 2>/dev/null; sleep 1; }
    parar_xfconfd

    mensagem "Devolvendo o padrão..."; progresso 45
    if [ "$PAINEL" = 1 ]; then
        echo "Painel e menu:"
        if ORIGEM=$(padrao_painel); then
            rm -rf "$XFCE/panel"
            mkdir -p "$XML" "$XFCE/panel"
            cp "$ORIGEM" "$XML/xfce4-panel.xml" && echo "  xfce4-panel: padrão SEDUC"
            ORIGEM=$(padrao_whisker) && cp "$ORIGEM" "$XFCE/panel/whiskermenu-1.rc" && echo "  menu: padrão SEDUC"
        else
            echo "  sem padrão do painel no sistema"
        fi
        NOMES+=("painel")
    fi
    if [ "$AREA" = 1 ]; then
        echo "Área de trabalho:"
        restaurar_canal xfce4-desktop
        NOMES+=("área de trabalho")
    fi
    if [ "$APAR" = 1 ]; then
        echo "Aparência:"
        for C in "${APARENCIA[@]}"; do restaurar_canal "$C"; done
        NOMES+=("aparência")
    fi
    if [ "$MON" = 1 ]; then
        echo "Monitores:"
        rm -f "$XML/displays.xml" && echo "  configuração dos monitores apagada"
        NOMES+=("monitores")
    fi

    mensagem "Reiniciando o painel e a área de trabalho..."; progresso 75
    if [ -z "${DISPLAY:-}" ]; then
        echo "Sem sessão gráfica: vale no próximo login."
    else
        if [ "$MON" = 1 ]; then
            xrandr --auto && echo "Monitores na resolução recomendada"
        fi
        if [ "$APAR" = 1 ] || [ "$MON" = 1 ]; then
            iniciar xfsettingsd --replace && echo "xfsettingsd reiniciado"
        fi
        if [ "$APAR" = 1 ]; then
            iniciar xfwm4 --replace && echo "xfwm4 reiniciado"
        fi
        if [ "$AREA" = 1 ]; then
            meu xfdesktop && { xfdesktop --quit 2>/dev/null; sleep 1; }
            iniciar xfdesktop && echo "Área de trabalho reiniciada"
        fi
        if [ "$PAINEL" = 1 ]; then
            iniciar xfce4-panel && echo "Painel reiniciado"
        fi
    fi

    limpar_backups
    progresso 100
    local LISTA="${NOMES[0]}"
    for C in "${NOMES[@]:1}"; do LISTA="$LISTA, $C"; done
    LISTA=$(printf '%s' "$LISTA" | sed 's/\(.*\), /\1 e /')
    aviso_fim "Padrão SEDUC restaurado: ${LISTA}. Configuração anterior guardada em $DESTINO."
}

##########
## MAIN ##
##########
case "${1:-pagina}" in
    pagina)    pagina ;;
    restaurar) restaurar ;;
    *) erro "Ação desconhecida."; exit 1 ;;
esac
