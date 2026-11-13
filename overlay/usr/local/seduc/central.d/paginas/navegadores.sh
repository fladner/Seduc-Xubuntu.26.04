#!/usr/bin/env bash

# Página "Restaurar navegadores" da Central do Suporte: Firefox e Google Chrome do
# usuário voltam à configuração inicial, como o "Restaurar o Firefox" do próprio Firefox.
#   pagina     navegadores, perfis e cópias guardadas
#   restaurar  tarefa: fecha o navegador (se pedido), guarda o perfil inteiro em
#              ~/.local/share/seduc-backup-navegadores/<data>/ e cria um perfil limpo;
#              no modo "manter", devolve favoritos, histórico, senhas, cookies e
#              preenchimento automático. Extensões, configurações e caches recomeçam
#              (as extensões obrigatórias da SEDUC voltam pelas políticas).
# Roda como o próprio usuário: só mexe no perfil dele. Antes, pede a senha do
# administrador (técnico da CREDE) pelo confirmar_tecnico.sh.

set -uo pipefail
. "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/central_pagina.sh"

BACKUP_BASE="$HOME/.local/share/seduc-backup-navegadores"
BACKUPS_GUARDADOS=3

# Firefox 147+ usa ~/.config/mozilla; os perfis antigos ficam em ~/.mozilla; o snap, no snap
FF_BASES=("$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox")
FF_CACHE="$HOME/.cache/mozilla/firefox"
# O que o "Restaurar o Firefox" mantém
FF_MANTER=(places.sqlite favicons.sqlite key4.db logins.json cookies.sqlite formhistory.sqlite
           persdict.dat autofill-profiles.json)

CH_BASE="$HOME/.config/google-chrome"
CH_CACHE="$HOME/.cache/google-chrome"
# "Local State" e "First Run" ficam na pasta do Chrome; o resto, em cada perfil
CH_MANTER_RAIZ=("Local State" "First Run")
CH_MANTER=(Bookmarks Bookmarks.bak History Favicons "Login Data" "Login Data For Account"
           "Web Data" Cookies Network/Cookies)

###############
## FUNCTIONS ##
###############

