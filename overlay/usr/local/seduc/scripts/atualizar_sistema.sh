#!/usr/bin/env bash

# "Atualizar o sistema" da Central do Suporte SEDUC.
# A atualização roda como root no atualizar_sistema_root.sh, via pkexec,
# e a saída aparece na janela enquanto acontece.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.4-0"

#####################
## VARIABLE GLOBAL ##
#####################
ATUALIZAR="/usr/local/seduc/scripts/atualizar_sistema_root.sh"
LOG_ROOT="/usr/local/seduc/logs/atualizar_sistema.log"
TITULO="Atualizar o sistema"
ICONE="system-software-update"

YAD=(yad --title="$TITULO" --window-icon="$ICONE" --center --borders=12)

##########
## MAIN ##
##########
if grep -q casper /proc/cmdline; then
    "${YAD[@]}" --image=dialog-information --button="OK:0" \
        --text="No modo live (pendrive) o sistema não é atualizado."
    exit 0
fi

"${YAD[@]}" --image="$ICONE" --width=460 \
    --text="<b>Atualizar todo o sistema</b>\n\nInstala as atualizações de todos os programas e do sistema SEDUC. Pode levar alguns minutos e precisa de internet.\n\nA senha do administrador será pedida a seguir." \
    --button="Cancelar:1" --button="Atualizar:0" || exit 0

STATUS_ARQ=$(mktemp)
echo 1 > "$STATUS_ARQ"

( pkexec "$ATUALIZAR"; echo $? > "$STATUS_ARQ" ) \
    | "${YAD[@]}" --text-info --tail --width=720 --height=460 \
        --fontname="Monospace 9" \
        --text="Atualizando... Pode fechar esta janela: a atualização continua até o fim." \
        --button="Fechar:0"

STATUS=$(cat "$STATUS_ARQ" 2>/dev/null || echo 1)
rm -f "$STATUS_ARQ"

case "$STATUS" in
    0)
        if [ -f /var/run/reboot-required ]; then
            "${YAD[@]}" --image=dialog-information --width=420 \
                --text="<b>Sistema atualizado.</b>\n\nReinicie o computador para concluir a atualização." \
                --button="Depois:1" --button="Reiniciar agora:0" && systemctl reboot
        else
            "${YAD[@]}" --image=dialog-information --width=420 --button="OK:0" \
                --text="<b>Sistema atualizado.</b>"
        fi
        ;;
    126|127)
        "${YAD[@]}" --image=dialog-error --width=420 --button="OK:0" \
            --text="A senha do administrador não foi confirmada.\nNada foi atualizado."
        ;;
    *)
        "${YAD[@]}" --image=dialog-warning --width=460 --button="OK:0" \
            --text="<b>A atualização terminou com erros.</b>\n\nDetalhes em $LOG_ROOT"
        ;;
esac
exit 0
