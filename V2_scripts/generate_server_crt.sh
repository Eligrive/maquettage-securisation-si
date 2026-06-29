#!/bin/bash
# generate_server_cert.sh
set -e

SERVICE_NAME=$1 # ex: moodle
FQDN=$2         # ex: moodle.unicampus.fr

if [ -z "$SERVICE_NAME" ] || [ -z "$FQDN" ]; then
    echo "Usage: $0 <service_name> <fqdn>"
    exit 1
fi

# 1. Clé privée du serveur
openssl genrsa -out ${SERVICE_NAME}.key 2048

# 2. CSR du serveur
openssl req -new -key ${SERVICE_NAME}.key \
  -out ${SERVICE_NAME}.csr \
  -subj "/C=FR/ST=Ile-de-France/L=Paris/O=UniCampus/OU=Services/CN=${FQDN}"

# 3. Signature par l'AC Intermédiaire (Valide 2 ans)
openssl x509 -req -days 730 -sha256 \
  -in ${SERVICE_NAME}.csr \
  -CA intermediateCA.crt -CAkey intermediateCA.key -CAcreateserial \
  -out ${SERVICE_NAME}.crt \
  -extfile <(echo "[v3_req]"; echo "basicConstraints=CA:FALSE"; echo "keyUsage=critical,digitalSignature,keyEncipherment"; echo "subjectAltName=DNS:${FQDN}")

# 4. CRUCIAL : Création de la Fullchain (Certificat Serveur + AC Intermédiaire)
cat ${SERVICE_NAME}.crt intermediateCA.crt > ${SERVICE_NAME}.fullchain.crt

echo "[OK] Certificats générés pour ${SERVICE_NAME} (${FQDN})"