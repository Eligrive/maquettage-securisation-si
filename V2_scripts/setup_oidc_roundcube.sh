#!/bin/bash

#Script client oidc Roundcube
echo "🔄 Bascule de Roundcube vers le SSO Keycloak..."

ROUNDCUBE_CONFIG="/var/www/html/roundcube/config/config.inc.php"
ROUNDCUBE_SECRET="Secret_Roundcube_OIDC_2024_Ultra_Securise"
KEYCLOAK_URL="https://sso.unicampus.fr/realms/master"

# 1. Activation du plugin OIDC
echo "⚙️ Activation du plugin oidc_login..."
sed -i "s/\$config\['plugins'\] = array(/\$config\['plugins'\] = array('oidc_login', /g" $ROUNDCUBE_CONFIG

# 2. Injection des paramètres d'authentification
echo "🔑 Configuration des clés Keycloak..."
cat << EOF >> $ROUNDCUBE_CONFIG

// Configuration SSO Keycloak (Injectée automatiquement)
\$config['oidc_login_client_id'] = 'roundcube-client';
\$config['oidc_login_client_secret'] = '$ROUNDCUBE_SECRET';
\$config['oidc_login_provider'] = '$KEYCLOAK_URL';
\$config['oidc_login_scopes'] = 'openid email profile';
\$config['oidc_login_redirect_uri'] = 'https://mail.unicampus.fr/index.php/login/oauth';
EOF

echo "✅ Le Webmail Roundcube est maintenant protégé par Keycloak !"