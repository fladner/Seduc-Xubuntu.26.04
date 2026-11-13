#!/usr/bin/env bash

# Funções para as páginas em bash da Central do Suporte (central.d/paginas/<nome>.sh).
# Uso no começo da página:  . /usr/local/seduc/scripts/central_pagina.sh
#
# A Central roda "<nome>.sh <ação>" e mostra o HTML que o script imprimir:
#   ação "pagina"  abertura da página (GET)
#   outra ação     botão de um formulário (POST); sem saída, a Central volta para a página
# Campos do formulário: variáveis F_<campo> (campo = letras minúsculas, números e _).
# Também: CENTRAL_PAGINA, CENTRAL_ACAO, CENTRAL_ADMIN (1/0), CENTRAL_SCRIPTS, CENTRAL_URL.
# Tudo que vem do usuário ou de comandos passa por "esc" antes de entrar no HTML.
# Sem JavaScript próprio: a Central não roda scripts das páginas (só os dela).

SCRIPT_VERSION="1.6-2"

# HTML escapado, sem quebra de linha no fim
esc() {
    local t="$*"
    t=${t//&/&amp;}
    t=${t//</&lt;}
    t=${t//>/&gt;}
    t=${t//\"/&quot;}
    t=${t//\'/&#39;}
    printf '%s' "$t"
}

# Valor de um campo do formulário (sem escapar): campo nome
campo() {
    local v="F_$1"
    printf '%s' "${!v:-}"
}

# Parágrafos e avisos (texto escapado)
p()          { printf '<p>%s</p>\n' "$(esc "$*")"; }
secundario() { printf '<p class="secundario">%s</p>\n' "$(esc "$*")"; }
ok()         { printf '<p class="ok">%s</p>\n' "$(esc "$*")"; }
erro()       { printf '<p class="erro" role="alert">%s</p>\n' "$(esc "$*")"; }
titulo()     { printf '<h2>%s</h2>\n' "$(esc "$*")"; }

# Texto pré-formatado (saída de comando): ... | pre
pre() {
    printf '<pre class="registro">'
    local l
    while IFS= read -r l || [ -n "$l" ]; do
        esc "$l"; printf '\n'
    done
    printf '</pre>\n'
}

# Tabela de duas colunas: tabela_inicio; linha "Rótulo" "valor"; tabela_fim
tabela_inicio() { printf '<table class="relatorio"><tbody>\n'; }
linha()         { printf '<tr><th scope="row">%s</th><td>%s</td></tr>\n' "$(esc "$1")" "$(esc "${2:-}")"; }
tabela_fim()    { printf '</tbody></table>\n'; }

# Formulário de uma ação rápida (resposta na hora) ou de uma tarefa (barra e saída ao vivo)
formulario()        { printf '<form method="post" action="%s/%s">\n' "$CENTRAL_URL" "$(esc "$1")"; }
formulario_tarefa() { printf '<form method="post" action="%s/tarefa/%s">\n' "$CENTRAL_URL" "$(esc "$1")"; }
fim_formulario()    { printf '</form>\n'; }

# Grupo de campos com título (quadro como o das Boas-vindas): grupo "Título" ... fim_grupo
grupo()     { printf '<fieldset><legend>%s</legend>\n' "$(esc "$*")"; }
fim_grupo() { printf '</fieldset>\n'; }

# Campo de texto: texto nome "Rótulo" [valor]
texto() {
    printf '<div class="campos"><label for="%s">%s</label><input type="text" id="%s" name="%s" value="%s"></div>\n' \
        "$(esc "$1")" "$(esc "$2")" "$(esc "$1")" "$(esc "$1")" "$(esc "${3:-}")"
}

# Caixa de marcar: marcar nome "Rótulo" [1 = marcada]
marcar() {
    local m=""
    [ "${3:-}" = 1 ] && m=" checked"
    printf '<label class="opcao"><input type="checkbox" name="%s" value="1"%s> %s</label>\n' \
        "$(esc "$1")" "$m" "$(esc "$2")"
}

# Opção de escolha única: escolha nome valor "Rótulo" [1 = marcada] ["explicação"]
escolha() {
    local m=""
    [ "${4:-}" = 1 ] && m=" checked"
    printf '<label class="opcao"><input type="radio" name="%s" value="%s"%s> <span>%s' \
        "$(esc "$1")" "$(esc "$2")" "$m" "$(esc "$3")"
    [ -n "${5:-}" ] && printf ' <small>%s</small>' "$(esc "$5")"
    printf '</span></label>\n'
}

# Botões: botao "Rótulo" (principal) | botao_secundario "Rótulo"
botao()            { printf '<div class="botoes"><button class="primario" type="submit">%s</button></div>\n' "$(esc "$*")"; }
botao_secundario() { printf '<div class="botoes"><button type="submit">%s</button></div>\n' "$(esc "$*")"; }

# Na tarefa: andamento (protocolo do yad --progress) e aviso do fim
progresso() { echo "$1"; }
mensagem()  { echo "# $*"; }
aviso_fim() { echo "RESULTADO_AVISO=$*"; }

# Na tarefa: pede a senha do administrador (técnico da CREDE) antes de uma correção.
# confirmar_tecnico <correção> || return 1   (a correção vai para o log do suporte)
confirmar_tecnico() {
    mensagem "Confirmando a senha do administrador (técnico da CREDE)..."
    pkexec "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/confirmar_tecnico.sh" "$1"
    case $? in
        0) echo "Senha do administrador confirmada"; return 0 ;;
        126|127) aviso_fim "A senha do administrador não foi confirmada. Nada foi alterado." ;;
        *) aviso_fim "Não foi possível confirmar a senha do administrador. Nada foi alterado." ;;
    esac
    return 1
}
