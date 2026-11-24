#!/usr/bin/env bash

set -euo pipefail

## VARIABLES
SCRIPT_VERSION="1.7-3"
SEDUC_DIR="/usr/local/seduc"
LOG_FILE="$SEDUC_DIR/logs/seduc_setup.log"
SCRIPT_PATH="$(readlink -f "$0")"
# Atualizador: repositório no GitHub e chave pública que assina as versões
UPDATE_CONF="$SEDUC_DIR/update.conf"
# Ajuste só desta máquina (ex.: REPO_RAW de um ramo de teste); não vem nos pacotes
UPDATE_LOCAL="$SEDUC_DIR/update.local.conf"
UPDATE_KEYRING="$SEDUC_DIR/keys/seduc-updates.gpg"

## FLAGS
FLAG_DIR="$SEDUC_DIR/flags"

## LOGS
mkdir -p "$(dirname "$LOG_FILE")"

[ -f "$LOG_FILE" ] && mv -f "$LOG_FILE" "$LOG_FILE.old"

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[INFO] $(date '+%F %T') - $*"
}

log_error() {
    echo "[ERROR] $(date '+%F %T') - $*" >&2
}

## CHECKS INICIAIS 
check_live() {
    # Evita rodar no modo live (ISO)
    if grep -q "casper" /proc/cmdline; then
        log "Ambiente Live detectado. Abortando..."
        exit 0
    fi
}

## VERIFICANDO O APT
check_apt() {

    local TIMEOUT=300
    local ELAPSED=0

    log "Verificando estado do APT..."

    # Aguarda lock liberar
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do

        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            log_error "Timeout aguardando lock do APT"
            return 1
        fi

        log "APT ocupado... aguardando 5s"
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done

    # Corrige pacotes pendentes
    if ! dpkg --configure -a; then
        log_error "Erro ao configurar pacotes pendentes"
        return 1
    fi

    log "APT verificado com sucesso"
}

## CONFIGURAÇÃO DO ATUALIZADOR
# update.conf (vem nos pacotes) e, por cima, update.local.conf (da máquina)
carregar_conf() {
    # shellcheck source=/dev/null
    [ -r "$UPDATE_CONF" ] && . "$UPDATE_CONF"
    # shellcheck source=/dev/null
    [ -r "$UPDATE_LOCAL" ] && . "$UPDATE_LOCAL"
    return 0
}

