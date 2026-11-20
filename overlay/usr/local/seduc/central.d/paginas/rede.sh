#!/usr/bin/env bash

# Página "Ferramentas de rede" da Central do Suporte.
#   pagina    placas de rede (cabo e Wi-Fi), endereço, roteador, DNS e domínio
#   testar    tarefa: testa passo a passo (placa, endereço, roteador, DNS, internet,
#             sites, domínio SEDUC e, se pedido, a velocidade), diz o provável problema
#             e salva um relatório na Área de Trabalho para o suporte
#   renovar   tarefa: reconecta as conexões ativas (novo endereço pelo DHCP)
#   limpardns limpa o cache de DNS do computador
#   renomear  tarefa (administrador): troca o nome do computador pelo
#             renomear_computador.sh, com a senha do administrador (pkexec)
# Roda como o próprio usuário: o NetworkManager e o resolved deixam o usuário da sessão
# reconectar e limpar o cache sem a senha do administrador.

set -uo pipefail
. "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/central_pagina.sh"
. "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/dominio_ad.sh"

AD_CONF="/usr/local/seduc/ad/ad.conf"
SITES=("www.seduc.ce.gov.br|Site da SEDUC" "www.gov.br|gov.br" "www.google.com|Google")
NOME_TESTE="www.seduc.ce.gov.br"
# Download para medir a velocidade (25 MB, servidor da Cloudflare)
VELOCIDADE_URL="https://speed.cloudflare.com/__down?bytes=25000000"

###############
## FUNCTIONS ##
###############

# Placas de rede de verdade: DEVICE|TYPE|STATE|CONNECTION (sem lo, p2p, docker...)
placas() {
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null |
        awk -F: '$2 == "ethernet" || $2 == "wifi"'
}

ipv4()       { ip -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4; exit}'; }
mac()        { cat "/sys/class/net/$1/address" 2>/dev/null; }
roteador()   { ip -4 route show default 2>/dev/null | awk '{print $3; exit}'; }
velocidade() { local V; V=$(cat "/sys/class/net/$1/speed" 2>/dev/null) && [ "${V:-0}" -gt 0 ] && echo "$V Mb/s"; }
wifi_atual() { nmcli -t -f IN-USE,SSID,SIGNAL device wifi list ifname "$1" --rescan no 2>/dev/null | awk -F: '$1 == "*" {print $2 " (sinal " $3 "%)"; exit}'; }

servidores_dns() {
    resolvectl dns 2>/dev/null | awk -F': ' 'NF > 1 && $2 != "" {print $2}' | tr ' ' '\n' | grep -v '^$' | sort -u
}

dominio_ad() {
    local DOMINIO=""
    [ -r "$AD_CONF" ] && DOMINIO=$(DOMINIO=""; . "$AD_CONF" >/dev/null 2>&1; echo "$DOMINIO")
    echo "$DOMINIO"
}

# No domínio pela configuração do ingresso (dominio_ad.sh), mesmo com o winbind parado
no_dominio() { computador_no_dominio; }

estado_placa() {
    case "$1" in
        connected) echo "conectada" ;;
        disconnected) echo "desconectada" ;;
        unavailable) echo "sem cabo ou desligada" ;;
        connecting*) echo "conectando" ;;
        *) echo "$1" ;;
    esac
}

