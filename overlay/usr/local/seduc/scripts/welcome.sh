#!/usr/bin/env bash

# Sem "set -e": em script de interface um erro não pode fechar a janela sem aviso.
set -uo pipefail

SCRIPT_VERSION="1.1-0"

#####################
## VARIABLE GLOBAL ##
#####################
LOG="/usr/local/seduc/logs/welcome.log"
FLAG="/usr/local/seduc/flags/pos-install"
CRIAR_USUARIOS="/usr/local/seduc/scripts/criar_usuarios.sh"

# Usuários disponíveis: login|Nome exibido|Grupo
# O login também é a senha padrão. Mantenha em sincronia com criar_usuarios.sh
USUARIOS=(
    "aluno|Aluno|Laboratório"
    "direcao|Direção|Núcleo gestor"
    "coordenacao|Coordenação|Núcleo gestor"
    "secretaria|Secretaria|Núcleo gestor"
    "financeiro|Financeiro|Núcleo gestor"
    "professores|Professores|Apoio"
    "multimeios|Multimeios|Apoio"
    "aee|AEE|Apoio"
    "gremio|Grêmio|Apoio"
)

#########
## LOG ##
#########
mkdir -p "$(dirname "$LOG")" 2>/dev/null
if [ ! -w "$(dirname "$LOG")" ]; then
    LOG="${XDG_CACHE_HOME:-$HOME/.cache}/seduc-welcome.log"
    mkdir -p "$(dirname "$LOG")"
fi
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.bak"
exec >"$LOG" 2>&1

echo "===== INÍCIO $(date) - versão $SCRIPT_VERSION ====="

###############
## FUNCTIONS ##
###############

# Verifica se está rodando em ambiente Live
check_live() {
    if grep -q "casper" /proc/cmdline; then
        echo "Ambiente Live detectado. Saindo..."
        exit 0
    fi
}

# Verifica se a flag de pós-instalação existe
check_flag() {
    if [ -f "$FLAG" ]; then
        echo "Pós-instalação já executada. Saindo..."
        exit 0
    fi
}

# Só o administrador (grupo sudo) configura o computador
check_admin() {
    if ! id -nG | tr ' ' '\n' | grep -qx sudo; then
        echo "Usuário $(id -un) não é administrador. Saindo..."
        exit 0
    fi
}

# Tela de boas-vindas ao administrador
show_welcome() {
    yad --title="Bem-vindo" \
        --width=480 --height=300 \
        --center \
        --borders=10 \
        --window-icon=help-about \
        --image=seduc-logo \
        --text="<b>Bem-vindo(a), administrador(a)!</b>

Este é o Linux da Secretaria de Educação - SEDUC, baseado no <b>Xubuntu 26.04 LTS</b>.

Agora vamos preparar este computador para uso: na próxima tela você escolhe quais usuários serão criados nele.

Clique em <b>Avançar</b> para continuar." \
        --button="Sair:1" --button="Avançar:0"
}

# Lista os usuários e devolve os logins marcados, um por linha
select_usuarios() {
    local LINHAS=() ITEM LOGIN NOME GRUPO

    for ITEM in "${USUARIOS[@]}"; do
        IFS="|" read -r LOGIN NOME GRUPO <<< "$ITEM"
        LINHAS+=(FALSE "$NOME" "$GRUPO" "$LOGIN" "$LOGIN")
    done

    yad --list --checklist \
        --title="Usuários do computador" \
        --width=520 --height=440 \
        --center \
        --borders=10 \
        --window-icon=system-users \
        --text="Marque os usuários que devem ser criados neste computador.\n\nO <b>primeiro usuário marcado</b> define o nome do computador e o tema." \
        --column="Criar:CHK" --column="Usuário" --column="Grupo" \
        --column="Login" --column="Senha padrão" \
        --print-column=4 --separator="" \
        --button="Voltar:1" --button="Avançar:0" \
        "${LINHAS[@]}"
}

# Confirma a lista e as senhas antes de aplicar
confirm_usuarios() {
    local TEXTO="" LOGIN

    for LOGIN in "$@"; do
        TEXTO+=" • Usuário <b>$LOGIN</b>, senha <b>$LOGIN</b>\n"
    done

    yad --question \
        --title="Confirmar usuários" \
        --width=450 \
        --center \
        --borders=10 \
        --text="Serão criados os usuários:\n\n${TEXTO}\nRecomenda-se alterar as senhas após o primeiro login.\nA senha do administrador será solicitada a seguir." \
        --button="Voltar:1" --button="Criar usuários:0"
}

# Cria os usuários como root, com barra de progresso
setup_usuarios() {
    local STATUS_FILE STATUS

    STATUS_FILE=$(mktemp)
    echo 1 > "$STATUS_FILE"

    (
        echo "# Criando usuários e configurando o computador..."
        # A saída vai para o log do próprio script, nunca para o yad
        pkexec "$CRIAR_USUARIOS" "$@" >/dev/null 2>&1
        echo $? > "$STATUS_FILE"
        echo "100"
    ) | yad --progress \
        --title="Configurando o computador" \
        --text="Aguarde enquanto o sistema é configurado..." \
        --center \
        --pulsate \
        --no-cancel \
        --auto-close \
        --width=400

    STATUS=$(cat "$STATUS_FILE")
    rm -f "$STATUS_FILE"
    echo "criar_usuarios.sh terminou com código $STATUS"

    return "$STATUS"
}

# Oferece reiniciar para aplicar nome do computador e tema
finish() {
    yad --question \
        --title="Configuração concluída" \
        --width=420 \
        --center \
        --borders=10 \
        --text="Configuração concluída com sucesso!\n\nReinicie o computador para aplicar o nome do computador e o tema." \
        --button="Depois:1" --button="Reiniciar agora:0" \
        && systemctl reboot
}

##########
## MAIN ##
##########
check_live
check_flag
check_admin
show_welcome || exit 0

while true; do
    # Voltar/fechar na lista retorna à boas-vindas
    if ! SAIDA=$(select_usuarios); then
        show_welcome || exit 0
        continue
    fi

    mapfile -t SELECIONADOS < <(printf '%s\n' "$SAIDA" | tr -d '|' | sed '/^[[:space:]]*$/d')

    if [ "${#SELECIONADOS[@]}" -eq 0 ]; then
        yad --warning --title="Nenhum usuário" --center --borders=10 \
            --text="Marque pelo menos um usuário para continuar." \
            --button="Voltar à lista:0" --button="Sair:1" || exit 0
        continue
    fi

    echo "Selecionados: ${SELECIONADOS[*]}"
    confirm_usuarios "${SELECIONADOS[@]}" || continue

    if setup_usuarios "${SELECIONADOS[@]}"; then
        finish
        break
    fi

    yad --error --title="Erro" --center --borders=10 \
        --text="Erro durante a configuração.\n\nDetalhes em: $LOG\ne em /usr/local/seduc/logs/criar_usuarios.log" \
        --button="Tentar novamente:0" --button="Sair:1" || exit 1
done

echo "===== FIM $(date) ====="
