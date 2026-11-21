#!/bin/bash
# Assinador Logus
# SEDUC: o mesmo lançador da Logus, com o driver PKCS#11 do token mToken CryptoID
# (PKCS11_DRIVER) para o assinador enxergar o certificado. Só para quem usa o CryptoID:
# o instalar_tokens.sh e o seduc_setup.sh copiam este arquivo para
# /opt/AssinadorLogus/AssinadorLogus.sh quando o driver do CryptoID está instalado;
# sem ele, fica o lançador original da Logus.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
PKCS11_DRIVER=/opt/CryptoIDEAdmin/x64/lib/linux/x64/libcryptoide_pkcs11.so ./jre/bin/java -Dlogus.signer.path="$(pwd)" -jar bin/AssinadorLogus.jar
