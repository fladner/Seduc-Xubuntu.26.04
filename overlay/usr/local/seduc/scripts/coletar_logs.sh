#!/usr/bin/env bash

# "Coletar logs para o suporte" da Central do Suporte SEDUC.
# Junta os logs SEDUC e um resumo do computador num .tar.gz na Área de Trabalho,
# para enviar ao suporte. Roda como o próprio usuário: só entra o que ele pode ler.

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.5-0"

#####################
## VARIABLE GLOBAL ##
#####################
TITULO="Coletar logs para o suporte"
ICONE="document-save"
YAD=(yad --title="$TITULO" --window-icon="$ICONE" --center --borders=12)

###############
## FUNCTIONS ##
###############
# Roda um comando e grava a saída em <pasta>/<arquivo>, sem travar se faltar
salvar() {
    local ARQ="$1"; shift
    { echo "\$ $*"; timeout 60 "$@" 2>&1; } > "$PASTA/$ARQ" || true
}

coletar() {
    echo "# Copiando os logs SEDUC..."
    mkdir -p "$PASTA/logs"
    find /usr/local/seduc/logs -maxdepth 1 -type f -readable \
        -exec cp -p {} "$PASTA/logs/" \; 2>/dev/null
    echo 20

    echo "# Lendo as informações do sistema..."
    {
        echo "Computador: $(hostname)"
        echo "Usuário: $(id -un) ($(id -nG))"
        echo "Sistema SEDUC: $(cat /usr/local/seduc/version 2>/dev/null)"
        echo "seduc_setup.sh: $(awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' /usr/local/seduc/scripts/seduc_setup.sh 2>/dev/null)"
        echo "Data: $(date '+%F %T')"
        grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
        echo "Kernel: $(uname -r)"
    } > "$PASTA/resumo.txt"
    # -z oculta endereços MAC, IP público e números de série no inxi
    salvar inxi.txt inxi -Fxxz -c0
    echo 45

    echo "# Lendo rede, discos e serviços..."
    salvar rede.txt ip -br address
    salvar rotas.txt ip route
    salvar dns.txt resolvectl status
    salvar discos.txt lsblk -f
    salvar espaco.txt df -h
    salvar usb.txt lsusb
    salvar servicos-com-falha.txt systemctl --failed --no-pager
    salvar servicos-seduc.txt systemctl status --no-pager seduc_setup.service seduc-trava-perfil.service seduc-fix-netplan.service
    salvar impressoras.txt lpstat -t
    salvar dominio.txt wbinfo --online-status
    salvar pacotes-seduc.txt dpkg -l 'seduc*' google-chrome-stable firefox rustdesk anydesk
    salvar erros-do-boot.txt journalctl -b -p err --no-pager -n 300
    echo 80

    echo "# Compactando..."
    tar -czf "$ARQUIVO" -C "$(dirname "$PASTA")" "$(basename "$PASTA")" 2>/dev/null
    echo 100
}

##########
## MAIN ##
##########
DESTINO=$(xdg-user-dir DESKTOP 2>/dev/null)
[ -d "$DESTINO" ] || DESTINO="$HOME"
NOME="suporte-$(hostname)-$(date +%Y%m%d-%H%M)"
ARQUIVO="$DESTINO/$NOME.tar.gz"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASTA="$TMP/$NOME"
mkdir -p "$PASTA"

# --sem-janela: para a Central do Suporte em web. O andamento sai na saída padrão no mesmo
# formato do yad --progress e o arquivo na linha RESULTADO_ARQUIVO=; sem o arquivo, sai com erro.
if [ "${1:-}" = "--sem-janela" ]; then
    coletar
    if [ -s "$ARQUIVO" ]; then
        echo "RESULTADO_ARQUIVO=$ARQUIVO"
        exit 0
    fi
    echo "Não foi possível criar o arquivo em $DESTINO"
    exit 1
fi

coletar | "${YAD[@]}" --progress --auto-close --no-buttons --width=420 --percentage=0

if [ -s "$ARQUIVO" ]; then
    "${YAD[@]}" --image=dialog-information --width=480 --button="Abrir a pasta:2" --button="OK:0" \
        --text="<b>Logs coletados.</b>\n\nEnvie ao suporte o arquivo:\n<tt>$ARQUIVO</tt>"
    if [ $? -eq 2 ]; then
        xdg-open "$DESTINO" >/dev/null 2>&1 &
    fi
else
    "${YAD[@]}" --image=dialog-error --width=420 --button="OK:0" \
        --text="Não foi possível criar o arquivo em\n$DESTINO"
fi
exit 0
