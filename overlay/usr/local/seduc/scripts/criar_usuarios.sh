#!/usr/bin/env bash

# Chamado pelo welcome.sh via pkexec com os logins marcados, na ordem da lista.
# Uso: criar_usuarios.sh [--id <escola|crede> <INEP|CREDE> <AMBIENTE> <nome da escola> | --manter-nome] <login> [login...]
# Com --id (Central do Suporte), o nome do computador vem do identificar_computador.sh;
# sem ele, do primeiro usuário marcado, como antes.

set -euo pipefail

SCRIPT_VERSION="1.6-1"

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

IDENT=()
MANTER_NOME=0
if [[ "${1:-}" == "--manter-nome" ]]; then
    MANTER_NOME=1
    shift
elif [[ "${1:-}" == "--id" ]]; then
    if [[ $# -lt 5 ]]; then
        echo "--id pede tipo, código, ambiente e nome da escola."
        exit 1
    fi
    IDENT=("$2" "$3" "$4" "$5")
    shift 5
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

# --manter-nome (Boas-vindas sem INEP): os scripts de perfil trocam o nome do
# computador; o nome de antes volta no fim
NOME_ANTES=$(hostnamectl hostname 2>/dev/null || hostname)
HOSTS_ANTES=$(grep -m1 '^127\.0\.1\.1' /etc/hosts || true)

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

# Por último: o nome pela escola/CREDE, ambiente e serial substitui o dos perfis
if (( ${#IDENT[@]} )); then
    echo "--- Identificando o computador"
    "$SCRIPTS/identificar_computador.sh" "${IDENT[@]}"
elif (( MANTER_NOME )) && [[ -n "$NOME_ANTES" ]]; then
    echo "--- Mantendo o nome do computador: $NOME_ANTES"
    hostnamectl hostname "$NOME_ANTES"
    if [[ -n "$HOSTS_ANTES" ]]; then
        sed -i "s/^127\.0\.1\.1.*/$HOSTS_ANTES/" /etc/hosts
    fi
fi

echo "===== FIM $(date) ====="
