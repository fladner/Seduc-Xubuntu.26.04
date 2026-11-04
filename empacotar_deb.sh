#!/usr/bin/env bash

# Gera out/seduc-ad-sige_<versão>_amd64.deb para os sabores do Ubuntu 26.04, com
# os mesmos arquivos de AD, impressoras e SIGE que a ISO leva em overlay/.
# Uso: ./empacotar_deb.sh   (não precisa de root; veja pacote/LEIAME.txt)

set -euo pipefail

#####################
## VARIABLE GLOBAL ##
#####################
PROJETO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OVERLAY="$PROJETO/overlay"
MODELOS="$PROJETO/pacote"
INSTALADORES="$PROJETO/debs/instaladores"
SAIDA="$PROJETO/out"
VERSAO="$(cat "$OVERLAY/usr/local/seduc/version")"
DEB="$SAIDA/seduc-ad-sige_${VERSAO}_amd64.deb"

SCRIPTS=(painel_ad.sh ingressar_ad.sh painel_impressora_ad.sh instalar_impressora_ad.sh sige.sh sige_remoto.sh)
ICONES=(sige.png sige-remoto.png)
ATALHOS=(painel_ad painel_impressora_ad sige sige-remoto)
# Fora do Git: o sige.conf tem os endereços e o orant_work.tar.gz é o Oracle Forms
SIGE=(orant_work.tar.gz sige.conf)

##########
## MAIN ##
##########
for ARQ in "${SIGE[@]}"; do
    [[ -r "$INSTALADORES/$ARQ" ]] || { echo "Não encontrado: $INSTALADORES/$ARQ" >&2; exit 1; }
done

RAIZ="$(mktemp -d)"
trap 'rm -rf "$RAIZ"' EXIT
SEDUC="$RAIZ/usr/local/seduc"

for ARQ in "${SCRIPTS[@]}"; do
    install -D -m 755 "$OVERLAY/usr/local/seduc/scripts/$ARQ" "$SEDUC/scripts/$ARQ"
done
for ARQ in "${ICONES[@]}"; do
    install -D -m 644 "$OVERLAY/usr/local/seduc/icones/$ARQ" "$SEDUC/icones/$ARQ"
done
for ARQ in "$OVERLAY"/usr/local/seduc/ad/*; do
    install -D -m 644 "$ARQ" "$SEDUC/ad/$(basename "$ARQ")"
done
for ARQ in "${SIGE[@]}"; do
    install -D -m 644 "$INSTALADORES/$ARQ" "$SEDUC/instaladores/$ARQ"
done
for ARQ in "${ATALHOS[@]}"; do
    install -D -m 644 "$OVERLAY/usr/local/share/applications/$ARQ.desktop" \
        "$RAIZ/usr/local/share/applications/$ARQ.desktop"
done
install -D -m 644 "$OVERLAY/usr/share/polkit-1/actions/br.gov.ce.seduc.impressora-ad.policy" \
    "$RAIZ/usr/share/polkit-1/actions/br.gov.ce.seduc.impressora-ad.policy"
install -D -m 644 "$MODELOS/seduc.menu" "$RAIZ/etc/xdg/menus/applications-merged/seduc.menu"
install -D -m 644 "$MODELOS/seduc.directory" "$RAIZ/usr/share/desktop-directories/seduc.directory"

TAMANHO="$(du -sk "$RAIZ" | cut -f1)"
install -d -m 755 "$RAIZ/DEBIAN"
sed -e "s/@VERSAO@/$VERSAO/" -e "s/@TAMANHO@/$TAMANHO/" "$MODELOS/control" > "$RAIZ/DEBIAN/control"
install -m 755 "$MODELOS/postinst" "$MODELOS/postrm" "$RAIZ/DEBIAN/"
chmod -R go-w "$RAIZ"
chmod 755 "$RAIZ"

mkdir -p "$SAIDA"
dpkg-deb --root-owner-group --build "$RAIZ" "$DEB"
ls -lh "$DEB"
