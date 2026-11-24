#!/usr/bin/env bash

# Página "Proteções da aparência" da Central do Suporte (só administrador).
#   pagina     estado das proteções do computador inteiro: papel de parede
#              (xfce4_backdrop_monitor), tema e aparência (seduc-trava-perfil, a cada
#              boot) e painel do laboratório (kiosk e painel travado)
#   desativar  tarefa: desliga as três, para todos os usuários (protecoes_aparencia.sh
#              pelo pkexec); quem já personalizou mantém, o resto fica como está
#   ativar     tarefa: religa as três
# Roda como o próprio usuário; a mudança é feita como root pelo pkexec.

set -uo pipefail
. "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/central_pagina.sh"

PROTECOES="${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/protecoes_aparencia.sh"
MARCA="${PROTECOES_MARCA:-/usr/local/seduc/flags/aparencia-livre}"

###############
## FUNCTIONS ##
###############
valor() { sed -n "s/^$1=//p" <<< "$ESTADO" | head -1; }

texto_estado() {
    case "$1" in
        ativa)           echo "Protegido" ;;
        desligada)       echo "Liberado" ;;
        sem-laboratorio) echo "Sem perfil laboratório (o painel já é livre)" ;;
        *)               echo "Desconhecido" ;;
    esac
}

pagina() {
    local ESTADO DATA POR
    ESTADO=$("$PROTECOES" estado 2>/dev/null)
    if [ "${CENTRAL_ADMIN:-0}" != 1 ]; then
        erro "Só o administrador muda as proteções da aparência."
        return 0
    fi

    p "Por padrão, o computador devolve a aparência da SEDUC: o papel de parede volta na hora, e o tema, os ícones, as janelas, os atalhos, a energia, o idioma, o painel e o menu voltam a cada vez que o computador liga. No perfil laboratório, o painel também fica travado."
    tabela_inicio
    linha "Papel de parede" "$(texto_estado "$(valor papel)")"
    linha "Tema e aparência" "$(texto_estado "$(valor tema)")"
    linha "Painel do laboratório" "$(texto_estado "$(valor painel)")"
    tabela_fim

    if [ "$(valor tema)" = desligada ]; then
        DATA=$(sed -n 's/^DATA=//p' "$MARCA" 2>/dev/null)
        POR=$(sed -n 's/^POR=//p' "$MARCA" 2>/dev/null)
        [ -n "$DATA" ] && secundario "Desligadas em $DATA${POR:+ por $POR}."
        formulario_tarefa ativar
        grupo "Religar as proteções"
        p "Volta a proteger o computador inteiro. O papel de parede volta ao da SEDUC na hora; o tema e o resto da aparência, quando o computador ligar de novo. No laboratório, o painel volta a ficar travado a partir do próximo login."
        fim_grupo
        botao "Religar as proteções"
        fim_formulario
    else
        formulario_tarefa desativar
        grupo "Desligar as proteções"
        p "Libera o papel de parede, o tema e o painel para todos os usuários deste computador, até alguém religar aqui. A aparência atual não é trocada: cada usuário passa a poder personalizar, e o que mudar fica."
        secundario "O papel de parede fica livre na hora; o painel do laboratório, a partir do próximo login. O sistema pede a senha do administrador."
        fim_grupo
        botao "Desligar as proteções"
        fim_formulario
    fi
}

# mudar desativar|ativar
mudar() {
    local CODIGO
    if [ "${CENTRAL_ADMIN:-0}" != 1 ]; then
        aviso_fim "Só o administrador muda as proteções da aparência."
        return 1
    fi
    mensagem "Aplicando... o sistema vai pedir a senha do administrador."
    progresso 20
    pkexec "$PROTECOES" "$1"
    CODIGO=$?
    progresso 100
    case "$CODIGO:$1" in
        0:desativar) aviso_fim "Proteções da aparência desligadas para todos os usuários. Papel de parede, tema e painel liberados." ;;
        0:ativar)    aviso_fim "Proteções da aparência religadas. O tema volta ao padrão SEDUC quando o computador ligar de novo." ;;
        126:*|127:*) aviso_fim "A senha do administrador não foi confirmada. Nada foi alterado." ;;
        *)           aviso_fim "Não foi possível mudar as proteções. Detalhes em /usr/local/seduc/logs/protecoes_aparencia.log." ;;
    esac
    return "$CODIGO"
}

##########
## MAIN ##
##########
case "${1:-pagina}" in
    pagina)    pagina ;;
    desativar) mudar desativar ;;
    ativar)    mudar ativar ;;
    *) erro "Ação desconhecida."; exit 1 ;;
esac