## AUTO UPDATE
# Baixa scripts/seduc_setup.sh e scripts/seduc_setup.sh.asc do GitHub.
# Só substitui o script se a assinatura conferir com a chave da ISO
# e a versão remota for maior que a local.
check_update() {

    log "Verificando atualização..."

    local REPO_RAW="" TMP_DIR REMOTE_VERSION

    carregar_conf

    if [ -z "$REPO_RAW" ]; then
        log "Atualizador sem repositório configurado ($UPDATE_CONF)"
        return 0
    fi

    if [ ! -s "$UPDATE_KEYRING" ]; then
        log_error "Chave de assinatura ausente: $UPDATE_KEYRING"
        return 1
    fi

    TMP_DIR=$(mktemp -d)

    if ! curl -fsSL --retry 3 -m 60 "$REPO_RAW/scripts/seduc_setup.sh" -o "$TMP_DIR/seduc_setup.sh" ||
       ! curl -fsSL --retry 3 -m 60 "$REPO_RAW/scripts/seduc_setup.sh.asc" -o "$TMP_DIR/seduc_setup.sh.asc"; then
        rm -rf "$TMP_DIR"
        log_error "Erro ao baixar script remoto"
        return 1
    fi

    if ! gpgv --keyring "$UPDATE_KEYRING" "$TMP_DIR/seduc_setup.sh.asc" "$TMP_DIR/seduc_setup.sh"; then
        rm -rf "$TMP_DIR"
        log_error "Assinatura inválida: atualização recusada"
        return 1
    fi

    REMOTE_VERSION=$(awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' "$TMP_DIR/seduc_setup.sh")

    if [ -z "${REMOTE_VERSION:-}" ] || ! bash -n "$TMP_DIR/seduc_setup.sh"; then
        rm -rf "$TMP_DIR"
        log_error "Script remoto inválido"
        return 1
    fi

    log "Versão local:  $SCRIPT_VERSION"
    log "Versão remota: $REMOTE_VERSION"

    # Só atualiza para versão maior: nunca volta para uma versão antiga
    if [ "$REMOTE_VERSION" = "$SCRIPT_VERSION" ] ||
       [ "$(printf '%s\n%s\n' "$SCRIPT_VERSION" "$REMOTE_VERSION" | sort -V | tail -1)" != "$REMOTE_VERSION" ]; then
        rm -rf "$TMP_DIR"
        log "Script já está atualizado"
        return 0
    fi

    log "Nova versão encontrada, atualizando..."

    # install + mv: troca atômica, dono root e permissão 755
    if install -o root -g root -m 755 "$TMP_DIR/seduc_setup.sh" "$SCRIPT_PATH.new" &&
       mv -f "$SCRIPT_PATH.new" "$SCRIPT_PATH"; then
        rm -rf "$TMP_DIR"
        log "Atualização concluída. Vale a partir da próxima execução."
        return 0
    fi

    rm -f "$SCRIPT_PATH.new"
    rm -rf "$TMP_DIR"
    log_error "Erro ao substituir script"
    return 1
}

## SNAP REMOVAL
remover_snaps() {

    if command -v snap >/dev/null 2>&1; then
        log "Removendo snaps instalados..."

        snap list | awk 'NR>1 {print $1}' | tac | while read -r snap; do
            log "Removendo: $snap"
            snap remove --purge "$snap" || true
        done
    else
        log "Snap não encontrado."
    fi

    # Desativa serviço
    systemctl stop snapd 2>/dev/null || true
    systemctl disable snapd 2>/dev/null || true

    # Verifica se o apt está bloqueado.
    check_apt

    # Remove pacotes
    apt-get purge -y snapd || true

    # Remove diretórios residuais
    rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd || true

}

## REMOVE APPS APOS INSTALACAO PRA NAO QUEBRAR O LIVECD
remove_apps() {
    
    local remove=(
        avahi-daemon
        avahi-utils
        cups-browsed
        modemmanager
        network-manager-pptp
        xfce4-indicator-plugin
    )

    check_apt

    log "Removendo os pacotes... "

    if apt-get remove --purge -y "${remove[@]}"; then
        log "Concluído!"
    else
        log_error "Falha na remoção"
        return 1
    fi

    apt-get autoremove --purge -y || true
    apt-get clean || true

}

## PATCH HARDWARE
patch_m720q() {

    local PARAM="intel_iommu=igfx_off"

    if ! grep -q "$PARAM" /etc/default/grub; then
        log "Aplicando patch M720q..."

        sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"/\1 $PARAM\"/" /etc/default/grub

        update-grub
    else
        log "Parâmetro já aplicado."
    fi
}

## PACOTES DE MÍDIAS E DISCOS
# Os mesmos da ISO 1.3-2 (config/pacotes-instalar.txt) para as máquinas
# instaladas antes: celular, câmera e pastas de rede no Thunar, e ferramentas
# para formatar e reparar os sistemas de arquivos menos comuns
instalar_midias() {

    local pacotes=(
        gvfs-backends
        gvfs-fuse
        btrfs-progs
        xfsprogs
        f2fs-tools
        udftools
        hfsprogs
        mtools
    )

    check_apt || return 1

    log "Instalando pacotes de mídias e discos..."

    apt-get update || log_error "Falha no apt-get update (continuando)"

    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pacotes[@]}"; then
        log "Concluído!"
    else
        log_error "Falha na instalação"
        return 1
    fi
}

