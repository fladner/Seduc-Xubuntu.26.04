#!/usr/bin/env bash

# Assina o seduc_setup.sh e o pacote de arquivos para publicação no GitHub.
# Uso: tools/publicar-seduc-setup.sh <ID-da-chave-GPG> [pasta-do-repositorio]  (padrão: este projeto)
#
# Gera em <repositorio>/scripts/:
#   seduc_setup.sh + seduc_setup.sh.asc
#     cópia de overlay/usr/local/seduc/scripts/seduc_setup.sh
#   seduc-arquivos.tar.gz + seduc-arquivos.tar.gz.asc
#     arquivos de config/arquivos-atualizador.txt, aplicados pelo seduc_setup.sh
#     nas máquinas instaladas. O pacote é reprodutível: sem mudança nos arquivos,
#     sai idêntico e as máquinas não aplicam de novo.
# Depois é só fazer commit e push no repositório.

set -euo pipefail

PROJETO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CHAVE="${1:?Informe o ID da chave GPG}"
REPO="${2:-$PROJETO}"
OVERLAY="$PROJETO/overlay"
ORIGEM="$OVERLAY/usr/local/seduc/scripts/seduc_setup.sh"
LISTA="$PROJETO/config/arquivos-atualizador.txt"
PACOTE="$REPO/scripts/seduc-arquivos.tar.gz"
# Mesmos destinos que o instalar_arquivos do seduc_setup.sh aceita
PERMITIDOS='^(usr/local/seduc/|usr/local/share/applications/|etc/xdg/menus/applications-merged/)'

assinar() {
    gpg --yes --armor --local-user "$CHAVE" --detach-sign --output "$1.asc" "$1"
    # Confere com a mesma chave que vai na ISO
    gpgv --keyring "$PROJETO/config/seduc-updates.gpg" "$1.asc" "$1"
}

gerar_pacote() {
    local TMP CAMINHO
    TMP=$(mktemp -d)

    while read -r CAMINHO; do
        [[ -z "$CAMINHO" || "$CAMINHO" == \#* ]] && continue
        [[ "$CAMINHO" =~ $PERMITIDOS && "$CAMINHO" != *..* ]] ||
            { echo "Caminho fora dos destinos permitidos: $CAMINHO" >&2; return 1; }
        [[ -e "$OVERLAY/$CAMINHO" ]] ||
            { echo "Não existe em overlay/: $CAMINHO" >&2; return 1; }
        (cd "$OVERLAY" && cp -a --parents "$CAMINHO" "$TMP/")
    done < "$LISTA"

    # Versão do pacote: a máquina com sistema mais novo (ISO compilada depois) não aplica
    mkdir -p "$TMP/usr/local/seduc"
    awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' "$ORIGEM" > "$TMP/usr/local/seduc/arquivos.version"

    # Mesmas permissões do build.sh
    find "$TMP" -type d -exec chmod 755 {} +
    find "$TMP" -type f -exec chmod 644 {} +
    find "$TMP" -type f -name '*.sh' -exec chmod 755 {} +
    local SH
    while IFS= read -r -d '' SH; do
        bash -n "$SH" || { echo "Erro de sintaxe: $SH" >&2; return 1; }
    done < <(find "$TMP" -type f -name '*.sh' -print0)

    (cd "$TMP" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort) > "$TMP.lista"
    tar -C "$TMP" --no-recursion --owner=0 --group=0 --numeric-owner \
        --mtime='2026-01-01 00:00Z' --format=gnu -cf - -T "$TMP.lista" | gzip -n -9 > "$PACOTE"
    rm -rf "$TMP" "$TMP.lista"
}

bash -n "$ORIGEM"
mkdir -p "$REPO/scripts"
install -m 755 "$ORIGEM" "$REPO/scripts/seduc_setup.sh"
assinar "$REPO/scripts/seduc_setup.sh"

gerar_pacote
assinar "$PACOTE"

echo "Pronto: $(awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' "$ORIGEM") assinado em $REPO/scripts/"
echo "Pacote de arquivos: $(tar -tzf "$PACOTE" | grep -vc '/$') arquivos, sha256 $(sha256sum "$PACOTE" | cut -c1-16)"
