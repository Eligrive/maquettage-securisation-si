#!/bin/bash
# script_ca_intermediate.sh
set -e

# 1. Génération de la clé privée de l'AC Intermédiaire
openssl genrsa -out intermediateCA.key 4096

# 2. Génération de la CSR pour l'AC Intermédiaire
openssl req -new -key intermediateCA.key \
  -out intermediateCA.csr \
  -subj "/C=FR/ST=Ile-de-France/L=Paris/O=UniCampus/OU=DSI-Securite/CN=UniCampus Intermediate CA"

echo "[INFO] Transférez intermediateCA.csr sur la machine Root CA pour signature."