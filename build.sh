#!/usr/bin/env bash

# Gera a ISO Xubuntu SEDUC a partir da ISO anterior:
#   1. extrai casper/minimal.squashfs
#   2. aplica overlay/ (arquivos SEDUC) por cima
#   3. remove config/arquivos-remover.txt e config/pacotes-remover.txt,
#      instala config/pacotes-instalar.txt e debs/*.deb no chroot
#   4. recria o squashfs e troca só os arquivos alterados na ISO,
#      reaproveitando o boot (BIOS/UEFI) da ISO original
#
# Uso: sudo ./build.sh [ISO_BASE] [VERSAO]
#      sudo RETOMAR=1 ./build.sh   refaz só do passo 4 em diante, usando o
#                                  work/build/rootfs da última compilação

set -euo pipefail

#####################
## VARIABLE GLOBAL ##
#####################
PROJETO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ISO_BASE="${1:-/home/fladner/Downloads/xubuntu-seduc-26.04-v1.0-0-amd64.iso}"
VERSAO="${2:-$(cat "$PROJETO/overlay/usr/local/seduc/version")}"

OVERLAY="$PROJETO/overlay"
PACOTES="$PROJETO/config/pacotes-instalar.txt"
PACOTES_REMOVER="$PROJETO/config/pacotes-remover.txt"
ARQUIVOS_REMOVER="$PROJETO/config/arquivos-remover.txt"
# Chave pública (gpg --export, binária) que assina o seduc_setup.sh no GitHub
CHAVE_ATUALIZADOR="$PROJETO/config/seduc-updates.gpg"
# Chave do repositório do NetMonitor; o pacote instala a própria cópia e o .sources
CHAVE_NETMONITOR="$PROJETO/config/fladnernetworks-archive-keyring.gpg"
DEBS="$PROJETO/debs"
BUILD="$PROJETO/work/build"
ROOTFS="$BUILD/rootfs"
CASPER="$BUILD/casper"
SAIDA="$PROJETO/out"
ISO_NOVA="$SAIDA/xubuntu-seduc-26.04-v${VERSAO}-amd64.iso"
VOLID="Xubuntu SEDUC 26.04 v${VERSAO}"

#########
## LOG ##
#########
log() {
    echo -e "\n[BUILD] $(date '+%T') - $*"
}

erro() {
    echo "[ERRO] $*" >&2
    exit 1
}

###############
## FUNCTIONS ##
###############

check_requisitos() {
    [[ $EUID -eq 0 ]] || erro "Execute com sudo: sudo $0"
    [[ -f "$ISO_BASE" ]] || erro "ISO base não encontrada: $ISO_BASE"
    [[ -f "$CHAVE_NETMONITOR" ]] || erro "Chave do NetMonitor não encontrada: $CHAVE_NETMONITOR"

    local CMD
    for CMD in xorriso unsquashfs mksquashfs rsync chroot md5sum; do
        command -v "$CMD" >/dev/null || erro "Comando ausente: $CMD"
    done

    [[ -e "$ISO_NOVA" ]] && erro "ISO de saída já existe: $ISO_NOVA"
    return 0
}

# Desmonta tudo que estiver montado dentro do rootfs (também em caso de erro)
desmontar_chroot() {
    local PONTO
    [[ -d "$ROOTFS" ]] || return 0

    for PONTO in $(findmnt -rn -o TARGET | grep -F "$ROOTFS/" | sort -r); do
        umount -l "$PONTO" || true
    done
}