## INFRAESTRUTURA DO XUBUNTU COMPLETO
# Atalhos de programa que aparecem no menu (nome do .desktop)
atalhos_visiveis() {
    local A
    for A in /usr/share/applications/*.desktop; do
        if grep -q '^Type=Application' "$A" && ! grep -qiE '^(NoDisplay|Hidden)=true' "$A"; then
            basename "$A"
        fi
    done
    return 0
}

# A mesma lista de config/pacotes-base-xubuntu.txt (ISO 1.3-3), para as máquinas
# instaladas antes. Nenhum programa novo no menu: atalho que aparecer na
# instalação fica oculto por uma cópia com NoDisplay=true em /usr/local
instalar_base_xubuntu() {

    local pacotes=(
        heif-gdk-pixbuf
        network-manager-openvpn-gnome
        xcursor-themes
        apt-config-icons-hidpi
        thunar-media-tags-plugin
        speech-dispatcher
        espeak
        xfce4-xkb-plugin
        xfce4-places-plugin
        xfce4-clipman-plugin
        xfce4-systemload-plugin
        xfce4-cpugraph-plugin
        xfce4-netload-plugin
        xfce4-weather-plugin
        xfce4-verve-plugin
        xfce4-mailwatch-plugin
        xubuntu-docs
        inxi
        pastebinit
    )
    local ANTES A DESTINO

    check_apt || return 1

    log "Instalando a infraestrutura do Xubuntu completo..."

    ANTES=$(atalhos_visiveis)

    apt-get update || log_error "Falha no apt-get update (continuando)"

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pacotes[@]}"; then
        log_error "Falha na instalação"
        return 1
    fi

    while read -r A; do
        grep -qxF "$A" <<< "$ANTES" && continue
        DESTINO="/usr/local/share/applications/$A"
        [ -e "$DESTINO" ] && continue
        install -d -m 755 /usr/local/share/applications
        sed -e '/^NoDisplay=/d' -e '/^\[Desktop Entry\]/a NoDisplay=true' \
            "/usr/share/applications/$A" > "$DESTINO"
        chmod 644 "$DESTINO"
        log "Atalho oculto: $A"
    done < <(atalhos_visiveis)

    log "Concluído!"
}

## SISTEMA SEDUC (OVERLAY DA ISO)
# Baixa scripts/seduc-sistema.tar.gz e a assinatura .asc (gerados pelo
# tools/publicar-seduc-setup.sh): o overlay inteiro da ISO, com a versão, e as listas
# do atualizador em usr/local/seduc/atualizador/. Extrai em / sempre que o pacote
# muda (sha256), não uma vez só.
# Mesmo assinado, só entram arquivos e pastas comuns dentro destes destinos:
ARQUIVOS_PERMITIDOS='^(etc/|usr/local/|usr/share/polkit-1/)'
ARQUIVOS_PASTAS='^(usr|usr/share|etc)/$'
ATUALIZADOR_DIR="$SEDUC_DIR/atualizador"

# Unidades seduc-* do overlay ligadas como na ISO; certificados e permissões
pos_arquivos() {
    local LISTA="$1" U ARQ
    systemctl daemon-reload || true
    while read -r U; do
        U=$(basename "$U")
        systemctl is-enabled --quiet "$U" 2>/dev/null && continue
        systemctl enable "$U" && log "Serviço habilitado: $U"
    done < <(grep -E '^etc/systemd/system/seduc-[^/]+\.service$' <<< "$LISTA" || true)
    # Timers (seduc-atualizar.timer): o serviço deles não tem [Install]
    while read -r U; do
        U=$(basename "$U")
        systemctl is-enabled --quiet "$U" 2>/dev/null && continue
        systemctl enable --now "$U" && log "Timer habilitado: $U"
    done < <(grep -E '^etc/systemd/system/seduc-[^/]+\.timer$' <<< "$LISTA" || true)

    grep -q '^usr/local/share/ca-certificates/.' <<< "$LISTA" && { update-ca-certificates || true; }

    # Logs e flags graváveis pelo administrador (grupo adm), como no build.sh
    chown root:adm "$SEDUC_DIR/logs" "$SEDUC_DIR/flags" 2>/dev/null || true
    chmod 2775 "$SEDUC_DIR/logs" "$SEDUC_DIR/flags" 2>/dev/null || true

    # Arquivos que a ISO apaga (config/arquivos-remover.txt)
    if [ -r "$ATUALIZADOR_DIR/arquivos-remover.txt" ]; then
        while read -r ARQ; do
            [[ "$ARQ" == /* && "$ARQ" != *..* ]] || continue
            [ -e "$ARQ" ] || continue
            rm -f "$ARQ" && log "Removido: $ARQ"
        done < "$ATUALIZADOR_DIR/arquivos-remover.txt"
    fi
}

instalar_arquivos() {

    local REPO_RAW="" TMP_DIR PACOTE HASH OLD_HASH="" LISTA INVALIDOS PACOTE_VERSAO SISTEMA_VERSAO
    local HASH_FILE="$FLAG_DIR/seduc-sistema.sha256"

    carregar_conf
    if [ -z "$REPO_RAW" ]; then
        log "Arquivos: atualizador sem repositório configurado"
        return 0
    fi
    if [ ! -s "$UPDATE_KEYRING" ]; then
        log_error "Chave de assinatura ausente: $UPDATE_KEYRING"
        return 1
    fi

    log "Verificando o sistema SEDUC..."
    TMP_DIR=$(mktemp -d)
    PACOTE="$TMP_DIR/seduc-sistema.tar.gz"

    if ! curl -fsSL --retry 3 -m 300 "$REPO_RAW/scripts/seduc-sistema.tar.gz" -o "$PACOTE" ||
       ! curl -fsSL --retry 3 -m 60 "$REPO_RAW/scripts/seduc-sistema.tar.gz.asc" -o "$PACOTE.asc"; then
        rm -rf "$TMP_DIR"
        log_error "Erro ao baixar o pacote do sistema"
        return 1
    fi

    if ! gpgv --keyring "$UPDATE_KEYRING" "$PACOTE.asc" "$PACOTE"; then
        rm -rf "$TMP_DIR"
        log_error "Assinatura inválida: pacote do sistema recusado"
        return 1
    fi

    HASH=$(sha256sum "$PACOTE" | cut -d' ' -f1)
    [ -f "$HASH_FILE" ] && OLD_HASH=$(cat "$HASH_FILE")
    if [ "$HASH" = "$OLD_HASH" ]; then
        rm -rf "$TMP_DIR"
        log "Sistema já aplicado (${HASH:0:16})"
        return 0
    fi

    # Nada de links, "..", nem outros destinos
    if ! LISTA=$(tar -tzf "$PACOTE"); then
        rm -rf "$TMP_DIR"
        log_error "Pacote do sistema corrompido"
        return 1
    fi
    INVALIDOS=$(grep -vE "$ARQUIVOS_PERMITIDOS" <<< "$LISTA" | grep -vE "$ARQUIVOS_PASTAS" || true)
    INVALIDOS+=$'\n'$(grep -E '(^/|(^|/)\.\.(/|$))' <<< "$LISTA" || true)
    INVALIDOS+=$'\n'$(grep -E '^usr/local/seduc/(scripts/seduc_setup\.sh|update\.local\.conf|keys/.*|logs/.*|flags/.*)$' <<< "$LISTA" || true)
    INVALIDOS+=$'\n'$(tar -tvzf "$PACOTE" | grep -v '^[-d]' | awk '{print $6}' || true)
    INVALIDOS=$(sed '/^$/d' <<< "$INVALIDOS")
    if [ -n "$INVALIDOS" ]; then
        rm -rf "$TMP_DIR"
        log_error "Pacote do sistema recusado, caminhos não permitidos: $(tr '\n' ' ' <<< "$INVALIDOS")"
        return 1
    fi

    # Sistema compilado depois do pacote (ISO mais nova) já tem arquivos mais novos
    PACOTE_VERSAO=$(tar -xzOf "$PACOTE" usr/local/seduc/arquivos.version 2>/dev/null || true)
    SISTEMA_VERSAO=$(cat "$SEDUC_DIR/version" 2>/dev/null || true)
    if [ -z "$PACOTE_VERSAO" ]; then
        rm -rf "$TMP_DIR"
        log_error "Pacote do sistema sem versão: recusado"
        return 1
    fi
    if [ -n "$SISTEMA_VERSAO" ] && [ "$SISTEMA_VERSAO" != "$PACOTE_VERSAO" ] &&
       [ "$(printf '%s\n%s\n' "$SISTEMA_VERSAO" "$PACOTE_VERSAO" | sort -V | tail -1)" = "$SISTEMA_VERSAO" ]; then
        mkdir -p "$FLAG_DIR"
        echo "$HASH" > "$HASH_FILE"
        rm -rf "$TMP_DIR"
        log "Sistema $PACOTE_VERSAO não aplicado: o sistema $SISTEMA_VERSAO é mais novo"
        return 0
    fi

    if ! tar -xzf "$PACOTE" -C / --no-same-owner --no-overwrite-dir --keep-directory-symlink; then
        rm -rf "$TMP_DIR"
        log_error "Falha ao extrair o pacote do sistema"
        return 1
    fi

    pos_arquivos "$LISTA"
    mkdir -p "$FLAG_DIR"
    echo "$HASH" > "$HASH_FILE"
    rm -rf "$TMP_DIR"
    log "Sistema $PACOTE_VERSAO aplicado: $(grep -vc '/$' <<< "$LISTA") arquivos (${HASH:0:16})"
}

## .DEB CRIADOS PARA A ISO
# atualizador/debs.txt (do pacote assinado): "pacote versão arquivo sha256".
# Baixa $REPO_RAW/scripts/debs/<arquivo>, confere o sha256 e instala quando a
# versão instalada é menor ou o pacote falta. Roda a cada boot; sem rede, tenta no próximo.
instalar_debs() {

    local REPO_RAW="" LISTA="$ATUALIZADOR_DIR/debs.txt" PKG VER ARQ SHA ATUAL TMP_DIR FALHA=0

    [ -r "$LISTA" ] || return 0
    carregar_conf
    [ -n "$REPO_RAW" ] || return 0

    while read -r PKG VER ARQ SHA; do
        [ -n "$SHA" ] || continue
        [[ "$ARQ" =~ ^[A-Za-z0-9._+~-]+\.deb$ ]] || { log_error ".deb com nome inválido: $ARQ"; FALHA=1; continue; }
        ATUAL=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$PKG" 2>/dev/null || true)
        if [[ "$ATUAL" == ii* ]] && dpkg --compare-versions "${ATUAL##* }" ge "$VER"; then
            log "$PKG ${ATUAL##* } já instalado"
            continue
        fi

        log "Instalando $PKG $VER..."
        check_apt || return 1
        TMP_DIR=$(mktemp -d)
        chmod 755 "$TMP_DIR"
        if ! curl -fsSL --retry 3 -m 600 "$REPO_RAW/scripts/debs/$ARQ" -o "$TMP_DIR/$ARQ"; then
            log_error "Erro ao baixar $ARQ"
            rm -rf "$TMP_DIR"; FALHA=1; continue
        fi
        if [ "$(sha256sum "$TMP_DIR/$ARQ" | cut -d' ' -f1)" != "$SHA" ]; then
            log_error "sha256 diferente: $ARQ recusado"
            rm -rf "$TMP_DIR"; FALHA=1; continue
        fi
        chmod 644 "$TMP_DIR/$ARQ"
        apt-get update || log_error "Falha no apt-get update (continuando)"
        if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
               -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$TMP_DIR/$ARQ"; then
            log "$PKG $VER instalado"
        else
            log_error "Falha ao instalar $PKG $VER"
            FALHA=1
        fi
        rm -rf "$TMP_DIR"
    done < "$LISTA"

    return "$FALHA"
}

## PACOTES DA ISO
# atualizador/pacotes-instalar.txt e pacotes-remover.txt: as mesmas listas do
# build.sh. Instala só o que falta e remove só o que está instalado.
pacote_instalado() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'; }

# Com o AD (winbind) instalado agora numa máquina fora do domínio: desliga como o
# build.sh, o login do domínio só liga no ingresso (painel_ad.sh)
desligar_ad_fora_do_dominio() {
    # Mesmo critério do dominio_ad.sh: smb.conf "ads" e winbind no nsswitch
    if grep -qiE '^[[:space:]]*security[[:space:]]*=[[:space:]]*ads[[:space:]]*([;#].*)?$' /etc/samba/smb.conf 2>/dev/null &&
       grep -qE '^passwd:.*[[:space:]]winbind([[:space:]]|$)' /etc/nsswitch.conf 2>/dev/null; then
        return 0
    fi
    log "AD instalado fora do domínio: winbind e login do domínio desligados"
    systemctl disable --now winbind.service 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive pam-auth-update --remove winbind libpam-mount || true
    sed -i -E '/^(passwd|group):/ s/[[:space:]]+winbind//g' /etc/nsswitch.conf
}

instalar_pacotes_iso() {

    local P FALTAM=() NOVOS_AD=0 ANTES A DESTINO FALHA=0

    [ -r "$ATUALIZADOR_DIR/pacotes-instalar.txt" ] || return 0

    local R=()
    while read -r P; do
        [ -n "$P" ] && pacote_instalado "$P" && R+=("$P")
    done < <(cat "$ATUALIZADOR_DIR/pacotes-remover.txt" 2>/dev/null || true)

    while read -r P; do
        [ -n "$P" ] || continue
        pacote_instalado "$P" && continue
        FALTAM+=("$P")
        [[ "$P" =~ ^(winbind|libpam-winbind|libnss-winbind|libpam-mount)$ ]] && NOVOS_AD=1
    done < "$ATUALIZADOR_DIR/pacotes-instalar.txt"

    if [ ${#FALTAM[@]} -eq 0 ] && [ ${#R[@]} -eq 0 ]; then
        log "Pacotes da ISO já instalados"
        return 0
    fi

    check_apt || return 1

    if [ ${#R[@]} -gt 0 ]; then
        log "Removendo: ${R[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "${R[@]}" || { log_error "Falha na remoção"; FALHA=1; }
    fi

    [ ${#FALTAM[@]} -gt 0 ] || return "$FALHA"

    if printf '%s\n' "${FALTAM[@]}" | grep -q ':i386$' && ! dpkg --print-foreign-architectures | grep -qx i386; then
        dpkg --add-architecture i386
    fi
    ANTES=$(atalhos_visiveis)
    apt-get update || log_error "Falha no apt-get update (continuando)"

    log "Instalando os pacotes da ISO: ${FALTAM[*]}"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${FALTAM[@]}"; then
        # Um pacote indisponível não segura os outros
        log_error "Falha na instalação em conjunto; tentando um por um"
        for P in "${FALTAM[@]}"; do
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$P" ||
                { log_error "Falha ao instalar $P"; FALHA=1; }
        done
    fi

    (( NOVOS_AD )) && desligar_ad_fora_do_dominio

    # Como no build.sh: atalho novo de dependência fica oculto; os da lista aparecem
    while read -r A; do
        grep -qxF "$A" <<< "$ANTES" && continue
        P=$(dpkg -S "/usr/share/applications/$A" 2>/dev/null | head -1 | cut -d: -f1 || true)
        [ -n "$P" ] && sed 's/:.*//' "$ATUALIZADOR_DIR/pacotes-instalar.txt" | grep -qxF "$P" && continue
        DESTINO="/usr/local/share/applications/$A"
        [ -e "$DESTINO" ] && continue
        install -d -m 755 /usr/local/share/applications
        sed -e '/^NoDisplay=/d' -e '/^\[Desktop Entry\]/a NoDisplay=true' \
            "/usr/share/applications/$A" > "$DESTINO"
        chmod 644 "$DESTINO"
        log "Atalho oculto: $A"
    done < <(atalhos_visiveis)

    return "$FALHA"
}

