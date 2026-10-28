#!/usr/bin/env bash

set -euo pipefail

## VARIABLES
SCRIPT_VERSION="1.1-0"
SEDUC_DIR="/usr/local/seduc"
LOG_FILE="$SEDUC_DIR/logs/seduc_setup.log"
SCRIPT_PATH="$(readlink -f "$0")"
# Atualizador: repositório no GitHub e chave pública que assina as versões
UPDATE_CONF="$SEDUC_DIR/update.conf"
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

## AUTO UPDATE
# Baixa scripts/seduc_setup.sh e scripts/seduc_setup.sh.asc do GitHub.
# Só substitui o script se a assinatura conferir com a chave da ISO
# e a versão remota for maior que a local.
check_update() {

    log "Verificando atualização..."

    local REPO_RAW="" TMP_DIR REMOTE_VERSION

    # shellcheck source=/dev/null
    [ -r "$UPDATE_CONF" ] && . "$UPDATE_CONF"

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

    check_model
    apply_patch_if_needed remover_snaps
    apply_patch_if_needed remove_apps
    
    log "Script finalizado com sucesso."
}

main "$@"
