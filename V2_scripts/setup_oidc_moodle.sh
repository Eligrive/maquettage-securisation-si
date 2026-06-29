#!/bin/bash

#Script de setup du oidc côté Moodle 

echo "🔄 Bascule de Moodle vers le SSO Keycloak..."

MOODLE_DIR="/var/www/html/moodle"
MOODLE_SECRET="Secret_Moodle_OIDC_2024_Ultra_Securise"
KEYCLOAK_URL="https://sso.unicampus.fr/realms/master"

# 1. Activation du plugin OIDC dans Moodle
echo "⚙️ Activation du plugin d'authentification OIDC..."
# (On suppose ici que tu as téléchargé le dossier du plugin dans /auth/oidc au préalable)
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --name=auth --set="oidc,manual"

# 2. Injection des paramètres Keycloak dans la configuration du plugin
echo "🔑 Injection des identifiants OIDC..."
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --component=auth_oidc --name=clientid --set="moodle-client"
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --component=auth_oidc --name=clientsecret --set="$MOODLE_SECRET"
sudo -u www-data php $MOODLE_DIR/admin/cli/cfg.php --component=auth_oidc --name=opurl --set="$KEYCLOAK_URL"

# 3. La Réconciliation des données (La véritable "Migration")
echo "🔒 Migration des comptes locaux (V1) vers le SSO (V2)..."
# On passe tous les utilisateurs de la méthode 'manual' à la méthode 'oidc', sauf l'admin de secours
mysql -u root moodle -e "UPDATE mdl_user SET auth = 'oidc' WHERE auth = 'manual' AND username != 'admin';"

echo "✅ Moodle est maintenant protégé par Keycloak !"