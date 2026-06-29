#!/bin/bash

# ==============================================================================
# Script de déploiement : Plugin OIDC pour Roundcube Webmail (Zone DMZ)
# ==============================================================================

ROUNDCUBE_DIR="/var/www/html/roundcube"
ROUNDCUBE_CONFIG="$ROUNDCUBE_DIR/config/config.inc.php"
ROUNDCUBE_SECRET="Secret_Roundcube_OIDC_2024_Ultra_Securise"
KEYCLOAK_URL="https://sso.unicampus.fr/realms/master"

echo "📦 Téléchargement du module oidc_login pour Roundcube..."
sudo apt-get update && sudo apt-get install -y git

# 1. Récupération des sources du plugin standard
sudo rm -rf $ROUNDCUBE_DIR/plugins/oidc_login
sudo git clone https://github.com/mstahv/roundcube-oidc-login.git $ROUNDCUBE_DIR/plugins/oidc_login --depth 1

# 2. Sécurisation des permissions des fichiers
sudo chown -R www-data:www-data $ROUNDCUBE_DIR/plugins/oidc_login

echo "⚙️ Enregistrement du plugin dans la configuration de Roundcube..."
# Injection du plugin dans la liste des modules actifs du fichier config.inc.php
if ! grep -q "'oidc_login'" $ROUNDCUBE_CONFIG; then
    sudo sed -i "s/\$config\['plugins'\] = array(/\$config\['plugins'\] = array('oidc_login', /g" $ROUNDCUBE_CONFIG
fi

echo "📝 Injection des directives de sécurité Keycloak..."
# Utilisation de la variable d'échappement \$ pour écrire correctement le PHP via Bash
cat << EOF | sudo tee -a $ROUNDCUBE_CONFIG

// --- Bloc de Configuration OIDC Keycloak (V2) ---
\$config['oidc_login_client_id'] = 'roundcube-client';
\$config['oidc_login_client_secret'] = '$ROUNDCUBE_SECRET';
\$config['oidc_login_provider'] = '$KEYCLOAK_URL';
\$config['oidc_login_scopes'] = array('openid', 'email', 'profile');
\$config['oidc_login_redirect_uri'] = 'https://mail.unicampus.fr/index.php/login/oauth';
\$config['oidc_login_logout_redirect_uri'] = 'https://mail.unicampus.fr/';
\$config['oidc_login_auto_login'] = false; 
EOF

echo "✅ Le Webmail Roundcube est désormais prêt pour les connexions SSO."