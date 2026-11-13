#!/usr/bin/env bash

# Confirma a senha do administrador (técnico da CREDE) antes de uma correção de perfil
# da Central do Suporte (Restaurar navegadores, Restaurar painel e tela). Chamado pelo
# pkexec (ação br.gov.ce.seduc.confirmar-tecnico, senha a cada vez); não muda nada no
# sistema, só registra quem autorizou o quê. A correção em si roda como o usuário.
# Uso: confirmar_tecnico.sh <correção>

set -euo pipefail

SCRIPT_VERSION="1.6-2"

LOG="/usr/local/seduc/logs/confirmar_tecnico.log"

if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

ACAO="${1:-}"
[[ "$ACAO" =~ ^[a-z-]{1,40}$ ]] || ACAO="desconhecida"
USUARIO=$(id -nu "${PKEXEC_UID:-0}" 2>/dev/null || echo "${PKEXEC_UID:-?}")

mkdir -p "$(dirname "$LOG")"
echo "$(date '+%d/%m/%Y %H:%M:%S') - $ACAO autorizada para o usuário $USUARIO (versão $SCRIPT_VERSION)" >> "$LOG"
