#!/bin/bash

# ==============================================================================
# Script de déploiement : Plugin OIDC pour Moodle (Zone DMZ)
# ==============================================================================

MOODLE_DIR="/var/www/html/moodle"
MOODLE_SECRET="Secret_Moodle_OIDC_2024_Ultra_Securise"
KEYCLOAK_URL="https://sso.unicampus.fr/realms/master"
MYSQL_MOODLE_PASS="MoodlePasswordV1" # À adapter avec ton vrai mot de passe de BDD

echo "📦 Installation des dépendances et téléchargement du plugin auth_oidc..."
sudo apt-get update && sudo apt-get install -y git

# 1. Récupération propre du plugin dans le répertoire d'authentification de Moodle
sudo rm -rf $MOODLE_DIR/auth/oidc
sudo git clone https://github.com/microsoft/moodle-auth_oidc.git $MOODLE_DIR/auth/oidc --depth 1

# 2. Attribution des droits au serveur Web Apache
sudo chown -R www-data:www-data $MOODLE_DIR/auth/oidc

echo "⚙️ Déclenchement de la mise à jour de la base de données Moodle..."
# Cette commande CLI force Moodle à intégrer le plugin sans passer par l'interface web
sudo -u www-data php $MOODLE_DIR/admin/cli/upgrade.php --non-interactive

echo "🔑 Configuration des clés secrètes du SSO Keycloak..."
# Activation officielle de la méthode d'authentification OIDC
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --name=auth --set="oidc,manual"

# Injection des paramètres de liaison issus de Keycloak
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --component=auth_oidc --name=clientid --set="moodle-client"
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --component=auth_oidc --name=clientsecret --set="$MOODLE_SECRET"
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --component=auth_oidc --name=opurl --set="$KEYCLOAK_URL"

echo "🔒 Migration de la table utilisateur (Bascule V1 -> V2)..."
# Tous les utilisateurs basculent sur le SSO, sauf le compte de secours 'admin'
mysql -u moodle -p"$MYSQL_MOODLE_PASS" moodle -e "UPDATE mdl_user SET auth = 'oidc' WHERE auth = 'manual' AND username != 'admin';" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Moodle est parfaitement connecté au SSO et les comptes sont migrés."
else
    echo "⚠️ Le plugin est installé, mais la mise à jour SQL a échoué. Vérifie le mot de passe MySQL."
fi