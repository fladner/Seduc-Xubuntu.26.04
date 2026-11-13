#!/bin/bash

# "Sobre o Xubuntu SEDUC": versão do sistema, compilação, instalação e a quem pertence
# o computador. A Central do Suporte mostra a página web com os dados de --listar.
# Sem argumentos (menu SEDUC), abre essa página da Central; sem o programa da
# Central, ou com --yad, abre a janela em yad.
#   --listar: uma linha por campo, CAMPO|<rótulo>|<valor>, e CONTATO|<e-mail>

set -euo pipefail

if [ -z "${1:-}" ] && command -v central-suporte >/dev/null 2>&1; then
    exec central-suporte --abrir sobre
fi

SCRIPT_VERSION="1.5-2"
SYSTEM_VERSION="$(cat /usr/local/seduc/version 2>/dev/null || echo 1.1-0)"
# Preenchido pelo build.sh com a data da compilação
BUILD="28/10/2026"
ESCOLA="SEDUC"
# Escola ou CREDE e nome do computador da identificação feita nas Boas-vindas
IDENTIFICACAO="/usr/local/seduc/identificacao.conf"
if [ -r "$IDENTIFICACAO" ]; then
    ESCOLA=$(
        . "$IDENTIFICACAO" 2>/dev/null
        if [ "${TIPO:-}" = escola ]; then
            echo "${ESCOLA:-Escola} (INEP ${INEP:-?}) - ${AMBIENTE_NOME:-}"
        elif [ "${TIPO:-}" = crede ]; then
            echo "CREDE ${CREDE:-?} - ${AMBIENTE_NOME:-}"
        else
            echo "SEDUC"
        fi
    )
fi
DISTRO="Seduc Xubuntu 26"
DEV="Tadeu Fladiner Costa Pereira"
THANKS="Carlos Renê P. Jr"
REPORT="tadeu.pereira@seduc.ce.gov.br"


## Informações do sistema
# carrega infos padrão do Ubuntu
. /etc/os-release

# Detecta flavor Ubuntu
detect_flavor() {
  if dpkg -l xubuntu-desktop-minimal >/dev/null 2>&1; then
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

## Pegando a data da instalação formatada (sem /lost+found, como no live, fica "-")
INSTALL=$(date -d "$(stat -c %w /lost+found 2>/dev/null)" +%d/%m/%y 2>/dev/null) || INSTALL="-"

if [ "${1:-}" = "--listar" ]; then
    campo() { printf 'CAMPO|%s|%s\n' "$1" "${2//|/-}"; }
    campo "Este computador pertence" "$ESCOLA"
    campo "Distro" "$DISTRO"
    campo "Versão" "$SYSTEM_VERSION"
    campo "Data da Instalação" "$INSTALL"
    campo "Baseada" "$FLAVOR $LINUX_VERSION ($CODENAME)"
    campo "Compilação" "$BUILD"
    campo "Desenvolvido por" "$DEV"
    campo "Agradecimentos" "$THANKS"
    echo "CONTATO|$REPORT"
    exit 0
fi

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
