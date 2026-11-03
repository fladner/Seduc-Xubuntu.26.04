#!/usr/bin/env bash

# Parte root do painel de tokens (painel_tokens.sh), chamada via pkexec.
# Baseado no instalador_drivers_token.sh (Carlos Renê P. Júnior - CREDE 16).
# Usa os instaladores de /usr/local/seduc/instaladores (vêm na ISO) e só
# baixa da internet o que não estiver lá (Java 8 e Assinador SERPRO sempre).
# Saída no formato do yad --progress: "<porcentagem>" e "# <texto>".
# Uso: instalar_tokens.sh <token|nenhum> [java8] [logus] [serpro] [bry]
#      token: safenet | cryptoid | starsign

set -uo pipefail

SCRIPT_VERSION="1.2-0"

#####################
## VARIABLE GLOBAL ##
#####################
INSTALADORES="/usr/local/seduc/instaladores"
LOG="/usr/local/seduc/logs/instalar_tokens.log"
RELATORIO="/usr/local/seduc/logs/instalar_tokens.relatorio"
LOCAL_APPS="/usr/local/share/applications"
TEMP_DIR=$(mktemp -d)

FIREFOX_EXT_DIR="/usr/share/firefox/distribution/extensions"
FIREFOX_POLICY="/etc/firefox/policies/policies.json"
CHROME_POLICY="/etc/opt/chrome/policies/managed/extensions.json"

# Arquivo local (na ISO) e link de reserva, os mesmos do instalador_drivers_token.sh
declare -A ARQUIVO=(
    [safenet]="safenetauthenticationclient_10.9.4723_amd64.deb"
    [cryptoid]="CryptoIDEUserTools-1.0.1.amd64.deb CryptoIDEAdminTools-1.0.1.amd64.deb"
    [starsign]="safesign-ic-standard-4.4.0.0-ub2404-amd64.deb"
    [logus]="assinador_digital_linux_com_jre.tar.gz"
    [logus_icone]="Logus.png"
    [bry_deb]="bry-ExtensionModule.deb"
    [bry_xpi]="bry-assinatura-digital.xpi"
)
declare -A LINK=(
    [safenet]="https://www.dropbox.com/scl/fi/lo8akie944v65y9xonuww/Linux_SAC_10.9_GA.zip?rlkey=yrzxks3yi5on57254g05sykqt&st=sdfnl5ap&dl=1"
    [cryptoid]="https://www.dropbox.com/scl/fi/ed1tfa9fddbvt0vzvhdbq/CryptoID_Drivers_Linux.zip?rlkey=r8ubzlt5kxppouas2yqnmarrq&st=d00m0sqa&dl=1"
    [starsign]="https://www.dropbox.com/scl/fi/o9blc2g60v107e7z4zdl5/safesign-ic-standard-linux-ub2404-4-4-0-0-aet-000.zip?rlkey=lir7lbixcqbdoxygt3s8a1xxd&st=0bxhbpnj&dl=1"
    [logus]="https://nextcloud.logusinfo.com.br/public.php/dav/files/AeK9dTm4MjPJMq7/assinador_digital_linux_com_jre.tar.gz"
    [logus_icone]="https://www.logusinfo.com.br/wp-content/uploads/2016/07/Logo800-300x300.png"
    [bry_deb]="https://www.bry.com.br/downloads/extension/v2/linux/ExtensionModule.deb"
    [bry_xpi]="https://www.bry.com.br/downloads/extension/firefox/assinatura_digital_bry.xpi"
    [java8]="https://javadl.oracle.com/webapps/download/AutoDL?BundleId=251646_7ed26d28139143f38c58992680c214a5"
    [serpro_chave]="https://assinadorserpro.estaleiro.serpro.gov.br/repository/AssinadorSERPROpublic.pgp"
)
BRY_CHROME="mbpaklahifpfndjiefdfjhmkefppocfm;https://clients2.google.com/service/update2/crx"

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.bak"
exec 3>&1 >"$LOG" 2>&1
: > "$RELATORIO"

echo "===== INÍCIO $(date) - versão $SCRIPT_VERSION ====="
echo "Pedido: $*"

###############
## FUNCTIONS ##
###############
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Progresso para o yad (fd 3) e para o log
progresso() {
    echo "$1" >&3
    echo "# $2" >&3
    echo ">>> [$1%] $2"
}