# Pastas dos perfis do Firefox (profiles.ini de cada base)
perfis_firefox() {
    local BASE
    for BASE in "${FF_BASES[@]}"; do
        [ -f "$BASE/profiles.ini" ] || continue
        awk -F= -v base="$BASE" '
            /^\[/ { if (p != "") print (rel == "0" ? p : base "/" p); p = ""; rel = "1"; next }
            $1 == "Path" { p = substr($0, 6) }
            $1 == "IsRelative" { rel = $2 }
            END { if (p != "") print (rel == "0" ? p : base "/" p) }
        ' "$BASE/profiles.ini" | while IFS= read -r P; do
            [ -d "$P" ] && echo "$P"
        done
    done | sort -u
}

perfis_chrome() {
    local P
    for P in "$CH_BASE/Default" "$CH_BASE"/Profile\ *; do
        [ -d "$P" ] && echo "$P"
    done
}

# Processos do usuário (o Chrome da própria Central, perfil em ~/.cache, não conta)
pids_firefox() { pgrep -u "$(id -u)" -x 'firefox|firefox-bin|firefox-esr' || true; }
pids_chrome() {
    local PID
    for PID in $(pgrep -u "$(id -u)" -x 'chrome' || true); do
        tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null | grep -q 'seduc-central-suporte' && continue
        echo "$PID"
    done
}

# fechar "Nome" pids...: pede para fechar e, depois de 15 s, encerra
fechar() {
    local NOME="$1" I
    shift
    [ $# -gt 0 ] || return 0
    echo "Fechando o $NOME..."
    kill -TERM "$@" 2>/dev/null
    for I in $(seq 1 15); do
        kill -0 "$@" 2>/dev/null || return 0
        sleep 1
    done
    kill -KILL "$@" 2>/dev/null
    sleep 1
}

# copiar_mantidos ORIGEM DESTINO arquivos...: os arquivos (e o -wal/-journal deles)
copiar_mantidos() {
    local DE="$1" PARA="$2" A X
    shift 2
    for A in "$@"; do
        for X in "$A" "$A-wal" "$A-journal"; do
            [ -f "$DE/$X" ] || continue
            mkdir -p "$PARA/$(dirname "$X")"
            cp -a "$DE/$X" "$PARA/$X" && [ "$X" = "$A" ] && echo "  mantido: $A"
        done
    done
}

restaurar_firefox() {
    local MODO="$1" DESTINO="$2" P N=0 COPIA
    while IFS= read -r P; do
        [ -n "$P" ] || continue
        N=$((N + 1))
        COPIA="$DESTINO/firefox/$(basename "$P")"
        [ -e "$COPIA" ] && COPIA="$COPIA-$N"
        echo "Perfil do Firefox: $P"
        mkdir -p "$(dirname "$COPIA")"
        mv "$P" "$COPIA" || { echo "  não foi possível guardar o perfil"; return 1; }
        mkdir -p "$P" && chmod 700 "$P"
        [ "$MODO" = manter ] && copiar_mantidos "$COPIA" "$P" "${FF_MANTER[@]}"
        rm -rf "${FF_CACHE:?}/$(basename "$P")"
    done < <(perfis_firefox)
    [ "$N" -gt 0 ] || echo "Firefox: nenhum perfil (ainda não foi aberto); nada a restaurar."
}

restaurar_chrome() {
    local MODO="$1" DESTINO="$2" P
    if [ ! -d "$CH_BASE" ]; then
        echo "Chrome: nenhum perfil (ainda não foi aberto); nada a restaurar."
        return 0
    fi
    echo "Pasta do Chrome: $CH_BASE"
    mkdir -p "$DESTINO"
    mv "$CH_BASE" "$DESTINO/chrome" || { echo "  não foi possível guardar o perfil"; return 1; }
    mkdir -p "$CH_BASE" && chmod 700 "$CH_BASE"
    if [ "$MODO" = manter ]; then
        copiar_mantidos "$DESTINO/chrome" "$CH_BASE" "${CH_MANTER_RAIZ[@]}"
        for P in "$DESTINO/chrome/Default" "$DESTINO/chrome"/Profile\ *; do
            [ -d "$P" ] || continue
            echo "Perfil do Chrome: $(basename "$P")"
            copiar_mantidos "$P" "$CH_BASE/$(basename "$P")" "${CH_MANTER[@]}"
        done
    fi
    rm -rf "${CH_CACHE:?}"
}

# Só as últimas cópias: perfis com cache e extensões ocupam espaço na pasta pessoal
limpar_backups() {
    [ -d "$BACKUP_BASE" ] || return 0
    find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | head -n -"$BACKUPS_GUARDADOS" |
        while IFS= read -r D; do rm -rf "$D"; done
}

pagina() {
    local FF=0 CH=0 NFF NCH
    command -v firefox >/dev/null 2>&1 && FF=1
    command -v google-chrome >/dev/null 2>&1 && CH=1
    NFF=$(perfis_firefox | grep -c .)
    NCH=$(perfis_chrome | grep -c .)

    p "Volta o navegador à configuração inicial, para quando ele estiver lento, com página inicial ou pesquisa trocadas, extensões estranhas ou sites que não abrem."
    tabela_inicio
    if [ "$FF" = 1 ]; then
        linha "Firefox" "$NFF perfil(is)$( [ -n "$(pids_firefox)" ] && echo ", aberto agora")"
    fi
    if [ "$CH" = 1 ]; then
        linha "Google Chrome" "$NCH perfil(is)$( [ -n "$(pids_chrome)" ] && echo ", aberto agora")"
    fi
    tabela_fim

    formulario_tarefa restaurar
    grupo "Navegadores"
    [ "$FF" = 1 ] && marcar firefox "Firefox" 1
    [ "$CH" = 1 ] && marcar chrome "Google Chrome" 1
    fim_grupo
    grupo "O que manter"
    escolha modo manter "Manter favoritos, histórico, senhas e cookies" 1 \
        "(recomendado) apaga extensões, configurações e cache"
    escolha modo zero "Começar do zero" "" \
        "o navegador fica como recém-instalado; nada do perfil antigo volta"
    fim_grupo
    grupo "Antes de restaurar"
    marcar fechar "Fechar o navegador se estiver aberto (abas abertas serão fechadas)" 1
    fim_grupo
    secundario "Só o técnico da CREDE restaura: o sistema pede a senha do administrador. O perfil antigo inteiro é guardado em $BACKUP_BASE (as $BACKUPS_GUARDADOS últimas restaurações), para o suporte recuperar algo se precisar."
    botao "Restaurar"
    fim_formulario
}

restaurar() {
    local MODO DESTINO FEITOS=() PIDS
    MODO=$(campo modo)
    [ "$MODO" = zero ] || MODO=manter
    if [ "$(campo firefox)" != 1 ] && [ "$(campo chrome)" != 1 ]; then
        aviso_fim "Marque pelo menos um navegador."
        return 1
    fi
    confirmar_tecnico restaurar-navegadores || return 1
    DESTINO="$BACKUP_BASE/$(date +%Y%m%d-%H%M%S)"

    if [ "$(campo firefox)" = 1 ]; then
        mensagem "Restaurando o Firefox..."; progresso 10
        mapfile -t PIDS < <(pids_firefox)
        if [ ${#PIDS[@]} -gt 0 ]; then
            if [ "$(campo fechar)" != 1 ]; then
                aviso_fim "O Firefox está aberto. Feche o Firefox ou marque \"Fechar o navegador\" e tente de novo."
                return 1
            fi
            fechar Firefox "${PIDS[@]}"
        fi
        restaurar_firefox "$MODO" "$DESTINO" || { aviso_fim "Não foi possível restaurar o Firefox. Veja os detalhes acima."; return 1; }
        FEITOS+=("Firefox")
    fi

    if [ "$(campo chrome)" = 1 ]; then
        mensagem "Restaurando o Google Chrome..."; progresso 55
        mapfile -t PIDS < <(pids_chrome)
        if [ ${#PIDS[@]} -gt 0 ]; then
            if [ "$(campo fechar)" != 1 ]; then
                aviso_fim "O Google Chrome está aberto. Feche o Chrome ou marque \"Fechar o navegador\" e tente de novo."
                return 1
            fi
            fechar "Google Chrome" "${PIDS[@]}"
        fi
        restaurar_chrome "$MODO" "$DESTINO" || { aviso_fim "Não foi possível restaurar o Google Chrome. Veja os detalhes acima."; return 1; }
        FEITOS+=("Google Chrome")
    fi

    mensagem "Concluindo..."; progresso 95
    limpar_backups
    progresso 100
    local LISTA="${FEITOS[0]} restaurado"
    [ ${#FEITOS[@]} -gt 1 ] && LISTA="${FEITOS[0]} e ${FEITOS[1]} restaurados"
    if [ "$MODO" = manter ]; then
        aviso_fim "$LISTA, com favoritos, histórico, senhas e cookies. Perfil antigo guardado em $DESTINO."
    else
        aviso_fim "$LISTA do zero. Perfil antigo guardado em $DESTINO."
    fi
}

##########
## MAIN ##
##########
case "${1:-pagina}" in
    pagina)    pagina ;;
    restaurar) restaurar ;;
    *) erro "Ação desconhecida."; exit 1 ;;
esac
