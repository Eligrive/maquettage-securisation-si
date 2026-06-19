#!/bin/bash

# ==============================================================================
# Script de déploiement automatisé : Reverse Proxy Nginx (Maquette V2)
# ==============================================================================

# Variables
CONF_AVAILABLE="/etc/nginx/sites-available/unicampus"
CONF_ENABLED="/etc/nginx/sites-enabled/unicampus"


# Remplace ces valeurs par les chemins réels une fois tes certificats générés
SSL_CERT_PATH=""
SSL_KEY_PATH=""

echo "Début de la configuration automatisée du Reverse Proxy..."

# 1. Vérification des droits administrateur
if [ "$EUID" -ne 0 ]; then
  echo " Erreur : Ce script doit être exécuté en tant que root (sudo)."
  exit 1
fi

# 2. Écriture du fichier de configuration Nginx
echo "Écriture du fichier de configuration dans $CONF_AVAILABLE..."

cat << EOF > "$CONF_AVAILABLE"
# ==========================================
# 1. SSO - KEYCLOAK (Zone DMZ)
# ==========================================
server {
    listen 443 ssl;
    server_name sso.unicampus.fr;

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};

    location / {
        proxy_pass http://192.168.107.3:8080; 

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme; 
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
    }
}

# ==========================================
# 2. PORTAIL RH (Zone Privée RH)
# ==========================================
server {
    listen 443 ssl;
    server_name rh.unicampus.fr;

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};

    location / {
        proxy_pass http://192.168.104.2:80; 
        
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# ==========================================
# 3. WEBMAIL - ROUNDCUBE (Zone DMZ)
# ==========================================
server {
    listen 443 ssl;
    server_name mail.unicampus.fr;

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};

    location / {
        proxy_pass http://192.168.107.2:80; 
        
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# ==========================================
# 4. BASTION - TELEPORT (Zone Admin)
# ==========================================
server {
    listen 443 ssl;
    server_name bastion.unicampus.fr;

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};

    location / {
        proxy_pass http://192.168.103.2:3080; 
        
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# ==========================================
# 5. PLATEFORME PÉDAGOGIQUE - MOODLE (Zone DMZ)
# ==========================================
server {
    listen 443 ssl;
    server_name moodle.unicampus.fr;

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};

    location / {
        proxy_pass http://192.168.107.1:80; 
        
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

EOF

# 3. Désactivation de la configuration par défaut de Nginx (pour éviter les conflits)
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    echo "Suppression du site par défaut de Nginx"
    rm /etc/nginx/sites-enabled/default
fi

# 4. Activation de la nouvelle configuration (Création du lien symbolique)
# L'option -f permet d'écraser le lien s'il existe déjà
echo "🔗 Activation du site unicampus..."
ln -sf "$CONF_AVAILABLE" "$CONF_ENABLED"

# 5. Test de la syntaxe Nginx
echo "Vérification de la syntaxe Nginx"
nginx -t

if [ $? -eq 0 ]; then
    # 6. Redémarrage propre si la syntaxe est bonne
    echo "Syntaxe valide. Rechargement de Nginx..."
    systemctl reload nginx
    echo "Terminé avec succès ! Le Reverse Proxy est opérationnel."
else
    # Arrêt du script si la syntaxe est mauvaise
    echo "Erreur de syntaxe dans la configuration Nginx. Le rechargement a été annulé."
    exit 1
fi