relatorio() {
    echo "$1|$2" >> "$RELATORIO"
    echo "=== $1: $2"
}

apt_instalar() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" </dev/null
}

# Copia o arquivo da ISO ou baixa do link de reserva. Uso: obter <chave> <destino>
obter() {
    local CHAVE="$1" DESTINO="$2" NOME
    NOME="${ARQUIVO[$CHAVE]:-}"
    if [ -n "$NOME" ] && [ -f "$INSTALADORES/${NOME%% *}" ]; then
        cp "$INSTALADORES/${NOME%% *}" "$DESTINO"
        return 0
    fi
    echo "$CHAVE: não está em $INSTALADORES, baixando ${LINK[$CHAVE]}"
    wget -q --tries=2 --timeout=30 -O "$DESTINO" "${LINK[$CHAVE]}"
}

# .deb dos tokens: da ISO ou de dentro do .zip baixado
obter_debs_token() {
    local TOKEN="$1" NOME TODOS=1
    for NOME in ${ARQUIVO[$TOKEN]}; do
        [ -f "$INSTALADORES/$NOME" ] || TODOS=0
    done
    if (( TODOS )); then
        for NOME in ${ARQUIVO[$TOKEN]}; do
            cp "$INSTALADORES/$NOME" "$TEMP_DIR/"
        done
        return 0
    fi

    echo "$TOKEN: não está em $INSTALADORES, baixando ${LINK[$TOKEN]}"
    wget -q --tries=2 --timeout=30 -O "$TEMP_DIR/driver.zip" "${LINK[$TOKEN]}" || return 1
    case "$TOKEN" in
        safenet)
            unzip -o -j "$TEMP_DIR/driver.zip" \
                "SAC_10.9 GA/Installation/Standard/Ubuntu-2204/*.deb" -d "$TEMP_DIR" ;;
        *)
            unzip -o -j "$TEMP_DIR/driver.zip" '*.deb' -d "$TEMP_DIR" ;;
    esac
}

# Atalhos do driver no menu Sistema
organizar_menu() {
    local DESKTOP ARQ
    mkdir -p "$LOCAL_APPS"
    for DESKTOP in "$@"; do
        [ -f "/usr/share/applications/$DESKTOP" ] || continue
        ARQ="$LOCAL_APPS/$DESKTOP"
        cp -f "/usr/share/applications/$DESKTOP" "$ARQ"
        if grep -q '^Categories=' "$ARQ"; then
            sed -i 's/^Categories=.*/Categories=System;/' "$ARQ"
        else
            echo 'Categories=System;' >> "$ARQ"
        fi
    done
}

verificar_apt() {
    progresso 5 "Verificando o APT..."
    if fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; then
        relatorio "APT" "ocupado por outro programa (atualização automática?). Tente mais tarde"
        exit 1
    fi
    dpkg --configure -a
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y </dev/null
}