## NTFS PELO NTFS-3G
# O mesmo /etc/udisks2/mount_options.conf da ISO 1.4-1: o ntfs3 do kernel recusa
# o HD NTFS "sujo" ("wrong fs type, bad option, bad superblock"); o ntfs-3g monta
corrigir_ntfs() {

    log "Montagem de NTFS pelo ntfs-3g..."

    mkdir -p /etc/udisks2
    cat > /etc/udisks2/mount_options.conf <<'EOF'
# SEDUC: HD e pendrive NTFS montam pelo ntfs-3g (driver "ntfs").
# O padrão do udisks é o ntfs3 do kernel, que recusa o disco NTFS marcado como
# "sujo" (desligado sem "Remover com segurança", Inicialização Rápida ou
# hibernação do Windows) com o erro "wrong fs type, bad option, bad superblock".
# O ntfs-3g monta esse disco; se o Windows estiver hibernado, monta só leitura.
[defaults]
ntfs_drivers=ntfs,ntfs3
EOF
    chmod 644 /etc/udisks2/mount_options.conf
    log "Concluído!"
}

## ASSINADOR LOGUS
# Nas máquinas com o Assinador Logus e o token mToken CryptoID instalados antes da
# 1.6-4: lançador com o driver do token (PKCS11_DRIVER). Sem o CryptoID, o
# lançador original da Logus fica como está
corrigir_logus() {

    local DIR="/opt/AssinadorLogus" MODELO="$SEDUC_DIR/tokens/AssinadorLogus.sh"
    local LIB="/opt/CryptoIDEAdmin/x64/lib/linux/x64/libcryptoide_pkcs11.so"

    if [ ! -f "$DIR/AssinadorLogus.sh" ] || [ ! -f "$LIB" ]; then
        log "Assinador Logus com CryptoID não instalado: lançador original mantido"
        return 0
    fi
    [ -r "$MODELO" ] || { log_error "Lançador do Assinador Logus ausente: $MODELO"; return 1; }
    install -m 755 "$MODELO" "$DIR/AssinadorLogus.sh"
    log "Assinador Logus com o driver do token CryptoID"
}

