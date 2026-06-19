#!/bin/bash

# ==============================================================================
# Script de configuration automatisée : Lien Keycloak <-> LDAP
# ==============================================================================

# 1. Variables Keycloak (Celles de ton docker-compose)
KC_DIR="/opt/keycloak"
KC_USER="admin"
KC_PASS="Mon_mot_de_passe"

# 2. Variables LDAP (Issues de network.md et srv-ldap.sh)
LDAP_URL="ldap://192.168.104.1:389"
LDAP_BIND_DN="cn=admin,dc=unicampus,dc=local"     
LDAP_BIND_PASS="unicampus2024"                    
LDAP_USERS_DN="ou=people,dc=unicampus,dc=local"   

echo "Attente du démarrage complet de Keycloak (cela peut prendre 30 à 60s)..."
# On interroge l'URL de santé de Keycloak jusqu'à ce qu'il réponde "200 OK"
while ! curl -s -f http://localhost:8080/health/ready > /dev/null; do
    echo "Keycloak n'est pas encore prêt, on patiente 5 secondes..."
    sleep 5
done
echo "Keycloak est en ligne !"

# 3. Authentification CLI
echo "🔑 Connexion à l'API d'administration Keycloak..."
sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user $KC_USER --password $KC_PASS

# 4. Création du connecteur LDAP
echo "Création et configuration de la liaison LDAP..."
sudo docker compose -f $KC_DIR/docker-compose.yml exec -T keycloak \
  /opt/keycloak/bin/kcadm.sh create components -r master \
  -s name="LDAP-UniCampus" \
  -s providerId=ldap \
  -s providerType=org.keycloak.storage.UserStorageProvider \
  -s 'config.vendor=["other"]' \
  -s "config.connectionUrl=[\"$LDAP_URL\"]" \
  -s "config.bindDn=[\"$LDAP_BIND_DN\"]" \
  -s "config.bindCredential=[\"$LDAP_BIND_PASS\"]" \
  -s "config.usersDn=[\"$LDAP_USERS_DN\"]" \
  -s 'config.editMode=["READ_ONLY"]' \
  -s 'config.usernameLDAPAttribute=["uid"]' \
  -s 'config.rdnLDAPAttribute=["uid"]' \
  -s 'config.uuidPropertyName=["entryUUID"]' \
  -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]' \
  -s 'config.searchScope=["1"]' \
  -s 'config.trustEmail=["true"]'

echo "Opération terminée ! Les utilisateurs (Lea Martin, Jean Dupont, etc.) sont maintenant synchronisés avec Keycloak."