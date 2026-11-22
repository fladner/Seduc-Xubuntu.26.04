#!/usr/bin/env bash

# Atualização dos pacotes do sistema (apt), no lugar do unattended-upgrades.
#   atualizar_pacotes.sh --auto   pelo seduc-atualizar.timer (após ligar e a cada 12 h)
#   atualizar_pacotes.sh          pelo "Atualizar o sistema" (atualizar_sistema_root.sh)
#
# O que o unattended-upgrades não fazia:
# - instala tudo (full-upgrade de todos os repositórios, como o build.sh) mantendo as
#   configurações da SEDUC (confold): os pacotes com configuração alterada atualizam;
# - um download barrado (proxy da SEDUC, repositório fora) não cancela o resto: o
#   pacote fica para depois e os outros são instalados;
# - conclui instalações interrompidas antes de começar;
# - no --auto, depois de uma atualização completa espera 3 dias; se faltou algo (rede,
#   proxy), tenta de novo depois de 1 dia; interrompida pelo desligamento, no próximo
#   boot. Fora desses horários o timer só lê o status, sem usar a rede;
# - grava o resultado em $STATUS, que a Central do Suporte mostra.
# Desligar o computador no meio: o download para; a instalação termina antes.
#
# Saída: 0 tudo atualizado (ou nada a fazer), 2 atualização parcial ou com erro.

set -uo pipefail

SCRIPT_VERSION="1.7-0"