## ATUALIZAÇÃO AUTOMÁTICA
# Desde a 1.7-0 quem atualiza os pacotes é o seduc-atualizar.timer
# (atualizar_pacotes.sh); o apt-daily e o unattended-upgrades ficam desligados para
# não disputarem o apt (o 99seduc-atualizar do overlay zera o APT::Periodic)
desligar_unattended_upgrades() {

    # O pacote 1.7-0 chega pelo seduc_setup.sh anterior, que não habilita timers
    if [ ! -x "$SEDUC_DIR/scripts/atualizar_pacotes.sh" ] ||
        [ ! -f /etc/systemd/system/seduc-atualizar.timer ]; then
        log_error "seduc-atualizar.timer ausente: unattended-upgrades mantido"
        return 1
    fi
    systemctl daemon-reload || true
    if ! systemctl enable --now seduc-atualizar.timer; then
        log_error "Falha ao habilitar o seduc-atualizar.timer: unattended-upgrades mantido"
        return 1
    fi
    systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    log "Atualização automática pelo seduc-atualizar.timer; apt-daily desligado"
}

## PAINEL NO MONITOR PRINCIPAL
# Desde a 1.7-3 o painel padrão fica no monitor principal (output-name "Primary" no
# default.xml do overlay). Nas máquinas que tiveram o perfil laboratório, o padrão do
# painel é a cópia xfce4-panel.xml feita na época, que o trava_perfil.sh devolve a cada
# boot: ela recebe o mesmo ajuste
painel_monitor_principal() {

    local XML="/etc/xdg/xdg-xubuntu/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

    if [ ! -f "$XML" ] || grep -q 'name="output-name"' "$XML"; then
        log "Painel do laboratório: nada a ajustar"
        return 0
    fi
    sed -i '0,/<property name="position-locked"[^>]*>/s//&\n      <property name="output-name" type="string" value="Primary"\/>/' "$XML"
    if grep -q 'name="output-name"' "$XML"; then
        log "Painel do laboratório no monitor principal"
    else
        log_error "Não foi possível ajustar o painel do laboratório: $XML"
        return 1
    fi
}

