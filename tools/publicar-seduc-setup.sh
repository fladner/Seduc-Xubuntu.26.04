#!/usr/bin/env bash

# Assina o seduc_setup.sh e os pacotes de atualização para publicação no GitHub.
# Uso: tools/publicar-seduc-setup.sh <ID-da-chave-GPG> [pasta-do-repositorio]  (padrão: este projeto)
#
# Gera em <repositorio>/scripts/:
#   seduc_setup.sh + .asc
#     cópia de overlay/usr/local/seduc/scripts/seduc_setup.sh
#   seduc-sistema.tar.gz + .asc  (seduc_setup.sh 1.6-3 em diante)
#     o overlay/ inteiro, como vai na ISO, mais usr/local/seduc/atualizador/:
#       pacotes-instalar.txt, pacotes-remover.txt e arquivos-remover.txt (de config/)
#       debs.txt: "pacote versão arquivo sha256" dos .deb de config/debs-atualizador.txt
#   debs/<arquivo>.deb
#     os .deb de config/debs-atualizador.txt (o sha256 vai no pacote assinado)
#   seduc-arquivos.tar.gz + .asc  (seduc_setup.sh até 1.6-2)
#     só a parte do overlay que os atualizadores antigos aceitam (usr/local/seduc/,
#     usr/local/share/applications/, etc/xdg/menus/applications-merged/)
# Os pacotes são reprodutíveis: sem mudança, saem idênticos e as máquinas não
# aplicam de novo. Depois é só fazer commit e push no repositório.

set -euo pipefail

PROJETO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CHAVE="${1:?Informe o ID da chave GPG}"
REPO="${2:-$PROJETO}"
OVERLAY="$PROJETO/overlay"
ORIGEM="$OVERLAY/usr/local/seduc/scripts/seduc_setup.sh"
CONFIG="$PROJETO/config"
SAIDA="$REPO/scripts"
# Destinos que o instalar_arquivos dos seduc_setup.sh até 1.6-2 aceita
LEGADO='^(usr/local/seduc/|usr/local/share/applications/|etc/xdg/menus/applications-merged/)'
# O próprio seduc_setup.sh só troca pelo check_update (versão maior e assinatura)
FORA='^usr/local/seduc/scripts/seduc_setup\.sh$'

