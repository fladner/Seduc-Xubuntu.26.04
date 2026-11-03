#!/usr/bin/env bash

# Painel de instalação de tokens e assinadores (menu SEDUC).
# Baseado no instalador de tokens com zenity e no instalador_drivers_token.sh.
# A instalação roda como root no instalar_tokens.sh, via pkexec.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.3-0"

#####################
## VARIABLE GLOBAL ##
#####################
INSTALAR="/usr/local/seduc/scripts/instalar_tokens.sh"
LOG_ROOT="/usr/local/seduc/logs/instalar_tokens.log"
RELATORIO="/usr/local/seduc/logs/instalar_tokens.relatorio"
TITULO="Instalador de Tokens SEDUC"
ICONE="dialog-password"

# Tokens conhecidos: chave|ID USB|Nome
TOKENS=(
    "safenet|0529:0620|Safenet eToken 5100"
    "cryptoid|20a0:4287|mToken CryptoID"
    "starsign|1059:0019|StarSign CUT S (SafeSign / G+D)"
)

# Programas adicionais: chave|Marcado|Nome|Observação
EXTRAS=(
    "logus|TRUE|Assinador Logus|Siafe"
    "serpro|TRUE|Assinador SERPRO|precisa de internet"
    "bry|FALSE|Extensão BRy (Firefox e Chrome)|assinatura BRy"
    "java8|FALSE|Oracle Java 8|precisa de internet"
)

YAD=(yad --title="$TITULO" --window-icon="$ICONE" --center --borders=12)

###############
## FUNCTIONS ##
###############
erro() {
    "${YAD[@]}" --image=dialog-error --text="$1" --button="OK:0" --width=420
}

check_live() {
    if grep -q "casper" /proc/cmdline; then
        erro "O instalador de tokens não funciona no modo de teste (Live).\nInstale o sistema primeiro."
        exit 0
    fi
}

# Primeiro token conhecido conectado na USB
detectar_token() {
    local T CHAVE ID
    for T in "${TOKENS[@]}"; do
        IFS='|' read -r CHAVE ID _ <<< "$T"
        if lsusb | grep -qi "ID $ID"; then
            echo "$CHAVE"
            return 0
        fi
    done
    return 1
}

escolher_token() {
    local DETECTADO T CHAVE ID NOME MARCA SITUACAO TEXTO LINHAS=()
    DETECTADO=$(detectar_token || true)

    for T in "${TOKENS[@]}"; do
        IFS='|' read -r CHAVE ID NOME <<< "$T"
        MARCA=FALSE
        SITUACAO="não conectado"
        if [[ "$CHAVE" == "$DETECTADO" ]]; then
            MARCA=TRUE
            SITUACAO="CONECTADO"
        fi
        LINHAS+=("$MARCA" "$CHAVE" "$NOME" "$SITUACAO")
    done
    [[ -z "$DETECTADO" ]] && MARCA=TRUE || MARCA=FALSE
    LINHAS+=("$MARCA" "nenhum" "Nenhum token (só os programas)" "")

    if [[ -n "$DETECTADO" ]]; then
        TEXTO="<b>Token detectado.</b> Confirme o modelo ou escolha outro:"
    else
        TEXTO="<b>Nenhum token conhecido foi detectado.</b>\nConecte o token e clique em Atualizar, ou escolha o modelo:"
    fi

    "${YAD[@]}" --list --radiolist \
        --width=560 --height=300 \
        --text="$TEXTO" \
        --column="" --column="chave:HD" --column="Token" --column="Situação" \
        --print-column=2 --separator="" \
        --button="Atualizar:2" --button="Cancelar:1" --button="Avançar:0" \
        "${LINHAS[@]}"
}

escolher_extras() {
    local E CHAVE MARCA NOME OBS LINHAS=()
    for E in "${EXTRAS[@]}"; do
        IFS='|' read -r CHAVE MARCA NOME OBS <<< "$E"
        LINHAS+=("$MARCA" "$CHAVE" "$NOME" "$OBS")
    done
    "${YAD[@]}" --list --checklist \
        --width=560 --height=300 \
        --text="<b>Programas adicionais</b>\nMarque o que também deve ser instalado:" \
        --column="" --column="chave:HD" --column="Programa" --column="Observação" \
        --print-column=2 --separator="" \
        --button="Voltar:2" --button="Cancelar:1" --button="Instalar:0" \
        "${LINHAS[@]}"
}

nome_token() {
    local T CHAVE NOME
    for T in "${TOKENS[@]}"; do
        IFS='|' read -r CHAVE _ NOME <<< "$T"
        [[ "$CHAVE" == "$1" ]] && { echo "$NOME"; return; }
    done
    echo "Nenhum"
}

instalar() {
    local TOKEN="$1"; shift
    local STATUS_ARQ STATUS
    STATUS_ARQ=$(mktemp)

    ( pkexec "$INSTALAR" "$TOKEN" "$@"; echo $? > "$STATUS_ARQ" ) \
        | "${YAD[@]}" --progress --auto-close --no-buttons \
            --width=480 --text="Instalando, aguarde..." --percentage=0

    STATUS=$(cat "$STATUS_ARQ" 2>/dev/null || echo 1)
    rm -f "$STATUS_ARQ"
    return "$STATUS"
}

mostrar_relatorio() {
    local STATUS="$1" IMAGEM TEXTO LINHAS=() ITEM SITUACAO
    if [ -s "$RELATORIO" ]; then
        while IFS='|' read -r ITEM SITUACAO; do
            LINHAS+=("$ITEM" "$SITUACAO")
        done < "$RELATORIO"
    fi

    case "$STATUS" in
        0)   IMAGEM=dialog-information; TEXTO="<b>Instalação concluída.</b>\nSe instalou extensões, feche e abra os navegadores." ;;
        126|127) erro "A senha do administrador não foi confirmada.\nNada foi instalado."; return ;;
        *)   IMAGEM=dialog-warning; TEXTO="<b>Algo não foi instalado.</b>\nDetalhes em $LOG_ROOT" ;;
    esac

    if (( ${#LINHAS[@]} == 0 )); then
        "${YAD[@]}" --image="$IMAGEM" --text="$TEXTO" --button="OK:0" --width=420
        return
    fi
    "${YAD[@]}" --list --image="$IMAGEM" --text="$TEXTO" \
        --width=560 --height=300 --no-selection \
        --column="Item" --column="Resultado" \
        --button="OK:0" "${LINHAS[@]}"
}

##########
## MAIN ##
##########
check_live

while :; do
    TOKEN=$(escolher_token); RET=$?
    case "$RET" in
        0) [[ -n "$TOKEN" ]] && break ;;
        2) continue ;;
        *) exit 0 ;;
    esac
done

while :; do
    SELECAO=$(escolher_extras); RET=$?
    case "$RET" in
        0) break ;;
        2) exec "$0" ;;
        *) exit 0 ;;
    esac
done

EXTRAS_ESCOLHIDOS=()
while IFS= read -r E; do
    [[ -n "$E" ]] && EXTRAS_ESCOLHIDOS+=("$E")
done <<< "$SELECAO"

if [[ "$TOKEN" == "nenhum" && ${#EXTRAS_ESCOLHIDOS[@]} -eq 0 ]]; then
    erro "Nenhuma opção selecionada."
    exit 0
fi

instalar "$TOKEN" "${EXTRAS_ESCOLHIDOS[@]}"
mostrar_relatorio $?
