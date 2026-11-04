#!/usr/bin/env bash

# Abre o SIGE Remoto (área de trabalho remota no servidor da SEDUC), para quem
# está fora do domínio. O usuário padrão fica guardado para a próxima vez.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.3-0"

#####################
## VARIABLE GLOBAL ##
#####################
CONF="/usr/local/seduc/instaladores/sige.conf"
GUARDADO="$HOME/.config/seduc/sige-remoto-usuario"
YAD=(yad --title="SIGE Remoto" --window-icon=/usr/local/seduc/icones/sige-remoto.png --center --borders=12)

##########
## MAIN ##
##########
SIGE_REMOTO_HOST=""
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"
if [[ -z "$SIGE_REMOTO_HOST" ]]; then
    "${YAD[@]}" --image=dialog-error --text="Servidor do SIGE Remoto não configurado em $CONF." --button="OK:0"
    exit 1
fi

ANTERIOR=""
[ -r "$GUARDADO" ] && ANTERIOR=$(cat "$GUARDADO")
USUARIO=$("${YAD[@]}" --entry --width=420 --entry-text="$ANTERIOR" \
    --text="Usuário PADRÃO do SIGE Remoto\n(exemplo: crede16remoto)" \
    --button="Cancelar:1" --button="Conectar:0") || exit 0
[[ -n "$USUARIO" ]] || exit 0

mkdir -p "$(dirname "$GUARDADO")"
printf '%s\n' "$USUARIO" > "$GUARDADO"

if ! rdesktop -g 100% -u "$USUARIO" "$SIGE_REMOTO_HOST"; then
    "${YAD[@]}" --image=dialog-warning --text="A conexão com o SIGE Remoto foi encerrada ou falhou.\nConfira se está na rede SEDUC." --button="OK:0" --width=440
fi