instalar_token() {
    local TOKEN="$1" NOME
    declare -A NOMES=([safenet]="Safenet eToken 5100" [cryptoid]="mToken CryptoID" [starsign]="StarSign CUT S (SafeSign)")
    NOME="${NOMES[$TOKEN]}"

    progresso 15 "Preparando o driver $NOME..."
    if ! obter_debs_token "$TOKEN"; then
        relatorio "$NOME" "FALHA no download do driver"
        return 1
    fi

    progresso 30 "Instalando o driver $NOME..."
    if ! apt_instalar "$TEMP_DIR"/*.deb; then
        relatorio "$NOME" "FALHA na instalação (veja o log)"
        return 1
    fi

    mkdir -p /usr/lib/pkcs11
    case "$TOKEN" in
        safenet)
            [ -f /usr/lib/libeTPkcs11.so ] && ln -sf /usr/lib/libeTPkcs11.so /usr/lib/pkcs11/libeTPkcs11.so
            [ -f /usr/lib/libeToken.so ] && ln -sf /usr/lib/libeToken.so /usr/lib/pkcs11/libeToken.so
            organizar_menu SACMonitor.desktop SACTools.desktop
            ;;
        cryptoid)
            local LIB=/opt/CryptoIDEUser/x64/lib/linux/x64/libcryptoide_pkcs11.so
            [ -f "$LIB" ] && ln -sf "$LIB" /usr/lib/pkcs11/libcryptoide_pkcs11.so
            organizar_menu mToken_CryptoID_Certificate_Utility.desktop mToken_CryptoID_Manager.desktop
            ;;
        starsign)
            [ -f /usr/lib/libaetpkss.so ] && ln -sf /usr/lib/libaetpkss.so /usr/lib/pkcs11/libaetpkss.so
            ;;
    esac
    systemctl enable --now pcscd.socket || true
    relatorio "$NOME" "instalado"
}

instalar_java8() {
    local DIR="$TEMP_DIR/java8" JAVA
    progresso 45 "Baixando o Oracle Java 8 (precisa de internet)..."
    mkdir -p "$DIR"
    if ! obter java8 "$DIR/java.tar.gz"; then
        relatorio "Java 8" "FALHA no download"
        return 1
    fi
    progresso 50 "Instalando o Oracle Java 8 em /opt/java..."
    tar -xzf "$DIR/java.tar.gz" --no-same-owner -C "$DIR" || { relatorio "Java 8" "FALHA ao extrair"; return 1; }
    JAVA=$(find "$DIR" -maxdepth 1 -type d -name 'jre*' | head -n1)
    [ -n "$JAVA" ] || { relatorio "Java 8" "FALHA: pasta jre não encontrada"; return 1; }
    rm -rf /opt/java
    mv "$JAVA" /opt/java
    update-alternatives --install /usr/bin/java java /opt/java/bin/java 1
    update-alternatives --set java /opt/java/bin/java
    if [ -x /opt/java/bin/javaws ]; then
        update-alternatives --install /usr/bin/javaws javaws /opt/java/bin/javaws 1
        update-alternatives --set javaws /opt/java/bin/javaws
    fi
    relatorio "Java 8" "instalado"
}

instalar_logus() {
    local DIR="/opt/AssinadorLogus"
    progresso 60 "Instalando o Assinador Logus..."
    if ! obter logus "$TEMP_DIR/assinador.tar.gz"; then
        relatorio "Assinador Logus" "FALHA no download"
        return 1
    fi
    rm -rf "$DIR"
    mkdir -p "$DIR"
    tar -xzf "$TEMP_DIR/assinador.tar.gz" --no-same-owner --strip-components=1 -C "$DIR" || {
        relatorio "Assinador Logus" "FALHA ao extrair"
        return 1
    }
    obter logus_icone "$DIR/assinador.png" || true
    chmod +x "$DIR/AssinadorLogus.sh"
    mkdir -p "$LOCAL_APPS"
    printf '%s\n' \
        '[Desktop Entry]' \
        'Version=1.0' \
        'Name=Assinador Logus' \
        'Comment=Certificado Digital – Siafe' \
        "Exec=$DIR/AssinadorLogus.sh" \
        "Icon=$DIR/assinador.png" \
        'Terminal=false' \
        'Type=Application' \
        'Categories=SEDUC;' \
        'StartupNotify=true' \
        > "$LOCAL_APPS/AssinadorLogus.desktop"
    relatorio "Assinador Logus" "instalado"
}

instalar_serpro() {
    local CHAVE="/usr/share/keyrings/assinador-serpro.gpg"
    local FONTE="/etc/apt/sources.list.d/assinador-serpro.sources"
    local DESKTOP="/usr/share/applications/serpro-signer.desktop"

    progresso 70 "Configurando o repositório do Assinador SERPRO (precisa de internet)..."
    if ! obter serpro_chave "$TEMP_DIR/serpro.pgp" || ! gpg --dearmor < "$TEMP_DIR/serpro.pgp" > "$TEMP_DIR/serpro.gpg"; then
        relatorio "Assinador SERPRO" "FALHA ao baixar a chave do repositório"
        return 1
    fi
    install -m 644 "$TEMP_DIR/serpro.gpg" "$CHAVE"
    rm -f /etc/apt/sources.list.d/assinador-serpro.list
    printf '%s\n' \
        'Types: deb' \
        'URIs: https://assinadorserpro.estaleiro.serpro.gov.br/repository/' \
        'Suites: universal' \
        'Components: stable' \
        'Architectures: amd64' \
        "Signed-By: $CHAVE" \
        > "$FONTE"
    apt-get update -qq || { relatorio "Assinador SERPRO" "FALHA no apt-get update"; return 1; }

    progresso 75 "Instalando o Assinador SERPRO..."
    # O instalador pergunta se o assinador inicia com o sistema: responde 0
    expect <<-EOF
		set timeout 900
		spawn env DEBIAN_FRONTEND=noninteractive apt-get install -y assinador-serpro
		expect {
		    -re "Iniciar o Assinador junto com o sistema" { send "0\r"; exp_continue }
		    timeout { exit 1 }
		    eof
		}
		catch wait result
		exit [lindex \$result 3]
	EOF

    if ! dpkg-query -W -f='${db:Status-Abbrev}' assinador-serpro 2>/dev/null | grep -q '^ii'; then
        relatorio "Assinador SERPRO" "FALHA na instalação (veja o log)"
        return 1
    fi
    if [ -f "$DESKTOP" ]; then
        mkdir -p "$LOCAL_APPS"
        cp -f "$DESKTOP" "$LOCAL_APPS/serpro-signer.desktop"
        if grep -q '^Categories=' "$LOCAL_APPS/serpro-signer.desktop"; then
            sed -i 's/^Categories=.*/Categories=SEDUC;/' "$LOCAL_APPS/serpro-signer.desktop"
        else
            echo 'Categories=SEDUC;' >> "$LOCAL_APPS/serpro-signer.desktop"
        fi
    fi
    relatorio "Assinador SERPRO" "instalado"
}

