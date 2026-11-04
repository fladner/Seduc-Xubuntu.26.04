#!/usr/bin/env bash

# Parte root do painel de Active Directory (painel_ad.sh), chamada via pkexec.
# Ingressa a máquina no AD SEDUC com Samba/winbind, monta as pastas do
# servidor pelo pam_mount. As impressoras o próprio usuário do AD instala
# depois de entrar (painel_impressora_ad.sh).
# A senha do administrador do AD chega pela entrada padrão (1ª linha), nunca
# na linha de comando. Saída no formato do yad --progress.
# Uso: ingressar_ad.sh entrar <usuario> <computador> [ou]
#      ingressar_ad.sh sair   <usuario>

set -uo pipefail

SCRIPT_VERSION="1.3-0"

#####################
## VARIABLE GLOBAL ##
#####################
AD_DIR="/usr/local/seduc/ad"
LOG="/usr/local/seduc/logs/ingressar_ad.log"
RELATORIO="/usr/local/seduc/logs/ingressar_ad.relatorio"
SUDOERS="/etc/sudoers.d/seduc-ad"
LIGHTDM="/etc/lightdm/lightdm.conf"
TIMESYNC="/etc/systemd/timesyncd.conf.d/seduc-ad.conf"

# shellcheck source=/dev/null
. "$AD_DIR/ad.conf"

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.bak"
exec 3>&1 >"$LOG" 2>&1
: > "$RELATORIO"

echo "===== INÍCIO $(date) - versão $SCRIPT_VERSION ====="
echo "Ação: ${1:-} ${2:-} ${3:-} ${4:-} ${5:-}"

###############
## FUNCTIONS ##
###############
progresso() {
    echo "$1" >&3
    echo "# $2" >&3
    echo ">>> [$1%] $2"
}

relatorio() {
    echo "$1|$2" >> "$RELATORIO"
    echo "=== $1: $2"
}

falhar() {
    relatorio "$1" "FALHA: $2"
    progresso 100 "Interrompido"
    exit 2
}

# Copia um modelo de $AD_DIR trocando @REALM@, @DOMINIO@, @WORKGROUP@, @NETBIOS@
gerar() {
    local MODELO="$1" DESTINO="$2"
    [ -f "$DESTINO" ] && [ ! -f "$DESTINO.seduc-bkp" ] && cp -a "$DESTINO" "$DESTINO.seduc-bkp"
    sed -e "s|@REALM@|$REALM|g" -e "s|@DOMINIO@|$DOMINIO|g" \
        -e "s|@WORKGROUP@|$WORKGROUP|g" -e "s|@NETBIOS@|${COMPUTADOR:-}|g" \
        "$AD_DIR/$MODELO" > "$DESTINO"
    chmod 644 "$DESTINO"
}

# Liga/desliga winbind em passwd e group do nsswitch.conf
nsswitch_winbind() {
    local BANCO
    for BANCO in passwd group; do
        sed -i -E "/^$BANCO:/ s/[[:space:]]+winbind//g" /etc/nsswitch.conf
        if [[ "$1" == "on" ]]; then
            sed -i -E "/^$BANCO:/ s/$/ winbind/" /etc/nsswitch.conf
        fi
    done
}

verificar_rede() {
    progresso 5 "Procurando os controladores do domínio $DOMINIO..."
    if ! host -t SRV "_ldap._tcp.dc._msdcs.$DOMINIO" >/dev/null; then
        falhar "Rede" "o DNS não encontra o domínio $DOMINIO. Conecte na rede SEDUC (cabo) e tente de novo"
    fi
    host -t SRV "_ldap._tcp.dc._msdcs.$DOMINIO"
    relatorio "Rede" "domínio $DOMINIO encontrado"
}

# Kerberos recusa relógio com mais de 5 minutos de diferença do servidor
acertar_hora() {
    progresso 10 "Acertando o relógio com o domínio..."
    mkdir -p "$(dirname "$TIMESYNC")"
    printf '[Time]\nNTP=%s\nFallbackNTP=ntp.ubuntu.com\n' "$DOMINIO" > "$TIMESYNC"
    timedatectl set-ntp true || true
    systemctl restart systemd-timesyncd || true
    sleep 3
}

