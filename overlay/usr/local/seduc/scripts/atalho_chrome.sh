#!/usr/bin/env bash

# Gera os atalhos do Google Chrome em /usr/local/share/applications, que têm
# prioridade sobre os do pacote em /usr/share/applications:
#   com.google.Chrome.desktop  visível; é o usado no painel e no menu Whisker
#   google-chrome.desktop      oculto, só para não aparecer o Chrome duas vezes
# Os dois abrem com --password-store=basic (problema do gnome-keyring).
# O pacote do Chrome traz o com.google.Chrome.desktop com NoDisplay=true,
# por isso ele não pode ser copiado como está.
# Uso: atalho_chrome.sh [raiz]   (raiz para o build/teste; padrão /)

set -euo pipefail

SCRIPT_VERSION="1.2-0"

#####################
## VARIABLE GLOBAL ##
#####################
RAIZ="${1:-}"
PACOTE="$RAIZ/usr/share/applications"
LOCAL="$RAIZ/usr/local/share/applications"

##########
## MAIN ##
##########
ORIGEM=""
for ARQ in "$PACOTE/google-chrome.desktop" "$PACOTE/com.google.Chrome.desktop"; do
    if [ -f "$ARQ" ]; then
        ORIGEM="$ARQ"
        break
    fi
done

if [ -z "$ORIGEM" ]; then
    echo "Google Chrome não instalado. Nada a fazer."
    exit 0
fi

mkdir -p "$LOCAL"

# Sem NoDisplay e com --password-store=basic em todos os Exec (uma vez só)
sed -e '/^NoDisplay=/d' \
    -e 's|^Exec=/usr/bin/google-chrome-stable\( --password-store=basic\)*|Exec=/usr/bin/google-chrome-stable --password-store=basic|' \
    "$ORIGEM" > "$LOCAL/com.google.Chrome.desktop"

# Mesmo atalho, oculto do menu (NoDisplay só na seção [Desktop Entry])
sed -e '0,/^Type=Application$/s//Type=Application\nNoDisplay=true/' \
    "$LOCAL/com.google.Chrome.desktop" > "$LOCAL/google-chrome.desktop"

chmod 644 "$LOCAL/com.google.Chrome.desktop" "$LOCAL/google-chrome.desktop"
echo "Atalhos do Chrome gerados em $LOCAL"
