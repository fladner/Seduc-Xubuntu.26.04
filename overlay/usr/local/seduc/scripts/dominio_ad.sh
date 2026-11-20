#!/usr/bin/env bash

# Diz se o computador está no domínio SEDUC (AD). Uso, depois de carregar:
#   . /usr/local/seduc/scripts/dominio_ad.sh
#   if computador_no_dominio; then ...
#
# O ingresso (ingressar_ad.sh) grava "security = ads" no smb.conf e liga o winbind no
# passwd do nsswitch.conf; a saída do domínio desliga o winbind no nsswitch, mas o
# smb.conf continua com "ads". Por isso valem os dois juntos. O "wbinfo --own-domain"
# não serve: com o winbind rodando, responde o workgroup mesmo fora do domínio.
# Não precisa de root nem de rede (o computador no domínio e sem rede continua no domínio).

SCRIPT_VERSION="1.6-3"

computador_no_dominio() {
    local SMB="${DOMINIO_SMB_CONF:-/etc/samba/smb.conf}" NSS="${DOMINIO_NSSWITCH:-/etc/nsswitch.conf}"
    grep -qiE '^[[:space:]]*security[[:space:]]*=[[:space:]]*ads[[:space:]]*([;#].*)?$' "$SMB" 2>/dev/null &&
        grep -qE '^passwd:.*[[:space:]]winbind([[:space:]]|$)' "$NSS" 2>/dev/null
}

# Executado direto: sai 0 no domínio, 1 fora (ex.: dominio_ad.sh && echo no domínio)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    computador_no_dominio
fi
