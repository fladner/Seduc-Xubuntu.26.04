#!/usr/bin/env bash

# Lista local dos usuários do AD que já entraram neste computador, para a tela de login
# do SDDM (Kubuntu) mostrá-los. O SDDM lista os usuários pelo getpwent, e o winbind não
# enumera o AD (milhares de contas travavam a tela): a lista fica no banco extrausers
# (libnss-extrausers), em /var/lib/extrausers/passwd, só com quem já entrou aqui.
# A senha continua conferida no domínio (pam_winbind); a lista só mostra o nome.
# Uso (root):
#   lista_login_ad.sh ligar      nsswitch, perfil do PAM e SDDM (ingressar_ad.sh, .deb)
#   lista_login_ad.sh desligar   desfaz tudo e apaga a lista (saída do domínio)
#   lista_login_ad.sh registrar  pam_exec na abertura da sessão: anota $PAM_USER
#   lista_login_ad.sh remover <usuário>   tira um usuário da lista
# Saída: 0 feito ou nada a fazer | 1 erro | 2 uso errado

set -uo pipefail
# O pam_exec roda com o ambiente vazio
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_VERSION="1.7-6"

#####################
## VARIABLE GLOBAL ##
#####################
LISTA_DIR="/var/lib/extrausers"
LISTA="$LISTA_DIR/passwd"
TRAVA="/run/lock/seduc-lista-login-ad.lock"
PERFIL_PAM="seduc-lista-ad"
# Depois do 20-kubuntu.conf (MaximumUid=60000): os arquivos são lidos em ordem
SDDM_CONF="/etc/sddm.conf.d/90-seduc-ad.conf"
NSSWITCH="/etc/nsswitch.conf"
# Faixa do idmap do smb.conf do ingresso (usuários do AD)
UID_MIN=1000000
UID_MAX=19999999

###############
## FUNCTIONS ##
###############
log() { logger -t seduc-lista-login-ad -- "$*" 2>/dev/null || true; }

# O pacote do 26.04 põe a biblioteca em /usr/lib (sem a pasta da arquitetura)
extrausers_instalado() {
    dpkg-query -W -f='${db:Status-Abbrev}' libnss-extrausers 2>/dev/null | grep -q '^ii'
}

sddm_ativo() {
    [ "$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service)" = sddm ]
}

ligar() {
    if ! sddm_ativo; then
        echo "Tela de login não é o SDDM: nada a fazer"
        return 0
    fi
    if ! extrausers_instalado; then
        echo "libnss-extrausers não instalado: lista de usuários do AD desligada"
        return 1
    fi
    install -d -m 755 "$LISTA_DIR"
    [ -f "$LISTA" ] || install -m 644 /dev/null "$LISTA"
    # extrausers depois do winbind: o winbind continua sendo a fonte do usuário
    sed -i -E '/^passwd:/ s/[[:space:]]+extrausers//g; /^passwd:/ s/$/ extrausers/' "$NSSWITCH"
    DEBIAN_FRONTEND=noninteractive pam-auth-update --enable "$PERFIL_PAM" || return 1
    mkdir -p "$(dirname "$SDDM_CONF")"
    # Com o UID máximo na faixa do AD aparecem também contas de sistema acima de 60000
    # (nobody, snap_daemon, snapd-range-*): todas têm shell sem login, e o SDDM as esconde
    # pelo HideShells
    cat > "$SDDM_CONF" <<EOF2
# Gerado pelo lista_login_ad.sh: mostra os usuários do AD que já entraram aqui
[Users]
MaximumUid=$UID_MAX
HideShells=/usr/sbin/nologin,/sbin/nologin,/usr/bin/false,/bin/false
HideUsers=nobody
EOF2
    echo "Lista de usuários do AD na tela de login ligada"
}

desligar() {
    DEBIAN_FRONTEND=noninteractive pam-auth-update --remove "$PERFIL_PAM" 2>/dev/null || true
    sed -i -E '/^passwd:/ s/[[:space:]]+extrausers//g' "$NSSWITCH"
    rm -f "$SDDM_CONF" "$LISTA"
    echo "Lista de usuários do AD na tela de login desligada"
}

# Troca a linha do usuário na lista (arquivo temporário + mv, com trava)
gravar() {
    local NOME="$1" LINHA="${2:-}" TMP
    install -d -m 755 "$LISTA_DIR"
    exec 9>"$TRAVA"
    flock -w 10 9 || return 1
    TMP=$(mktemp "$LISTA_DIR/.passwd.XXXXXX") || return 1
    awk -F: -v n="$NOME" '$1 != n' "$LISTA" 2>/dev/null > "$TMP"
    [ -n "$LINHA" ] && printf '%s\n' "$LINHA" >> "$TMP"
    chmod 644 "$TMP"
    mv -f "$TMP" "$LISTA"
}

registrar() {
    local U="${PAM_USER:-}" LINHA UID_
    [ "${PAM_TYPE:-}" = open_session ] || return 0
    [ -n "$U" ] || return 0
    [ -f "$LISTA" ] || return 0
    LINHA=$(timeout 5 getent passwd "$U") || return 0
    UID_=$(cut -d: -f3 <<< "$LINHA")
    [[ "$UID_" =~ ^[0-9]+$ ]] && (( UID_ >= UID_MIN && UID_ <= UID_MAX )) || return 0
    # Já anotado igual: nada a fazer
    grep -qxF "$LINHA" "$LISTA" && return 0
    gravar "$(cut -d: -f1 <<< "$LINHA")" "$LINHA" && log "$U anotado na lista da tela de login"
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root." >&2
    exit 1
fi

case "${1:-}" in
    ligar)     ligar ;;
    desligar)  desligar ;;
    registrar) registrar; exit 0 ;;   # nunca atrapalha o login
    remover)
        [ -n "${2:-}" ] || { echo "Uso: $0 remover <usuário>" >&2; exit 2; }
        [ -f "$LISTA" ] || exit 0
        gravar "$2" ""
        ;;
    *) echo "Uso: $0 ligar|desligar|registrar|remover <usuário>" >&2; exit 2 ;;
esac
