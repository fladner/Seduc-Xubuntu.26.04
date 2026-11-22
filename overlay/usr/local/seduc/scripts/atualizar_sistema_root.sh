#!/usr/bin/env bash

# Parte root do "Atualizar o sistema" (atualizar_sistema.sh), chamada via pkexec.
# Atualiza todos os pacotes (atualizar_pacotes.sh, o mesmo da atualização automática)
# e roda o seduc_setup.sh na hora, sem esperar o boot.
# A saída vai para a janela e para o log; se a janela for fechada, continua.

set -uo pipefail

SCRIPT_VERSION="1.7-0"

#####################
## VARIABLE GLOBAL ##
#####################
LOG="/usr/local/seduc/logs/atualizar_sistema.log"
SETUP_LOG="/usr/local/seduc/logs/seduc_setup.log"
VERSAO_SETUP() { awk -F'"' '/^SCRIPT_VERSION=/{print $2; exit}' /usr/local/seduc/scripts/seduc_setup.sh; }
PACOTES="/usr/local/seduc/scripts/atualizar_pacotes.sh"

#########
## LOG ##
#########
# Janela fechada no meio não pode derrubar o apt
trap '' PIPE
mkdir -p "$(dirname "$LOG")"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.old"
exec > >(tee -p -a "$LOG") 2>&1

etapa() {
    echo
    echo "==> $*"
}

###############
## FUNCTIONS ##
###############
# O seduc_setup.service roda no boot; espera ele terminar antes de rodar de novo
esperar_setup_boot() {
    local N=0
    while [ "$(systemctl is-active seduc_setup.service 2>/dev/null)" = "activating" ]; do
        (( N == 0 )) && echo "A atualização do boot ainda está rodando, aguardando..."
        sleep 5
        N=$((N + 1))
        (( N >= 120 )) && { echo "ERRO: a atualização do boot não terminou em 10 minutos."; return 1; }
    done
}

rodar_setup() {
    systemctl restart seduc_setup.service
    local RET=$?
    grep -E '^\[(INFO|ERROR)\]' "$SETUP_LOG" 2>/dev/null | sed 's/^\[[A-Z]*\] [0-9-]* [0-9:]* - /   /' | tail -20
    return "$RET"
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

if grep -q casper /proc/cmdline; then
    echo "No modo live (pendrive) o sistema não é atualizado."
    exit 1
fi

echo "===== INÍCIO $(date '+%F %T') - versão $SCRIPT_VERSION ====="
FALHAS=0

# Concluir instalações interrompidas, buscar, baixar e instalar (etapas "==> ")
"$PACOTES" || FALHAS=$((FALHAS + 1))

etapa "Atualizando o sistema SEDUC (seduc_setup.sh)"
if esperar_setup_boot; then
    ANTES=$(VERSAO_SETUP)
    rodar_setup || FALHAS=$((FALHAS + 1))
    DEPOIS=$(VERSAO_SETUP)
    # Versão nova só vale a partir da execução seguinte: roda de novo já com ela
    if [ "$ANTES" != "$DEPOIS" ]; then
        etapa "Aplicando o seduc_setup.sh $DEPOIS"
        rodar_setup || FALHAS=$((FALHAS + 1))
    fi
else
    FALHAS=$((FALHAS + 1))
fi

echo
if (( FALHAS )); then
    echo "===== FIM $(date '+%F %T'): $FALHAS etapa(s) com erro ====="
    exit 2
fi
echo "===== FIM $(date '+%F %T'): tudo atualizado ====="
exit 0