## GERENCIADOR DE USUÁRIOS
# O perfil laboratório (aluno criado pelo Boas-vindas) removia o gnome-system-tools
# ("Usuários e grupos") até a 1.4-1; devolve nas máquinas em que foi removido
instalar_usuarios_grupos() {

    if dpkg-query -W -f='${Status}' gnome-system-tools 2>/dev/null | grep -q 'ok installed'; then
        log "Usuários e grupos (gnome-system-tools) já instalado"
        return 0
    fi

    check_apt || return 1

    log "Reinstalando Usuários e grupos (gnome-system-tools)..."

    apt-get update || log_error "Falha no apt-get update (continuando)"

    if DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-system-tools; then
        log "Concluído!"
    else
        log_error "Falha na instalação"
        return 1
    fi
}

## PATCH (HASH)
apply_patch_if_needed() {

    local FUNC_NAME="$1"
    local HASH_FILE="$FLAG_DIR/${FUNC_NAME}.hash"
      
    local FUNC_DEF
    FUNC_DEF=$(declare -f "$FUNC_NAME") || {
    log_error "Função $FUNC_NAME não encontrada"
    return 1
    }

    if [[ -z "$FUNC_DEF" ]]; then
        log_error "Função $FUNC_NAME vazia"
        return 1
    fi

    local HASH
    HASH=$(echo "$FUNC_DEF" | md5sum | awk '{print $1}')

    local OLD_HASH=""
    [ -f "$HASH_FILE" ] && OLD_HASH=$(cat "$HASH_FILE")

    if [ "$HASH" == "$OLD_HASH" ]; then
        log "Patch $FUNC_NAME já aplicado (hash atual)."
        return
    fi

    log "Executando patch: $FUNC_NAME"

    if "$FUNC_NAME"; then
        echo "$HASH" > "$HASH_FILE"
        log "Patch $FUNC_NAME aplicado com sucesso."
    else
        log_error "Erro ao aplicar patch $FUNC_NAME"
        return 1
    fi
}

