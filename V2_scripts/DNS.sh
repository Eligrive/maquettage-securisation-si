#!/bin/bash
# Script de setup du DNS 

# 1. Définition de l'IP cible (l'IP du Pare-feu / Reverse Proxy sur ce réseau)
PROXY_IP="192.168.108.1" 

# 2. On vérifie si la configuration n'existe pas déjà pour éviter les doublons
if ! grep -q "sso.unicampus.fr" /etc/hosts; then
    echo "Injection des résolutions DNS locales..."
    
    # 3. Injection dans le fichier
    cat <<EOF >> /etc/hosts
# Configuration DNS manuelle - Maquette V2 SSO & Proxy
$PROXY_IP    rh.unicampus.fr
$PROXY_IP    mail.unicampus.fr
$PROXY_IP    sso.unicampus.fr
$PROXY_IP    bastion.unicampus.fr
$PROXY_IP    moodle.unicampus.fr
EOF

    echo "Configuration DNS terminée."
else
    echo "La configuration DNS est déjà présente dans /etc/hosts."
fi