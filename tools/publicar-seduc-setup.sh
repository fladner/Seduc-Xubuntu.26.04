#!/usr/bin/env bash

# Assina o seduc_setup.sh para publicação no GitHub.
# Uso: tools/publicar-seduc-setup.sh <ID-da-chave-GPG> [pasta-do-repositorio]  (padrão: este projeto)
#
# Copia overlay/usr/local/seduc/scripts/seduc_setup.sh para
# <repositorio>/scripts/ e gera a assinatura seduc_setup.sh.asc ao lado.
# Depois é só fazer commit e push no repositório.

set -euo pipefail

PROJETO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CHAVE="${1:?Informe o ID da chave GPG}"
REPO="${2:-$PROJETO}"
ORIGEM="$PROJETO/overlay/usr/local/seduc/scripts/seduc_setup.sh"

bash -n "$ORIGEM"
mkdir -p "$REPO/scripts"
install -m 755 "$ORIGEM" "$REPO/scripts/seduc_setup.sh"
gpg --yes --armor --local-user "$CHAVE" --detach-sign \
    --output "$REPO/scripts/seduc_setup.sh.asc" "$REPO/scripts/seduc_setup.sh"

# Confere com a mesma chave que vai na ISO
gpgv --keyring "$PROJETO/config/seduc-updates.gpg" \
    "$REPO/scripts/seduc_setup.sh.asc" "$REPO/scripts/seduc_setup.sh"

echo "Pronto: $(awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' "$ORIGEM") assinado em $REPO/scripts/"
