#!/bin/bash

set -euo pipefail

SCRIPT_VERSION="1.1-0"
SYSTEM_VERSION="$(cat /usr/local/seduc/version 2>/dev/null || echo 1.1-0)"
# Preenchido pelo build.sh com a data da compilação
BUILD="28/10/2026"
ESCOLA="SEDUC"
DISTRO="Seduc Xubuntu 26"
DEV="Tadeu Fladiner Costa Pereira"
THANKS="Carlos Renê P. Jr"
REPORT="tadeu.pereira@seduc.ce.gov.br"


## Informações do sistema
# carrega infos padrão do Ubuntu
. /etc/os-release

# Detecta flavor Ubuntu
detect_flavor() {
  if dpkg -l xubuntu-desktop-minimal >/dev/null; then
    echo "Xubuntu"
  else
    echo "Ubuntu"
  fi
}

FLAVOR=$(detect_flavor)

# Versão numérica
LINUX_VERSION="$VERSION_ID"

# Nome humano da versão
CODENAME=$(echo "$VERSION" | sed -n 's/.*(\(.*\)).*/\1/p')
CODENAME=${CODENAME:-Unknown}

## Pegando a data da instalação formatada
INSTALL=$(date -d "$(stat -c %w /lost+found)" +%d/%m/%y)

## Mensagem do YAD
TEXT="
<b><big>Informações do Sistema</big></b>

<b>Este computador pertence:</b>
$ESCOLA

<b>Distro:</b> $DISTRO
<b>Versão:</b> $SYSTEM_VERSION
<b>Data da Instalação:</b> $INSTALL
<b>Baseada:</b> $FLAVOR $LINUX_VERSION ($CODENAME)
<b>Compilação:</b> $BUILD
<b>Desenvolvido por:</b> $DEV
<b>Agradecimentos:</b> $THANKS
<b>Reportar bug ou sugestão:</b> $REPORT
"

## Janela do YAD
yad --center \
    --width=450 \
    --height=250 \
    --fixed \
    --window-icon=computer \
    --image=seduc-logo \
    --title="Informações do Sistema" \
    --text="$TEXT" \
    --button="OK:0" \
    --markup
