#!/bin/bash

#Script de création client Teleport 

echo "🚀 Début de la configuration automatisée du Client Teleport dans Keycloak..."

KC_DIR="/opt/keycloak"
KC_USER="admin"
KC_PASS="Mon_mot_de_passe"
# On fige le secret pour que le Bastion puisse l'utiliser facilement
TELEPORT_SECRET="Secret_Teleport_OIDC_2024_Ultra_Securise" 

# 1. Authentification CLI
echo "🔑 Connexion à l'API d'administration Keycloak..."
sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user $KC_USER --password $KC_PASS

# 2. Création du client OIDC pour le Bastion
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

# 3. Ajout du Mapper pour injecter les rôles dans le jeton SSO
# C'est vital pour que Teleport sache si l'utilisateur est un Admin_DSI ou un Chercheur
echo "⚙️ Configuration du Mapper de Rôles..."
CLIENT_ID=$(sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r master -q clientId=teleport-bastion --fields id --format csv | tr -d '"')

sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh create clients/$CLIENT_ID/protocol-mappers/models -r master \
  -s name="roles-mapper" \
  -s protocol="openid-connect" \
  -s protocolMapper="oidc-usermodel-realm-role-mapper" \
  -s 'config."claim.name"="roles"' \
  -s 'config."jsonType.label"="String"' \
  -s 'config."id.token.claim"="true"' \
  -s 'config."access.token.claim"="true"' \
  -s 'config."multivalued"="true"'

echo "✅ Client Keycloak configuré avec succès ! Le secret partagé est en place."