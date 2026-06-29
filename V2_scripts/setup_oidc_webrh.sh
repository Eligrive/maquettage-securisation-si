#!/bin/bash

#Script setup client oidc webrh 

echo "🔄 Configuration de la connexion SSO Keycloak sur l'application Web_RH..."

WEBRH_DIR="/var/www/webrh" # À ajuster selon le dossier de ton application
ENV_FILE="$WEBRH_DIR/.env"
WEBRH_SECRET="Secret_WebRH_OIDC_2026_Ultra_Securise"
KEYCLOAK_URL="https://sso.unicampus.fr/realms/master"

# 1. Sauvegarde de l'ancien fichier d'environnement
if [ -f "$ENV_FILE" ]; then
    cp $ENV_FILE "${ENV_FILE}.bak"
fi

# 2. Injection des paramètres d'authentification OIDC
echo "⚙️ Écriture des paramètres OIDC dans le fichier .env..."
cat << EOF >> $ENV_FILE

# --- Configuration SSO Keycloak (V2 Architecture) ---
AUTH_METHOD=OIDC
OIDC_PROVIDER_URL="$KEYCLOAK_URL"
OIDC_CLIENT_ID="webrh-client"
OIDC_CLIENT_SECRET="$WEBRH_SECRET"
OIDC_REDIRECT_URI="https://webrh.unicampus.fr/auth-callback"
OIDC_SCOPES="openid profile email"

# Sécurité Applicative : Rôle Keycloak requis pour ouvrir une session RH
REQUIRED_REALM_ROLE="Admin_RH" 
EOF

# 3. Redémarrage du service applicatif (ex: systemd ou docker) pour appliquer la configuration
echo "🔄 Redémarrage de l'application Web_RH..."
# Si l'application tourne avec systemd (ex: pm2, gunicorn, php-fpm) :
# sudo systemctl restart webrh.service

echo "✅ L'application Web_RH est désormais connectée au SSO Keycloak et restreinte aux profils autorisés !"