#!/bin/bash

#Script création des différents clients 

echo "🚀 Début de la configuration automatisée des Clients OIDC dans Keycloak..."

KC_DIR="/opt/keycloak"
KC_USER="admin"
KC_PASS="Mon_mot_de_passe"

# Mots de passe partagés (Secrets OIDC)
TELEPORT_SECRET="Secret_Teleport_OIDC_2024_Ultra_Securise" 
MOODLE_SECRET="Secret_Moodle_OIDC_2024_Ultra_Securise"

# 1. Authentification CLI
echo "🔑 Connexion à l'API d'administration Keycloak..."
sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user $KC_USER --password $KC_PASS

# ==========================================
# 2. CLIENT BASTION (TELEPORT)
# ==========================================
echo "📝 Création du client 'teleport-bastion'..."
sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh create clients -r master \
  -s clientId="teleport-bastion" \
  -s enabled=true \
  -s publicClient=false \
  -s secret="$TELEPORT_SECRET" \
  -s 'redirectUris=["https://bastion.unicampus.fr/v1/webapi/oidc/callback"]' \
  -s 'standardFlowEnabled=true' \
  -s 'directAccessGrantsEnabled=true'

# Ajout du Mapper de Rôles pour Teleport
CLIENT_ID_TELEPORT=$(sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r master -q clientId=teleport-bastion --fields id --format csv | tr -d '"')

sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh create clients/$CLIENT_ID_TELEPORT/protocol-mappers/models -r master \
  -s name="roles-mapper" \
  -s protocol="openid-connect" \
  -s protocolMapper="oidc-usermodel-realm-role-mapper" \
  -s 'config."claim.name"="roles"' \
  -s 'config."jsonType.label"="String"' \
  -s 'config."id.token.claim"="true"' \
  -s 'config."access.token.claim"="true"' \
  -s 'config."multivalued"="true"'

# ==========================================
# 3. CLIENT PLATEFORME PÉDAGOGIQUE (MOODLE)
# ==========================================
echo "📝 Création du client 'moodle-client'..."
sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh create clients -r master \
  -s clientId="moodle-client" \
  -s enabled=true \
  -s publicClient=false \
  -s secret="$MOODLE_SECRET" \
  -s 'redirectUris=["https://moodle.unicampus.fr/auth/oidc/"]' \
  -s 'standardFlowEnabled=true'

echo "✅ Tous les clients Keycloak sont configurés avec succès !"