VERSAO=$(awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' "$ORIGEM")
VERSAO_SISTEMA=$(cat "$OVERLAY/usr/local/seduc/version")

assinar() {
    gpg --yes --armor --local-user "$CHAVE" --detach-sign --output "$1.asc" "$1"
    # Confere com a mesma chave que vai na ISO
    gpgv --keyring "$CONFIG/seduc-updates.gpg" "$1.asc" "$1"
}

# Arquivos e pastas comuns do overlay (os links das unidades do systemd ficam de
# fora: o seduc_setup.sh habilita as unidades seduc-*)
lista_overlay() {
    (cd "$OVERLAY" && find . -mindepth 1 \( -type f -o -type d \) -printf '%P\n') |
        grep -vE "$FORA" | LC_ALL=C sort
}

# Mesmas permissões do build.sh: só root altera; executável continua executável
permissoes() {
    find "$1" -type d -exec chmod 755 {} +
    find "$1" -type f -perm -u+x -exec chmod 755 {} +
    find "$1" -type f ! -perm -u+x -exec chmod 644 {} +
    find "$1" -type f -name '*.sh' -exec chmod 755 {} +
}

# empacotar <pasta> <saida.tar.gz>
empacotar() {
    local SH
    while IFS= read -r -d '' SH; do
        bash -n "$SH" || { echo "Erro de sintaxe: $SH" >&2; return 1; }
    done < <(find "$1" -type f -name '*.sh' -print0)
    (cd "$1" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort) > "$1.lista"
    tar -C "$1" --no-recursion --owner=0 --group=0 --numeric-owner \
        --mtime='2026-01-01 00:00Z' --format=gnu -cf - -T "$1.lista" | gzip -n -9 > "$2"
    rm -f "$1.lista"
}

# copiar_overlay <pasta> [filtro]: o overlay como na ISO
copiar_overlay() {
    local CAMINHO
    while IFS= read -r CAMINHO; do
        [ -n "${2:-}" ] && ! [[ "$CAMINHO" =~ $2 ]] && continue
        if [ -d "$OVERLAY/$CAMINHO" ]; then
            mkdir -p "$1/$CAMINHO"
        else
            mkdir -p "$1/$(dirname "$CAMINHO")"
            cp -p "$OVERLAY/$CAMINHO" "$1/$CAMINHO"
        fi
    done < <(lista_overlay)
    mkdir -p "$1/usr/local/seduc"
    echo "$VERSAO" > "$1/usr/local/seduc/arquivos.version"
    # Data de publicação no lugar da compilação ("Sobre"), como o build.sh faz
    [ -f "$1/usr/local/seduc/scripts/about_system.sh" ] &&
        sed -i "s|^BUILD=.*|BUILD=\"$(date +%d/%m/%Y)\"|" "$1/usr/local/seduc/scripts/about_system.sh"
    permissoes "$1"
}

# Lista sem comentários e linhas vazias
limpa() { sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$1"; }

# Os .deb nossos: copia para scripts/debs/ e escreve debs.txt
publicar_debs() {
    local DEBS_TXT="$1" NOME ARQ PKG VER
    mkdir -p "$SAIDA/debs"
    : > "$DEBS_TXT"
    find "$SAIDA/debs" -maxdepth 1 -name '*.deb' -delete
    while IFS= read -r NOME; do
        [[ "$NOME" == *sige* ]] && { echo "Recusado: $NOME é interno e não vai para o repositório" >&2; return 1; }
        ARQ=$(find "$PROJETO/debs" -maxdepth 1 -name "${NOME}_*.deb" | sort -V | tail -1)
        [ -n "$ARQ" ] || { echo "Sem .deb de $NOME em debs/" >&2; return 1; }
        PKG=$(dpkg-deb -f "$ARQ" Package)
        VER=$(dpkg-deb -f "$ARQ" Version)
        [ "$PKG" = "$NOME" ] || { echo "$ARQ é do pacote $PKG, não $NOME" >&2; return 1; }
        dpkg-deb -c "$ARQ" | grep -q 'sige\.conf' && { echo "Recusado: $ARQ tem sige.conf" >&2; return 1; }
        install -m 644 "$ARQ" "$SAIDA/debs/"
        echo "$PKG $VER $(basename "$ARQ") $(sha256sum "$ARQ" | cut -d' ' -f1)" >> "$DEBS_TXT"
        echo "  .deb: $PKG $VER"
    done < <(limpa "$CONFIG/debs-atualizador.txt")
}

bash -n "$ORIGEM"
# A versão do sistema vai no pacote: tem que ser a mesma do seduc_setup.sh
[ "$VERSAO" = "$VERSAO_SISTEMA" ] ||
    { echo "seduc_setup.sh $VERSAO e overlay/usr/local/seduc/version $VERSAO_SISTEMA diferentes" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$SAIDA"

install -m 755 "$ORIGEM" "$SAIDA/seduc_setup.sh"
assinar "$SAIDA/seduc_setup.sh"

# Sistema completo
mkdir -p "$TMP/sistema"
copiar_overlay "$TMP/sistema"
ATUALIZADOR="$TMP/sistema/usr/local/seduc/atualizador"
mkdir -p "$ATUALIZADOR"
for L in pacotes-instalar pacotes-remover arquivos-remover; do
    limpa "$CONFIG/$L.txt" > "$ATUALIZADOR/$L.txt"
done
publicar_debs "$ATUALIZADOR/debs.txt"
permissoes "$TMP/sistema"
empacotar "$TMP/sistema" "$SAIDA/seduc-sistema.tar.gz"
assinar "$SAIDA/seduc-sistema.tar.gz"

# Atualizadores antigos (até 1.6-2)
mkdir -p "$TMP/legado"
copiar_overlay "$TMP/legado" "$LEGADO"
empacotar "$TMP/legado" "$SAIDA/seduc-arquivos.tar.gz"
assinar "$SAIDA/seduc-arquivos.tar.gz"

echo "Pronto: $VERSAO assinado em $SAIDA/"
for P in seduc-sistema seduc-arquivos; do
    echo "$P.tar.gz: $(tar -tzf "$SAIDA/$P.tar.gz" | grep -vc '/$') arquivos, sha256 $(sha256sum "$SAIDA/$P.tar.gz" | cut -c1-16)"
done