# ping_resumo HOST: "<perda>|<média em ms, uma casa>" (perda 100 = sem resposta)
ping_resumo() {
    local S PERDA MEDIA
    S=$(LC_ALL=C ping -c 4 -i 0.3 -W 2 -q "$1" 2>/dev/null)
    PERDA=$(printf '%s' "$S" | sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p')
    MEDIA=$(printf '%s' "$S" | sed -n 's|^rtt [^=]*= [0-9.]*/\([0-9.]*\)/.*|\1|p')
    [ -n "$MEDIA" ] && MEDIA=$(LC_ALL=C printf '%.1f' "$MEDIA")
    echo "${PERDA:-100}|${MEDIA/./,}"
}

pagina() {
    local DEV TIPO EST CON IP V W GW DNS DOM
    tabela_inicio
    linha "Computador" "$(hostname)"
    while IFS=: read -r DEV TIPO EST CON; do
        IP=$(ipv4 "$DEV")
        if [ "$TIPO" = wifi ]; then
            W=$(wifi_atual "$DEV")
            linha "Wi-Fi ($DEV)" "$(estado_placa "$EST")${W:+, rede $W}${IP:+, endereço $IP}"
        else
            V=$(velocidade "$DEV")
            linha "Cabo ($DEV)" "$(estado_placa "$EST")${V:+, $V}${IP:+, endereço $IP}"
        fi
        linha "  MAC ($DEV)" "$(mac "$DEV")"
    done < <(placas)
    GW=$(roteador)
    linha "Roteador" "${GW:-nenhum}"
    DNS=$(servidores_dns | tr '\n' ' ')
    linha "DNS" "${DNS:-nenhum}"
    DOM=$(dominio_ad)
    if no_dominio; then
        linha "Domínio" "ingressado em ${DOM:-SEDUC}"
    else
        linha "Domínio" "não ingressado"
    fi
    tabela_fim

    formulario_tarefa testar
    grupo "Testar a conexão"
    p "Testa um passo por vez: placa, endereço, roteador, DNS, internet, sites e o domínio SEDUC, e diz onde está o problema."
    marcar velocidade "Medir também a velocidade de download (baixa 25 MB)"
    marcar relatorio "Salvar o relatório na Área de Trabalho, para enviar ao suporte" 1
    fim_grupo
    botao "Testar a conexão"
    fim_formulario

    formulario_tarefa renovar
    grupo "Consertos rápidos"
    p "Renovar a conexão desliga e liga de novo a rede (cabo e Wi-Fi) e pede um novo endereço. A internet cai por alguns segundos."
    botao_secundario "Renovar a conexão"
    fim_grupo
    fim_formulario
    formulario limpardns
    secundario "Limpar o cache de DNS resolve sites que mudaram de endereço ou que só este computador não abre."
    botao_secundario "Limpar o cache de DNS"
    fim_formulario

    nome_computador
}

# Nome do computador: só o administrador troca; no domínio, não (a conta do AD ficaria
# com o nome antigo)
nome_computador() {
    formulario_tarefa renomear
    grupo "Nome do computador"
    if [ "${CENTRAL_ADMIN:-0}" != 1 ]; then
        p "Este computador se chama $(hostname). Só o administrador troca o nome."
    elif no_dominio; then
        p "Este computador se chama $(hostname) e está no domínio SEDUC: o nome não pode ser trocado, porque a conta do computador no AD ficaria com o nome antigo. Para trocar, saia do domínio (Active Directory SEDUC), troque aqui e ingresse de novo."
    else
        texto nome "Novo nome do computador" "$(hostname)"
        secundario "Letras sem acento, números e hífen. Padrão SEDUC: INEP-AMBIENTE-serial (ex.: 23012345-LMAT-1234) ou CR05-SETOR-serial. O sistema confere se outra máquina da rede já usa o nome e pede a senha do administrador."
        botao_secundario "Trocar o nome"
    fi
    fim_grupo
    fim_formulario
}

# Resultado de cada passo: tela (curto) e relatório
OKS=0; FALHAS=(); ALERTAS=(); DICAS=(); RELATORIO=""
anotar()  { echo "$1"; RELATORIO+="$1"$'\n'; }
ok_()     { OKS=$((OKS + 1)); anotar "OK      $*"; }
falha_()  { FALHAS+=("$1"); anotar "FALHA   $2"; }
alerta_() { ALERTAS+=("$1"); anotar "ALERTA  $2"; }
dica()    { DICAS+=("$*"); }

testar() {
    local DEV TIPO EST CON IP ATIVAS=0 GW R PERDA MEDIA DNS S RESP=() DOM SRV DC CODIGO T SITE NOME BPS

    mensagem "Placas de rede..."; progresso 5
    while IFS=: read -r DEV TIPO EST CON; do
        if [ "$EST" = connected ]; then
            ATIVAS=$((ATIVAS + 1))
            ok_ "Placa $DEV ($TIPO) conectada${CON:+ em $CON}"
        elif [ "$TIPO" = ethernet ] && [ "$EST" = unavailable ]; then
            anotar "        Placa $DEV: sem cabo"
        fi
    done < <(placas)
    if [ "$ATIVAS" -eq 0 ]; then
        falha_ "placa de rede" "Nenhuma placa de rede conectada"
        dica "Confira se o cabo de rede está bem encaixado no computador e no ponto da parede, ou conecte o Wi-Fi."
        # Sem placa, os outros testes só repetiriam a mesma falha
        concluir
        return 1
    fi

    mensagem "Endereço..."; progresso 15
    IP=""
    while IFS=: read -r DEV TIPO EST CON; do
        [ "$EST" = connected ] && IP=$(ipv4 "$DEV") && [ -n "$IP" ] && break
    done < <(placas)
    case "$IP" in
        "") [ "$ATIVAS" -gt 0 ] && { falha_ "endereço" "Sem endereço IP"; dica "O computador não recebeu endereço: clique em Renovar a conexão."; } ;;
        169.254.*) falha_ "endereço" "Endereço automático $IP (o DHCP não respondeu)"
                   dica "O roteador ou o servidor DHCP da escola não deu endereço: renove a conexão; se continuar, o problema é no switch ou no roteador." ;;
        *) ok_ "Endereço $IP" ;;
    esac

    mensagem "Roteador..."; progresso 25
    GW=$(roteador)
    if [ -z "$GW" ]; then
        falha_ "roteador" "Sem roteador (rota padrão)"
    else
        R=$(ping_resumo "$GW"); PERDA=${R%%|*}; MEDIA=${R#*|}
        if [ "${PERDA%.*}" -ge 100 ]; then
            falha_ "roteador" "Roteador $GW não responde"
            dica "O roteador da rede não responde: confira o cabo, o switch e se o roteador está ligado."
        elif [ "${PERDA%.*}" -gt 0 ]; then
            alerta_ "perda no roteador" "Roteador $GW: ${PERDA}% de perda, ${MEDIA:-?} ms"
            dica "Há perda de pacotes já dentro da rede da escola: cabo, switch ou Wi-Fi fraco."
        else
            ok_ "Roteador $GW responde (${MEDIA:-?} ms)"
        fi
    fi

    mensagem "DNS..."; progresso 40
    for DNS in $(servidores_dns); do
        if dig +short +time=2 +tries=1 "@$DNS" "$NOME_TESTE" A 2>/dev/null | grep -q '^[0-9]'; then
            ok_ "Servidor DNS $DNS responde"; RESP+=("$DNS")
        else
            anotar "        Servidor DNS $DNS não responde"
        fi
    done
    if getent hosts "$NOME_TESTE" >/dev/null; then
        [ ${#RESP[@]} -gt 0 ] || ok_ "DNS resolve $NOME_TESTE"
    elif dig +short +time=2 +tries=1 @1.1.1.1 "$NOME_TESTE" A 2>/dev/null | grep -q '^[0-9]'; then
        falha_ "DNS" "O DNS da rede não resolve nomes, mas o DNS público (1.1.1.1) sim"
        dica "O servidor DNS da rede está com problema: avise o suporte da CREDE/SEDUC. Até lá, os sites não abrem pelo nome."
    else
        falha_ "DNS" "Nenhum DNS resolve $NOME_TESTE"
    fi

    mensagem "Internet..."; progresso 55
    R=$(ping_resumo 1.1.1.1); PERDA=${R%%|*}; MEDIA=${R#*|}
    if [ "${PERDA%.*}" -ge 100 ]; then
        R=$(ping_resumo 8.8.8.8); PERDA=${R%%|*}; MEDIA=${R#*|}
    fi
    if [ "${PERDA%.*}" -ge 100 ]; then
        if [[ " ${FALHAS[*]} " != *" roteador "* ]]; then
            falha_ "internet" "A internet não responde (o roteador sim)"
            dica "A rede interna funciona, mas a internet da escola está fora: confira o link/modem da operadora."
        else
            falha_ "internet" "A internet não responde"
        fi
    elif [ "${PERDA%.*}" -gt 0 ]; then
        alerta_ "perda na internet" "Internet: ${PERDA}% de perda, ${MEDIA:-?} ms"
    elif [ "${MEDIA%%,*}" -gt 150 ] 2>/dev/null; then
        alerta_ "internet lenta" "Internet responde, mas com ${MEDIA} ms (lenta)"
    else
        ok_ "Internet responde (${MEDIA:-?} ms)"
    fi

    mensagem "Sites..."; progresso 65
    for S in "${SITES[@]}"; do
        SITE=${S%%|*}; NOME=${S#*|}
        CODIGO=$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' -m 15 "https://$SITE/" 2>/dev/null)
        case $? in
            0)  T=$(LC_ALL=C printf '%.1f' "${CODIGO#* }"); ok_ "$NOME abre (${T/./,} s)" ;;
            60) alerta_ "certificado" "$NOME responde, mas o certificado não foi validado"
                dica "A rede inspeciona o HTTPS (proxy): alguns sites e programas podem reclamar do certificado." ;;
            6)  falha_ "sites" "$NOME: nome não encontrado (DNS)" ;;
            28) falha_ "sites" "$NOME: tempo esgotado" ;;
            *)  falha_ "sites" "$NOME não abre" ;;
        esac
    done

    DOM=$(dominio_ad)
    if [ -n "$DOM" ] && no_dominio; then
        mensagem "Domínio SEDUC..."; progresso 78
        SRV=$(dig +short +time=2 +tries=1 "_ldap._tcp.$DOM" SRV 2>/dev/null | awk '{print $4}' | sed 's/\.$//' | head -1)
        if [ -z "$SRV" ]; then
            falha_ "domínio" "Servidores do domínio $DOM não encontrados no DNS"
            dica "Sem o DNS da SEDUC o login do AD e as pastas de rede não funcionam (fora da rede SEDUC isso é esperado)."
        elif timeout 3 bash -c "exec 3<>/dev/tcp/$SRV/389" 2>/dev/null; then
            ok_ "Servidor do domínio $SRV responde"
        else
            falha_ "domínio" "Servidor do domínio $SRV não responde"
        fi
        # --ping-dc confere a ligação do computador com o domínio sem precisar de root
        if wbinfo --ping-dc >/dev/null 2>&1; then ok_ "Computador ligado ao domínio (winbind)"
        else
            falha_ "ingresso" "O computador não conseguiu falar com o domínio (winbind)"
            dica "O login do AD pode falhar: confira a rede SEDUC; se continuar, ingresse de novo pelo Active Directory SEDUC."
        fi
    fi

    if [ "$(campo velocidade)" = 1 ]; then
        mensagem "Medindo a velocidade (25 MB)..."; progresso 85
        BPS=$(curl -sS -o /dev/null -w '%{speed_download}' -m 60 "$VELOCIDADE_URL" 2>/dev/null)
        if [ -n "$BPS" ] && [ "${BPS%.*}" -gt 0 ]; then
            ok_ "Velocidade de download: $(awk -v b="$BPS" 'BEGIN {printf "%.1f", b * 8 / 1000000}') Mb/s"
        else
            alerta_ "velocidade" "Não foi possível medir a velocidade"
        fi
    fi

    concluir
    [ ${#FALHAS[@]} -eq 0 ]
}

# Resumo, o que fazer, relatório na Área de Trabalho e aviso do fim
concluir() {
    local RESUMO ARQ DESK U=() F
    progresso 95
    # Cada problema uma vez só (vários sites contam como "sites")
    for F in "${FALHAS[@]}"; do [[ " ${U[*]} " == *" $F "* ]] || U+=("$F"); done
    FALHAS=("${U[@]}")
    if [ ${#FALHAS[@]} -eq 0 ] && [ ${#ALERTAS[@]} -eq 0 ]; then
        RESUMO="Rede ok: $OKS testes passaram."
    elif [ ${#FALHAS[@]} -eq 0 ]; then
        RESUMO="Rede funcionando, com alerta: $(IFS=,; echo "${ALERTAS[*]}" | sed 's/,/, /g')."
    else
        RESUMO="Problema em: $(IFS=,; echo "${FALHAS[*]}" | sed 's/,/, /g')."
    fi
    if [ ${#DICAS[@]} -gt 0 ]; then
        anotar ""
        anotar "O que fazer:"
        local D
        for D in "${DICAS[@]}"; do anotar "  - $D"; done
        RESUMO+=" ${DICAS[0]}"
    fi

    if [ "$(campo relatorio)" = 1 ]; then
        DESK=$(xdg-user-dir DESKTOP 2>/dev/null); [ -d "$DESK" ] || DESK="$HOME"
        ARQ="$DESK/diagnostico-rede-$(hostname)-$(date +%Y%m%d-%H%M).txt"
        {
            echo "Diagnóstico da rede - $(hostname) - $(date '+%d/%m/%Y %H:%M')"
            echo "Sistema SEDUC $(cat /usr/local/seduc/version 2>/dev/null)"
            echo; echo "$RESUMO"; echo; printf '%s' "$RELATORIO"
            echo; echo "== Placas";   nmcli -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null
            echo; echo "== Endereços"; ip -br addr 2>/dev/null | grep -v '^lo '
            echo; echo "== Rotas";     ip route 2>/dev/null
            echo; echo "== DNS";       resolvectl status 2>/dev/null | grep -E 'Link|DNS Servers|Current DNS|DNS Domain'
        } > "$ARQ" 2>/dev/null && anotar "" && anotar "Relatório salvo em $ARQ"
    fi

    progresso 100
    aviso_fim "$RESUMO"
}

renovar() {
    local DEV TIPO EST CON N=0
    while IFS=: read -r DEV TIPO EST CON; do
        [ "$EST" = connected ] && [ -n "$CON" ] || continue
        mensagem "Reconectando $CON..."
        if nmcli connection up id "$CON" ifname "$DEV" >/dev/null 2>&1; then
            echo "$CON ($DEV): reconectada, endereço $(ipv4 "$DEV")"; N=$((N + 1))
        else
            echo "$CON ($DEV): não foi possível reconectar"
        fi
    done < <(placas)
    if [ "$N" -gt 0 ]; then
        aviso_fim "Conexão renovada. Teste de novo para ver se resolveu."
    else
        aviso_fim "Nenhuma conexão ativa para renovar. Confira o cabo ou conecte o Wi-Fi."
        return 1
    fi
}

nome_valido() {
    local LC_ALL=C   # sem isso, [A-Za-z] aceita letra acentuada no português
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

renomear() {
    local NOVO CODIGO
    NOVO=$(campo nome | tr -d '[:space:]')
    if no_dominio; then
        aviso_fim "O computador está no domínio SEDUC: o nome não pode ser trocado. Saia do domínio, troque o nome e ingresse de novo."
        return 4
    fi
    if ! nome_valido "$NOVO"; then
        aviso_fim "Nome inválido: use letras sem acento, números e hífen (sem hífen no começo ou no fim), até 63."
        return 1
    fi
    if [ "${NOVO,,}" = "$(hostname | tr '[:upper:]' '[:lower:]')" ]; then
        aviso_fim "O computador já se chama $NOVO."
        return 0
    fi
    mensagem "Trocando o nome para $NOVO... o sistema vai pedir a senha do administrador."
    pkexec "${CENTRAL_SCRIPTS:-/usr/local/seduc/scripts}/renomear_computador.sh" "$NOVO"
    CODIGO=$?
    case $CODIGO in
        0)       aviso_fim "Nome do computador trocado para $NOVO. Reinicie o computador para todos os programas usarem o nome novo." ;;
        2)       aviso_fim "Nome inválido." ;;
        3)       aviso_fim "Outra máquina da rede já usa o nome $NOVO. Escolha outro." ;;
        4)       aviso_fim "O computador está no domínio: saia do domínio, troque o nome e ingresse de novo." ;;
        126|127) aviso_fim "A senha do administrador não foi confirmada. O nome não mudou." ;;
        *)       aviso_fim "Não foi possível trocar o nome. Detalhes em /usr/local/seduc/logs/renomear_computador.log." ;;
    esac
    return "$CODIGO"
}

limpardns() {
    if resolvectl flush-caches 2>/dev/null; then
        ok "Cache de DNS limpo. Tente abrir o site de novo."
    else
        erro "Não foi possível limpar o cache de DNS."
    fi
    pagina
}

##########
## MAIN ##
##########
case "${1:-pagina}" in
    pagina)    pagina ;;
    testar)    testar ;;
    renovar)   renovar ;;
    limpardns) limpardns ;;
    renomear)  renomear ;;
    *) erro "Ação desconhecida."; exit 1 ;;
esac
