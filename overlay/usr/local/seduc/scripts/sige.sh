#!/usr/bin/env bash

# Abre o SIGE (Oracle Forms 5.0, programa Windows de 32 bits) no Wine.
# Na primeira vez de cada usuário prepara o ambiente em ~/.wine-sige com o
# orant_work.tar.gz da ISO (no lugar do antigo sigeInstall.sh da 20.04).
# Os formulários vêm de \\fileserver\sige e \sige5, que o pam_mount só monta
# no login do domínio: fora do AD, o caminho é o SIGE Remoto.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.3-0"

#####################
## VARIABLE GLOBAL ##
#####################
INSTALADORES="/usr/local/seduc/instaladores"
PACOTE="$INSTALADORES/orant_work.tar.gz"
CONF="$INSTALADORES/sige.conf"
PASTA_SIGE="/mnt/sige"
PASTA_SIGE5="/mnt/sige5"
ORANT="C:\\orant"

export WINEPREFIX="$HOME/.wine-sige"
export WINEARCH="win32"
# Sem as perguntas de instalar Mono e Gecko, que o SIGE não usa
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG="-all"

TITULO="SIGE SEDUC"
YAD=(yad --title="$TITULO" --window-icon=/usr/local/seduc/icones/sige.png --center --borders=12)
LOG="$HOME/.cache/seduc-sige.log"

###############
## FUNCTIONS ##
###############
erro() {
    "${YAD[@]}" --image=dialog-error --text="$1" --button="OK:0" --width=480
}

verificar() {
    if ! command -v wine >/dev/null; then
        erro "O Wine não está instalado neste computador."
        exit 1
    fi
    if [[ ! -r "$CONF" || ! -r "$PACOTE" ]]; then
        erro "Arquivos do SIGE não encontrados em $INSTALADORES."
        exit 1
    fi
    if ! mountpoint -q "$PASTA_SIGE" || ! mountpoint -q "$PASTA_SIGE5"; then
        erro "As pastas do SIGE no servidor não estão disponíveis.\n\nEntre com um usuário do domínio, na rede SEDUC.\nSem domínio, use o <b>SIGE Remoto</b>."
        exit 1
    fi
}

preparar() {
    local DRIVE="$WINEPREFIX/drive_c" REG
    wineboot --init || return 1
    wineserver -w || true

    mkdir -p "$DRIVE/PLANILHAS"
    rm -rf "$DRIVE/orant" "$DRIVE/orant_work"
    tar -xzf "$PACOTE" -C "$DRIVE" || return 1
    mv "$DRIVE/orant_work" "$DRIVE/orant" || return 1

    ln -sfn "$PASTA_SIGE5" "$WINEPREFIX/dosdevices/o:"
    ln -sfn "$PASTA_SIGE" "$WINEPREFIX/dosdevices/j:"

    for REG in oracle_novo.reg sige.reg; do
        wine regedit /S "$ORANT\\regs\\$REG" || return 1
    done
    wineserver -w || true
    touch "$WINEPREFIX/.seduc-sige-pronto"
}

##########
## MAIN ##
##########
mkdir -p "$(dirname "$LOG")"
exec >"$LOG" 2>&1
echo "===== $(date) - versão $SCRIPT_VERSION ====="

verificar
# shellcheck source=/dev/null
. "$CONF"

if [[ ! -f "$WINEPREFIX/.seduc-sige-pronto" ]]; then
    STATUS=$(mktemp)
    ( preparar >>"$LOG" 2>&1; echo $? > "$STATUS" ) \
        | "${YAD[@]}" --progress --pulsate --auto-close --no-buttons --width=440 \
            --text="Preparando o SIGE para o primeiro uso, aguarde..."
    if [[ "$(cat "$STATUS")" != "0" ]]; then
        rm -f "$STATUS"
        erro "Não foi possível preparar o SIGE.\nDetalhes em $LOG"
        exit 1
    fi
    rm -f "$STATUS"
fi

cd "$WINEPREFIX/drive_c/orant/BIN" || exit 1
wine "$ORANT\\BIN\\F50RUN32.EXE" "${SIGE_ARGS[@]}"
