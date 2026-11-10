#!/usr/bin/env bash

# Central do Suporte SEDUC (menu SEDUC).
# Mostra como ícones os itens de /usr/local/seduc/central.d (um .desktop por item,
# na ordem do nome do arquivo). Itens com X-SEDUC-Acesso=admin só aparecem para
# administradores; TryExec esconde o item quando o programa não está instalado.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.4-0"

#####################
## VARIABLE GLOBAL ##
#####################
ITENS="/usr/local/seduc/central.d"
AD_CONF="/usr/local/seduc/ad/ad.conf"
TITULO="Central do Suporte SEDUC"
ICONE="preferences-system"

###############
## FUNCTIONS ##
###############

# Administrador: grupo sudo ou um dos GRUPOS_ADMIN do AD (ad.conf)
eh_admin() {
    local G A ADMIN=(sudo)

    if [ -r "$AD_CONF" ]; then
        while IFS= read -r -d '' A; do
            [ -n "$A" ] && ADMIN+=("$A")
        done < <( GRUPOS_ADMIN=(); . "$AD_CONF" >/dev/null 2>&1; printf '%s\0' "${GRUPOS_ADMIN[@]}" )
    fi

    # -z: nomes de grupo do AD têm espaço ("domain admins")
    while IFS= read -r -d '' G; do
        G="${G##*\\}"
        for A in "${ADMIN[@]}"; do
            [[ "${G,,}" == "${A,,}" ]] && return 0
        done
    done < <(id -nGz)

    return 1
}

campo() {
    sed -n "s/^$1=//p" "$2" | head -1
}

# Copia para DESTINO os itens que este usuário pode ver
montar_itens() {
    local DESTINO="$1" ADMIN="$2" ARQ ACESSO TRY

    for ARQ in "$ITENS"/*.desktop; do
        [ -f "$ARQ" ] || continue
        ACESSO=$(campo X-SEDUC-Acesso "$ARQ")
        TRY=$(campo TryExec "$ARQ")
        [[ "$ACESSO" == "admin" && "$ADMIN" -ne 1 ]] && continue
        [[ -n "$TRY" && ! -x "$TRY" ]] && continue
        cp "$ARQ" "$DESTINO/"
    done
}

##########
## MAIN ##
##########
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ADMIN=0
eh_admin && ADMIN=1
montar_itens "$TMP" "$ADMIN"

VERSAO=$(cat /usr/local/seduc/version 2>/dev/null || echo "?")
if (( ADMIN )); then
    PERFIL="administrador"
else
    PERFIL="usuário (as ferramentas de administrador ficam ocultas)"
fi

yad --icons --read-dir="$TMP" \
    --title="$TITULO" --window-icon="$ICONE" --center --borders=12 \
    --width=640 --height=400 \
    --single-click --item-width=120 --icon-size=48 \
    --image=seduc-logo --image-on-top \
    --text="<b>$TITULO</b>\nComputador <b>$(hostname)</b>, sistema SEDUC $VERSAO\nVocê entrou como $PERFIL." \
    --button="Fechar:0"

exit 0