instalar_bry() {
    local ID
    progresso 85 "Instalando a extensão BRy no Firefox e no Chrome..."
    if ! obter bry_xpi "$TEMP_DIR/bry.xpi" || ! obter bry_deb "$TEMP_DIR/bry.deb"; then
        relatorio "Extensão BRy" "FALHA no download"
        return 1
    fi
    ID=$(unzip -p "$TEMP_DIR/bry.xpi" manifest.json | jq -r '.browser_specific_settings.gecko.id // .applications.gecko.id // empty')
    [ -n "$ID" ] || { relatorio "Extensão BRy" "FALHA: ID da extensão vazio"; return 1; }

    mkdir -p "$FIREFOX_EXT_DIR" "$(dirname "$FIREFOX_POLICY")" "$(dirname "$CHROME_POLICY")"
    install -m 644 "$TEMP_DIR/bry.xpi" "$FIREFOX_EXT_DIR/$ID.xpi"
    [ -s "$FIREFOX_POLICY" ] || echo '{"policies":{}}' > "$FIREFOX_POLICY"
    [ -s "$CHROME_POLICY" ] || echo '{}' > "$CHROME_POLICY"

    jq --arg xpi "$FIREFOX_EXT_DIR/$ID.xpi" '
        .policies.Extensions.Install = ((.policies.Extensions.Install // []) | if index($xpi) then . else . + [$xpi] end)
    ' "$FIREFOX_POLICY" > "$FIREFOX_POLICY.tmp" && mv -f "$FIREFOX_POLICY.tmp" "$FIREFOX_POLICY"
    jq --arg ext "$BRY_CHROME" '
        .ExtensionInstallForcelist = ((.ExtensionInstallForcelist // []) | if index($ext) then . else . + [$ext] end)
    ' "$CHROME_POLICY" > "$CHROME_POLICY.tmp" && mv -f "$CHROME_POLICY.tmp" "$CHROME_POLICY"
    chmod 644 "$FIREFOX_POLICY" "$CHROME_POLICY"

    if ! apt_instalar "$TEMP_DIR/bry.deb"; then
        relatorio "Extensão BRy" "FALHA na instalação do módulo (veja o log)"
        return 1
    fi
    relatorio "Extensão BRy" "instalada (reabra os navegadores)"
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

TOKEN="${1:-nenhum}"
shift || true

verificar_apt

case "$TOKEN" in
    safenet|cryptoid|starsign) instalar_token "$TOKEN" ;;
    nenhum) ;;
    *) relatorio "Token" "inválido: $TOKEN"; exit 1 ;;
esac

for EXTRA in "$@"; do
    case "$EXTRA" in
        java8)  instalar_java8 ;;
        logus)  instalar_logus ;;
        serpro) instalar_serpro ;;
        bry)    instalar_bry ;;
        *)      relatorio "$EXTRA" "opção inválida" ;;
    esac
done

update-desktop-database "$LOCAL_APPS" || true
progresso 100 "Concluído"
echo "===== FIM $(date) ====="

grep -q '|FALHA' "$RELATORIO" && exit 2
exit 0