limpar_chroot() {
    desmontar_chroot
    rm -f "$ROOTFS/usr/sbin/policy-rc.d"
    rm -f "$ROOTFS/etc/apt/sources.list.d/seduc-build-netmonitor.sources" \
          "$ROOTFS/etc/apt/seduc-build-netmonitor.gpg"
    if [[ -e "$ROOTFS/etc/resolv.conf.seduc-build" || -L "$ROOTFS/etc/resolv.conf.seduc-build" ]]; then
        rm -f "$ROOTFS/etc/resolv.conf"
        mv -f "$ROOTFS/etc/resolv.conf.seduc-build" "$ROOTFS/etc/resolv.conf"
    fi
    # cdrom.sources é usado pelo instalador no modo live: volta para a imagem
    if [[ -e "$ROOTFS/etc/apt/cdrom.sources.seduc-build" ]]; then
        mv -f "$ROOTFS/etc/apt/cdrom.sources.seduc-build" "$ROOTFS/etc/apt/sources.list.d/cdrom.sources"
    fi
}

extrair() {
    log "Preparando diretório de build"
    desmontar_chroot
    rm -rf "${BUILD:?}"
    mkdir -p "$CASPER" "$SAIDA"

    log "Extraindo casper e md5sum.txt da ISO base"
    xorriso -osirrox on -indev "$ISO_BASE" \
        -extract /casper/minimal.squashfs "$CASPER/minimal.squashfs" \
        -extract /casper/install-sources.yaml "$CASPER/install-sources.yaml" \
        -extract /md5sum.txt "$BUILD/md5sum.txt" \
        -extract /.disk/info "$BUILD/info"
    chmod u+w "$CASPER"/* "$BUILD/md5sum.txt" "$BUILD/info"

    log "Descompactando minimal.squashfs (demora)"
    unsquashfs -d "$ROOTFS" "$CASPER/minimal.squashfs"
    rm -f "$CASPER/minimal.squashfs"
}

aplicar_overlay() {
    log "Aplicando overlay/"
    rsync -a --chown=root:root --chmod=go-w "$OVERLAY/" "$ROOTFS/"

    # Scripts executados como root: só root pode alterar (v1.0 deixava o grupo adm editar)
    local SEDUC="$ROOTFS/usr/local/seduc"
    chown -R root:root "$SEDUC"
    find "$SEDUC" -type d -exec chmod 755 {} +
    find "$SEDUC" -type f -exec chmod 644 {} +
    chmod 755 "$SEDUC"/scripts/*.sh

    # Logs e flags continuam graváveis pelo administrador (grupo adm), que roda o welcome
    chown root:adm "$SEDUC/logs" "$SEDUC/flags"
    chmod 2775 "$SEDUC/logs" "$SEDUC/flags"

    # Chave pública que valida as atualizações do seduc_setup.sh vindas do GitHub
    if [[ -s "$CHAVE_ATUALIZADOR" ]]; then
        install -D -o root -g root -m 644 "$CHAVE_ATUALIZADOR" "$SEDUC/keys/seduc-updates.gpg"
    else
        log "AVISO: $CHAVE_ATUALIZADOR ausente; o seduc_setup.sh não vai se atualizar"
    fi

    # Data da compilação mostrada em "Informações do Sistema"
    sed -i "s|^BUILD=.*|BUILD=\"$(date +%d/%m/%Y)\"|" "$SEDUC/scripts/about_system.sh"

    local ARQ
    while read -r ARQ; do
        log "Removendo arquivo: $ARQ"
        rm -f "${ROOTFS:?}$ARQ"
    done < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$ARQUIVOS_REMOVER")
}

instalar_pacotes() {
    local LISTA=() DEBS_LISTA=()

    mapfile -t LISTA < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$PACOTES")
    shopt -s nullglob
    DEBS_LISTA=("$DEBS"/*.deb)
    shopt -u nullglob

    if [[ ${#LISTA[@]} -eq 0 && ${#DEBS_LISTA[@]} -eq 0 ]]; then
        log "Nenhum pacote para instalar"
        return 0
    fi

    log "Preparando chroot"
    mount --bind /dev "$ROOTFS/dev"
    mount --bind /dev/pts "$ROOTFS/dev/pts"
    mount -t proc proc "$ROOTFS/proc"
    mount -t sysfs sysfs "$ROOTFS/sys"
    mount -t tmpfs tmpfs "$ROOTFS/run"

    # DNS do host durante o build; o original volta em limpar_chroot
    mv -f "$ROOTFS/etc/resolv.conf" "$ROOTFS/etc/resolv.conf.seduc-build"
    cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

    # Não iniciar serviços dentro do chroot
    printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
    chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"

    # O repositório file:///cdrom só existe com a ISO montada (modo live)
    if [[ -e "$ROOTFS/etc/apt/sources.list.d/cdrom.sources" ]]; then
        mv -f "$ROOTFS/etc/apt/sources.list.d/cdrom.sources" "$ROOTFS/etc/apt/cdrom.sources.seduc-build"
    fi

    # Repositório do NetMonitor só para o build. Nome diferente do arquivo do
    # pacote, que instala o próprio .sources e a chave como conffiles.
    install -m 644 "$CHAVE_NETMONITOR" "$ROOTFS/etc/apt/seduc-build-netmonitor.gpg"
    printf '%s\n' \
        'Types: deb' \
        'URIs: https://apt.fladnernetworks.com.br' \
        'Suites: stable' \
        'Components: main' \
        'Architectures: amd64' \
        'Signed-By: /etc/apt/seduc-build-netmonitor.gpg' \
        > "$ROOTFS/etc/apt/sources.list.d/seduc-build-netmonitor.sources"

    local CHROOT_DEBS=()
    if [[ ${#DEBS_LISTA[@]} -gt 0 ]]; then
        mkdir -p "$ROOTFS/tmp/seduc-debs"
        cp "${DEBS_LISTA[@]}" "$ROOTFS/tmp/seduc-debs/"
        local D
        for D in "${DEBS_LISTA[@]}"; do
            CHROOT_DEBS+=("/tmp/seduc-debs/$(basename "$D")")
        done
    fi

    chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 \
        apt-get update

    # Remove só os pacotes da lista que estão instalados
    local REMOVER=() P
    while read -r P; do
        if chroot "$ROOTFS" dpkg-query -W -f='${db:Status-Abbrev}' "$P" 2>/dev/null | grep -q '^ii'; then
            REMOVER+=("$P")
        fi
    done < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$PACOTES_REMOVER")

    if [[ ${#REMOVER[@]} -gt 0 ]]; then
        log "Removendo: ${REMOVER[*]}"
        chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 \
            apt-get purge -y "${REMOVER[@]}"
    fi

    log "Instalando: ${LISTA[*]} ${CHROOT_DEBS[*]}"
    chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 \
        apt-get install -y --no-install-recommends "${LISTA[@]}" "${CHROOT_DEBS[@]}"

    # O pacote do NetMonitor traz o próprio .sources para o mesmo repositório:
    # com o temporário junto o apt recusa (Signed-By conflitante)
    if [[ -f "$ROOTFS/etc/apt/sources.list.d/fladnernetworks-netmonitor.sources" ]]; then
        rm -f "$ROOTFS/etc/apt/sources.list.d/seduc-build-netmonitor.sources" \
              "$ROOTFS/etc/apt/seduc-build-netmonitor.gpg"
    fi

    # Atualiza tudo para a versão mais nova dos repositórios. O kernel fica:
    # o vmlinuz/initrd da ISO precisam bater com os módulos do squashfs.
    # Arquivos de configuração alterados pelo overlay são mantidos (confold).
    local KERNEL=() K
    for K in linux-generic linux-image-generic linux-headers-generic; do
        if chroot "$ROOTFS" dpkg-query -W -f='${db:Status-Abbrev}' "$K" 2>/dev/null | grep -q '^ii'; then
            KERNEL+=("$K")
        fi
    done
    [[ ${#KERNEL[@]} -gt 0 ]] && chroot "$ROOTFS" apt-mark hold "${KERNEL[@]}"
    log "Atualizando todos os pacotes (kernel mantido: ${KERNEL[*]})"
    chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 \
        apt-get full-upgrade -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
    [[ ${#KERNEL[@]} -gt 0 ]] && chroot "$ROOTFS" apt-mark unhold "${KERNEL[@]}"
    chroot "$ROOTFS" apt-get clean

    # Certificados de usr/local/share/ca-certificates (proxy SEDUC) no console
    chroot "$ROOTFS" update-ca-certificates

    # A imagem é clonada em todas as máquinas: nenhuma identidade pode ir junto
    rm -f "$ROOTFS"/etc/netmonitor-agent/{installation-id,token,config.json}
    rm -rf "$ROOTFS"/root/.config/rustdesk

    rm -rf "$ROOTFS/tmp/seduc-debs"
    rm -rf "$ROOTFS"/var/lib/apt/lists/*
    limpar_chroot
}

gerar_casper() {
    log "Gerando manifest e tamanho"
    chroot "$ROOTFS" dpkg-query -W --showformat='${Package} ${Version}\n' \
        > "$CASPER/minimal.manifest"
    cp "$CASPER/minimal.manifest" "$CASPER/minimal.manifest.full"

    local TAMANHO
    TAMANHO=$(du -sx --block-size=1 "$ROOTFS" | cut -f1)
    echo "$TAMANHO" > "$CASPER/minimal.size"
    sed -i "s/^\([[:space:]]*size:\).*/\1 $TAMANHO/" "$CASPER/install-sources.yaml"

    sed -i "s/ - Release / - SEDUC v${VERSAO} - Release /" "$BUILD/info"

    log "Compactando minimal.squashfs (xz, demora bastante)"
    mksquashfs "$ROOTFS" "$CASPER/minimal.squashfs" \
        -noappend -comp xz -Xbcj x86 -b 1M
}

