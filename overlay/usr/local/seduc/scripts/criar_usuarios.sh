#!/usr/bin/env bash

# Chamado pelo welcome.sh via pkexec com os logins marcados, na ordem da lista.
# Uso: criar_usuarios.sh <login> [login...]

set -euo pipefail

SCRIPT_VERSION="1.1-0"

#####################
## VARIABLE GLOBAL ##
#####################
SCRIPTS="/usr/local/seduc/scripts"
LOG="/usr/local/seduc/logs/criar_usuarios.log"

# Nome exibido de cada usuário da escola. Mantenha em sincronia com welcome.sh
declare -A NOMES=(
    ["direcao"]="Direção"
    ["coordenacao"]="Coordenação"
    ["secretaria"]="Secretaria"
    ["financeiro"]="Financeiro"
    ["professores"]="Professores"
    ["multimeios"]="Multimeios"
    ["aee"]="AEE"
    ["gremio"]="Grêmio"
)

# Abreviação usada no hostname (esc-<abrev>-<serial>)
declare -A ABREV=(
    ["direcao"]="dir"
    ["coordenacao"]="coord"
    ["secretaria"]="sec"
    ["financeiro"]="fin"
    ["professores"]="prof"
    ["multimeios"]="multi"
    ["aee"]="aee"
    ["gremio"]="gre"
)

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.bak"
exec > >(tee "$LOG") 2>&1

echo "===== INÍCIO $(date) - versão $SCRIPT_VERSION ====="
echo "Usuários pedidos: $*"

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Nenhum usuário informado."
    exit 1
fi

ALUNO=0
ESCOLA=()

for LOGIN in "$@"; do
    if [[ "$LOGIN" == "aluno" ]]; then
        ALUNO=1
    elif [[ -n "${NOMES[$LOGIN]:-}" ]]; then
        ESCOLA+=("$LOGIN")
    else
        echo "Usuário inválido: $LOGIN"
        exit 1
    fi
done

# Cada script de perfil define hostname e tema, então o último a rodar vence.
# Rodamos em ordem inversa para que o primeiro marcado defina o computador.
for (( i=${#ESCOLA[@]}-1; i>=0; i-- )); do
    LOGIN="${ESCOLA[$i]}"
    echo "--- Configurando ${NOMES[$LOGIN]} ($LOGIN)"
    "$SCRIPTS/configurar_perfil_escola.sh" \
        "$LOGIN" "${NOMES[$LOGIN]}" "$LOGIN" "${ABREV[$LOGIN]}" "esc"
done

# Aluno é sempre o primeiro da lista: se marcado, o computador vira laboratório
if (( ALUNO )); then
    echo "--- Configurando Aluno (laboratório)"
    "$SCRIPTS/configurar_perfil_lab.sh" "Aluno" "alu" "lab"
fi

echo "===== FIM $(date) ====="