## DETECÇÃO DE HARDWARE
check_model() {

    local MODEL
    MODEL=$(cat /sys/class/dmi/id/product_version 2>/dev/null || echo "unknown")

    log "Modelo detectado: $MODEL"

    declare -A MODEL_PATCHES=(
        ["M720q"]="patch_m720q"
    )

    for key in "${!MODEL_PATCHES[@]}"; do
        if [[ "$MODEL" == *"$key"* ]]; then
            apply_patch_if_needed "${MODEL_PATCHES[$key]}"
        fi
    done
}

## MAIN 
main() {

    echo "----------------------------------------"
    echo "Execução: $(date '+%F %T')"
    echo "Versão: $SCRIPT_VERSION"
    echo "----------------------------------------"

    check_live
    
    check_update || log_error "Falha no update (continuando)"
    # Tudo o que a ISO nova traz: overlay, .deb nossos e pacotes; sem rede tenta no próximo boot
    instalar_arquivos || log_error "Arquivos do sistema SEDUC pendentes (próximo boot)"
    instalar_debs || log_error ".deb do sistema SEDUC pendentes (próximo boot)"
    instalar_pacotes_iso || log_error "Pacotes da ISO pendentes (próximo boot)"

    check_model
    apply_patch_if_needed remover_snaps
    apply_patch_if_needed remove_apps
    # Sem rede no boot falha e tenta de novo no próximo
    apply_patch_if_needed instalar_midias || log_error "Pacotes de mídias pendentes (próximo boot)"
    apply_patch_if_needed instalar_base_xubuntu || log_error "Infraestrutura do Xubuntu pendente (próximo boot)"
    apply_patch_if_needed corrigir_ntfs
    apply_patch_if_needed corrigir_logus || log_error "Assinador Logus pendente (próximo boot)"
    apply_patch_if_needed instalar_usuarios_grupos || log_error "Usuários e grupos pendente (próximo boot)"
    apply_patch_if_needed desligar_unattended_upgrades || log_error "Atualização automática pendente (próximo boot)"
    apply_patch_if_needed painel_monitor_principal

    log "Script finalizado com sucesso."
}

main "$@"