atualizar_md5() {
    log "Atualizando md5sum.txt"
    local ARQ SOMA
    for ARQ in minimal.squashfs minimal.manifest minimal.manifest.full minimal.size install-sources.yaml; do
        SOMA=$(md5sum "$CASPER/$ARQ" | cut -d' ' -f1)
        sed -i "s|^[0-9a-f]\{32\}  \./casper/$ARQ\$|$SOMA  ./casper/$ARQ|" "$BUILD/md5sum.txt"
    done
    SOMA=$(md5sum "$BUILD/info" | cut -d' ' -f1)
    sed -i "s|^[0-9a-f]\{32\}  \./\.disk/info\$|$SOMA  ./.disk/info|" "$BUILD/md5sum.txt"
}

gerar_iso() {
    log "Gerando $ISO_NOVA"
    local MAPS=() ARQ
    for ARQ in minimal.squashfs minimal.manifest minimal.manifest.full minimal.size install-sources.yaml; do
        MAPS+=(-map "$CASPER/$ARQ" "/casper/$ARQ")
    done

    xorriso -indev "$ISO_BASE" -outdev "$ISO_NOVA" \
        -volid "$VOLID" \
        "${MAPS[@]}" \
        -map "$BUILD/info" /.disk/info \
        -map "$BUILD/md5sum.txt" /md5sum.txt \
        -boot_image any replay

    (cd "$SAIDA" && sha256sum "$(basename "$ISO_NOVA")" > "$(basename "$ISO_NOVA").sha256")
    # out/ fica com quem chamou o sudo, para poder apagar/mover a ISO sem root
    chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$SAIDA"
    log "Pronto: $ISO_NOVA"
}

##########
## MAIN ##
##########
trap limpar_chroot EXIT

check_requisitos
if [[ "${RETOMAR:-0}" == "1" ]]; then
    if [[ ! -x "$ROOTFS/usr/bin/dpkg" || ! -f "$CASPER/install-sources.yaml" ]]; then
        log "ERRO: RETOMAR=1 sem rootfs pronto em $BUILD. Rode sem RETOMAR."
        exit 1
    fi
    log "Retomando com o rootfs existente (sem extrair, overlay nem pacotes)"
else
    extrair
    aplicar_overlay
    instalar_pacotes
fi
gerar_casper
atualizar_md5
gerar_iso