#####################
## VARIABLE GLOBAL ##
#####################
STATUS="${SEDUC_ATUALIZAR_STATUS:-/var/lib/seduc-atualizar/status}"
TRAVA="${SEDUC_ATUALIZAR_TRAVA:-/run/lock/seduc-atualizar.lock}"
CACHE="${SEDUC_ATUALIZAR_CACHE:-/var/cache/apt/archives}"
LOG="${SEDUC_ATUALIZAR_LOG:-/usr/local/seduc/logs/atualizacao_automatica.log}"
INTERVALO_OK=$((3 * 86400))   # --auto: espera depois de uma atualização completa
INTERVALO_FALHA=86400         # --auto: espera depois de uma atualização incompleta
RODADAS=3                     # tentativas de download, separando os pacotes barrados
APT=(apt-get -y -o DPkg::Lock::Timeout=1800
     -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

AUTO=0
[ "${1:-}" = "--auto" ] && AUTO=1

# Pacotes travados por este script (apt-mark hold) só durante a execução
TRAVADOS=()
FILHO=""
INTERROMPIVEL=0
PARAR=0
INTERROMPIDA=0

###############
## FUNCTIONS ##
###############
etapa() {
    echo
    echo "==> $*"
}

aviso() { echo "AVISO: $*"; }

# rodar <interrompível 0|1> comando...: no desligamento (SIGTERM), o download é
# cancelado; a instalação (dpkg) continua até o fim
rodar() {
    INTERROMPIVEL="$1"
    shift
    "$@" &
    FILHO=$!
    local RC
    while :; do
        wait "$FILHO"
        RC=$?
        kill -0 "$FILHO" 2>/dev/null || break
    done
    FILHO=""
    return "$RC"
}

ao_parar() {
    PARAR=1
    echo "Desligamento pedido: a atualização para depois da etapa atual."
    if [ -n "$FILHO" ] && [ "$INTERROMPIVEL" = 1 ]; then
        kill "$FILHO" 2>/dev/null || true
    fi
}

destravar() {
    if [ "${#TRAVADOS[@]}" -gt 0 ]; then
        apt-mark unhold "${TRAVADOS[@]}" >/dev/null 2>&1 || true
        TRAVADOS=()
    fi
}

ler_status() { sed -n "s/^$1=//p" "$STATUS" 2>/dev/null | head -1; }

# gravar_status <resultado> <mensagem>
gravar_status() {
    local RESULTADO="$1" MENSAGEM="$2" AGORA ULTIMO_OK ULTIMO_OK_DATA REINICIAR=0
    AGORA=$(date +%s)
    ULTIMO_OK=$(ler_status ULTIMO_OK)
    ULTIMO_OK_DATA=$(ler_status ULTIMO_OK_DATA)
    if [ "$RESULTADO" = ok ]; then
        ULTIMO_OK="$AGORA"
        ULTIMO_OK_DATA=$(date '+%d/%m/%Y %H:%M')
    fi
    [ -f /var/run/reboot-required ] && REINICIAR=1
    mkdir -p "$(dirname "$STATUS")"
    {
        echo "VERSAO=$SCRIPT_VERSION"
        echo "DATA=$AGORA"
        echo "DATA_TEXTO=$(date '+%d/%m/%Y %H:%M')"
        echo "ORIGEM=$([ "$AUTO" = 1 ] && echo automatica || echo manual)"
        echo "RESULTADO=$RESULTADO"
        echo "MENSAGEM=${MENSAGEM//$'\n'/ }"
        echo "INSTALADOS=${INSTALADOS:-0}"
        echo "PENDENTES=${PENDENTES:-0}"
        echo "BLOQUEADOS=${BLOQUEADOS[*]:-}"
        echo "REINICIAR=$REINICIAR"
        echo "INTERROMPIDA=$INTERROMPIDA"
        echo "ULTIMO_OK=$ULTIMO_OK"
        echo "ULTIMO_OK_DATA=$ULTIMO_OK_DATA"
    } > "$STATUS.tmp" && mv -f "$STATUS.tmp" "$STATUS"
    chmod 644 "$STATUS" 2>/dev/null || true
}

# Quantos pacotes o full-upgrade instalaria ou atualizaria agora
contar_pendentes() {
    "${APT[@]}" -s full-upgrade 2>/dev/null | grep -c '^Inst ' || true
}

# Arquivos .deb que o full-upgrade precisa e não estão no cache: "pacote arquivo"
faltando_no_cache() {
    local URL ARQ RESTO
    while read -r URL ARQ RESTO; do
        [ -n "$ARQ" ] || continue
        [ -f "$CACHE/$ARQ" ] && continue
        echo "${ARQ%%_*} $ARQ"
    done < <("${APT[@]}" -qq --print-uris full-upgrade 2>/dev/null | tr -d "'")
}

# Baixa tudo; o que não baixar (proxy, repositório fora) fica travado nesta execução
baixar() {
    local RODADA PKG ARQ FALTA
    for (( RODADA = 1; RODADA <= RODADAS; RODADA++ )); do
        (( PARAR )) && return 1
        rodar 1 "${APT[@]}" --download-only full-upgrade && return 0
        (( PARAR )) && return 1
        FALTA=$(faltando_no_cache)
        [ -n "$FALTA" ] || return 0
        while read -r PKG ARQ; do
            [ -n "$PKG" ] || continue
            aviso "não foi possível baixar $ARQ: $PKG fica para a próxima vez"
            BLOQUEADOS+=("$PKG")
            if ! apt-mark showhold 2>/dev/null | grep -qx "$PKG"; then
                apt-mark hold "$PKG" >/dev/null 2>&1 && TRAVADOS+=("$PKG")
            fi
        done <<< "$FALTA"
    done
    return 1
}

# O seduc_setup.service (boot) também usa o apt: espera ele terminar
esperar_setup() {
    local N=0
    while [ "$(systemctl is-active seduc_setup.service 2>/dev/null)" = "activating" ]; do
        (( N == 0 )) && echo "A atualização SEDUC do boot está rodando, aguardando..."
        sleep 10
        N=$((N + 1))
        (( N >= 180 )) && return 1
        (( PARAR )) && return 1
    done
    return 0
}

##########
## MAIN ##
##########
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

if grep -q casper /proc/cmdline 2>/dev/null; then
    echo "No modo live (pendrive) o sistema não é atualizado."
    exit 0
fi

trap ao_parar TERM INT
trap destravar EXIT

# Uma execução por vez (automática e "Atualizar o sistema")
mkdir -p "$(dirname "$TRAVA")"
exec 9> "$TRAVA"
if ! flock -n 9; then
    if (( AUTO )); then
        echo "Outra atualização já está rodando."
        exit 0
    fi
    echo "A atualização automática está rodando; aguardando ela terminar..."
    flock 9
fi

if (( AUTO )); then
    AGORA=$(date +%s)
    ULTIMO_OK=$(ler_status ULTIMO_OK)
    ULTIMA=$(ler_status DATA)
    if [ "$(ler_status RESULTADO)" = ok ]; then
        if [[ "$ULTIMO_OK" =~ ^[0-9]+$ ]] && (( AGORA - ULTIMO_OK < INTERVALO_OK )); then
            echo "Sistema atualizado em $(ler_status ULTIMO_OK_DATA): próxima verificação em 3 dias."
            exit 0
        fi
    elif [ "$(ler_status INTERROMPIDA)" != 1 ] && [[ "$ULTIMA" =~ ^[0-9]+$ ]] &&
        (( AGORA - ULTIMA < INTERVALO_FALHA )); then
        echo "Última tentativa em $(ler_status DATA_TEXTO) incompleta: tenta de novo 1 dia depois."
        exit 0
    fi
    # Notebook na bateria: espera a tomada
    if command -v systemd-ac-power >/dev/null && ! systemd-ac-power; then
        echo "Computador na bateria: a atualização fica para quando estiver na tomada."
        exit 0
    fi
    # "Atualizar o sistema" tem o próprio log; o automático fica aqui (Coletar logs)
    mkdir -p "$(dirname "$LOG")"
    [ -f "$LOG" ] && mv -f "$LOG" "$LOG.old"
    exec > >(tee -a "$LOG") 2>&1
fi

echo "===== Atualização dos pacotes $(date '+%F %T') - versão $SCRIPT_VERSION ====="
BLOQUEADOS=()
INSTALADOS=0
PENDENTES=0
FALHAS=0

esperar_setup || aviso "a atualização SEDUC do boot não terminou; continuando"

etapa "Concluindo instalações interrompidas"
rodar 0 dpkg --configure -a || FALHAS=$((FALHAS + 1))
rodar 0 "${APT[@]}" -f install || FALHAS=$((FALHAS + 1))

etapa "Buscando atualizações"
ATUALIZOU_LISTA=0
for T in 1 2 3; do
    (( PARAR )) && break
    if rodar 1 "${APT[@]}" update; then
        ATUALIZOU_LISTA=1
        break
    fi
    (( T < 3 )) && { echo "Tentando de novo em 1 minuto..."; sleep 60; }
done
if (( ! ATUALIZOU_LISTA )); then
    # Com a lista antiga ainda dá para instalar o que já se sabia
    aviso "não foi possível atualizar a lista de pacotes (rede ou proxy)"
    FALHAS=$((FALHAS + 1))
fi

if (( PARAR )); then
    PENDENTES=$(contar_pendentes)
    INTERROMPIDA=1
    gravar_status erro "Interrompida pelo desligamento"
    exit 2
fi

ANTES=$(contar_pendentes)
echo "$ANTES pacote(s) para atualizar."

if (( ANTES > 0 )); then
    etapa "Baixando atualizações"
    if ! baixar; then
        (( PARAR )) || aviso "nem todos os pacotes foram baixados"
        FALHAS=$((FALHAS + 1))
    fi

    if (( ! PARAR )); then
        etapa "Instalando atualizações"
        rodar 0 "${APT[@]}" full-upgrade || FALHAS=$((FALHAS + 1))
    fi
    if (( ! PARAR )); then
        etapa "Removendo pacotes que não são mais usados"
        rodar 0 "${APT[@]}" autoremove --purge || FALHAS=$((FALHAS + 1))
    fi
fi
(( PARAR )) || rodar 0 "${APT[@]}" autoclean >/dev/null 2>&1 || true

destravar
PENDENTES=$(contar_pendentes)
INSTALADOS=$(( ANTES > PENDENTES ? ANTES - PENDENTES : 0 ))
echo
echo "Instalados: $INSTALADOS; pendentes: $PENDENTES${BLOQUEADOS[*]:+; não baixados: ${BLOQUEADOS[*]}}"

if (( PARAR )) && (( PENDENTES > 0 )); then
    INTERROMPIDA=1
    gravar_status erro "Interrompida pelo desligamento"
    exit 2
elif (( ! ATUALIZOU_LISTA )); then
    gravar_status sem-rede "Sem acesso aos repositórios (rede ou proxy)"
    exit 2
elif (( PENDENTES > 0 )); then
    gravar_status parcial "$PENDENTES pacote(s) ficaram para a próxima vez"
    exit 2
elif (( FALHAS )); then
    gravar_status erro "Atualização com erros: veja o log"
    exit 2
fi
gravar_status ok "Todos os pacotes atualizados"
[ -f /var/run/reboot-required ] && echo "Reinicie o computador para concluir a atualização."
echo "===== Sistema atualizado ====="
exit 0