entrar() {
    local USUARIO="$1" OU="${2:-}" SENHA OPCOES=()
    IFS= read -r SENHA || true
    [ -n "$SENHA" ] || falhar "Credenciais" "senha vazia"

    verificar_rede
    acertar_hora

    progresso 20 "Gerando smb.conf, krb5.conf e pam_winbind.conf..."
    gerar smb.conf /etc/samba/smb.conf
    gerar krb5.conf /etc/krb5.conf
    gerar pam_winbind.conf /etc/security/pam_winbind.conf
    testparm -s /etc/samba/smb.conf >/dev/null || falhar "smb.conf" "testparm recusou o arquivo"

    progresso 35 "Ingressando $COMPUTADOR no domínio (pode demorar)..."
    systemctl stop winbind || true
    [ -n "$OU" ] && OPCOES+=("createcomputer=$OU")
    if ! PASSWD="$SENHA" net ads join -U "$USUARIO" "${OPCOES[@]}"; then
        unset SENHA
        falhar "Ingresso" "o domínio recusou (usuário/senha, permissão ou OU). Veja $LOG"
    fi
    unset SENHA
    net ads testjoin || falhar "Ingresso" "net ads testjoin falhou"
    relatorio "Ingresso" "$COMPUTADOR ingressado em $DOMINIO"

    progresso 55 "Iniciando o winbind..."
    systemctl enable winbind
    systemctl restart winbind
    local I
    for I in $(seq 1 20); do
        wbinfo -t >/dev/null 2>&1 && break
        sleep 2
    done
    wbinfo -t || falhar "Winbind" "sem conexão de confiança com o domínio"

    progresso 65 "Ativando o login dos usuários do domínio..."
    nsswitch_winbind on
    DEBIAN_FRONTEND=noninteractive pam-auth-update --enable winbind mkhomedir libpam-mount
    if getent passwd "$USUARIO" >/dev/null; then
        relatorio "Login do domínio" "ativo (teste: $USUARIO encontrado)"
    else
        relatorio "Login do domínio" "FALHA: $USUARIO não aparece no getent passwd"
    fi

    progresso 75 "Configurando as pastas do servidor (pam_mount)..."
    [ -f /etc/security/pam_mount.conf.xml ] && [ ! -f /etc/security/pam_mount.conf.xml.seduc-bkp ] \
        && cp -a /etc/security/pam_mount.conf.xml /etc/security/pam_mount.conf.xml.seduc-bkp
    install -m 644 "$AD_DIR/pam_mount.conf.xml" /etc/security/pam_mount.conf.xml
    relatorio "Pastas do servidor" "montadas no login conforme os grupos do AD"

    progresso 80 "Liberando sudo para ${GRUPOS_ADMIN[*]}..."
    local G
    {
        echo "# Gerado pelo ingressar_ad.sh: grupos do AD SEDUC com sudo"
        for G in "${GRUPOS_ADMIN[@]}"; do
            echo "%${G// /\\ } ALL=(ALL:ALL) ALL"
        done
    } > "$SUDOERS.tmp"
    if visudo -cf "$SUDOERS.tmp"; then
        install -m 440 "$SUDOERS.tmp" "$SUDOERS"
        relatorio "Administradores" "${GRUPOS_ADMIN[*]}"
    else
        relatorio "Administradores" "FALHA: sudoers inválido"
    fi
    rm -f "$SUDOERS.tmp"

    progresso 85 "Tela de login com o campo para digitar o usuário..."
    if [ -f "$LIGHTDM" ] && grep -q '^greeter-show-manual-login=' "$LIGHTDM"; then
        sed -i 's/^greeter-show-manual-login=.*/greeter-show-manual-login=true/' "$LIGHTDM"
    else
        mkdir -p /etc/lightdm
        printf '[Seat:*]\ngreeter-show-manual-login=true\n' >> "$LIGHTDM"
    fi

    relatorio "Impressoras" "cada usuário do AD instala pelo menu SEDUC > Impressoras SEDUC"

    progresso 100 "Concluído"
}

sair() {
    local USUARIO="$1" SENHA
    IFS= read -r SENHA || true

    progresso 20 "Removendo a máquina do domínio..."
    if [ -n "$SENHA" ] && PASSWD="$SENHA" net ads leave -U "$USUARIO"; then
        relatorio "Domínio" "máquina removida do AD"
    else
        relatorio "Domínio" "FALHA ao remover a conta no AD (a configuração local será desfeita mesmo assim)"
    fi
    unset SENHA

    progresso 50 "Desativando o login do domínio..."
    DEBIAN_FRONTEND=noninteractive pam-auth-update --remove winbind libpam-mount
    nsswitch_winbind off
    systemctl disable --now winbind || true
    rm -f "$SUDOERS" "$TIMESYNC"
    [ -f /etc/security/pam_mount.conf.xml.seduc-bkp ] \
        && mv -f /etc/security/pam_mount.conf.xml.seduc-bkp /etc/security/pam_mount.conf.xml
    [ -f "$LIGHTDM" ] && sed -i 's/^greeter-show-manual-login=.*/greeter-show-manual-login=false/' "$LIGHTDM"
    # Impressoras instaladas pelo painel_impressora_ad.sh
    lpstat -p 2>/dev/null | awk '$2 ~ /^SEDUC-/ {print $2}' | while read -r FILA; do
        lpadmin -x "$FILA" || true
    done
    # Backend Kerberos ligado pelo instalar_impressora_ad.sh
    if dpkg-divert --listpackage /usr/lib/cups/backend/smb | grep -qx LOCAL; then
        rm -f /usr/lib/cups/backend/smb
        dpkg-divert --local --rename --remove /usr/lib/cups/backend/smb || true
    fi
    if grep -qs smbspool_krb5_wrapper /etc/apparmor.d/local/usr.sbin.cupsd; then
        sed -i '/smbspool_krb5_wrapper/d' /etc/apparmor.d/local/usr.sbin.cupsd
        [ -d /sys/kernel/security/apparmor ] && apparmor_parser -r /etc/apparmor.d/usr.sbin.cupsd || true
    fi
    relatorio "Configuração local" "desfeita (usuários locais continuam)"
    progresso 100 "Concluído"
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

ACAO="${1:-}"
case "$ACAO" in
    entrar)
        [[ $# -ge 3 ]] || falhar "Uso" "entrar <usuario> <computador> [ou]"
        COMPUTADOR="${3^^}"
        [[ "$COMPUTADOR" =~ ^[A-Z0-9-]{1,15}$ ]] || falhar "Computador" "nome inválido: use até 15 letras, números ou hífen"
        entrar "$2" "${4:-}"
        ;;
    sair)
        [[ $# -ge 2 ]] || falhar "Uso" "sair <usuario>"
        sair "$2"
        ;;
    *)
        falhar "Uso" "ação inválida: $ACAO"
        ;;
esac

echo "===== FIM $(date) ====="
grep -q '|FALHA' "$RELATORIO" && exit 2
exit 0
