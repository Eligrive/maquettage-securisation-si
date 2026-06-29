#!/bin/bash
# ==============================================================================
# UniCampus+ V2 - Script d'installation automatisé de l'agent Teleport SSH
# Valable pour : uc-srv-mail, uc-srv-ldap, uc-web-rh, uc-srv-moodle, uc-srv-roundcube
# ==============================================================================

set -e # Arrêt immédiat du script en cas d'erreur
export DEBIAN_FRONTEND=noninteractive

# 1. Auto-détection du nom de la machine courante
NODE_NAME=$(hostname)
ENV_LABEL="infra"

# 2. Variables de liaison de la maquette V2
BASTION_IP="192.168.103.2" # IP fixe du Bastion Central
SHARED_JOIN_TOKEN="Token_De_Jointure_Teleport_V2_UniCampus_2026" # Jeton pré-partagé fige

echo "🚀 [${NODE_NAME}] Initialisation du raccordement vers le Bastion Teleport..."

# ==============================================================================
# 1. REPO & DEPS : Configuration des dépôts officiels Teleport
# ==============================================================================
echo "📦 Configuration du dépôt APT pour Teleport v15..."
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://apt.releases.teleport.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/teleport-archive-keyring.gpg

source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.gpg] https://apt.releases.teleport.dev/${ID?} ${VERSION_CODENAME?} stable/v15" | sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null

echo "🔄 Mise à jour des paquets et installation de l'agent..."
sudo apt-get update
sudo apt-get install -y teleport

# ==============================================================================
# 2. CONFIGURATION : Génération du fichier d'agent /etc/teleport.yaml
# ==============================================================================
echo "⚙️ Écriture de la configuration de l'agent..."
cat << EOF | sudo tee /etc/teleport.yaml
teleport:
  nodename: $NODE_NAME
  data_dir: /var/lib/teleport
  auth_server: $BASTION_IP:3025
  auth_token: $SHARED_JOIN_TOKEN

# Activation stricte du service SSH contrôlé par Teleport
ssh_service:
  enabled: "yes"
  labels:
    env: $ENV_LABEL

# Désactivation des services inutiles pour les nœuds d'infrastructure génériques
db_service:
  enabled: "no"
app_service:
  enabled: "no"
EOF

# ==============================================================================
# 3. DURCISSEMENT (Hardening) : Verrouillage du protocole SSH Legacy
# ==============================================================================
echo "🔒 Durcissement du système : Fermeture du SSH traditionnel par mot de passe..."

# Modification de la configuration OpenSSH d'origine (Port 22 classique)
if [ -f /etc/ssh/sshd_config ]; then
    # Désactive l'authentification par mot de passe
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
    # Désactive l'accès root direct hors clé
    sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config
    
    echo "🔄 Redémarrage d'OpenSSH pour appliquer le durcissement..."
    sudo systemctl restart sshd
fi

# ==============================================================================
# 4. INITIALISATION : Démarrage du daemon de l'agent
# ==============================================================================
echo "🔄 Activation et démarrage de l'infrastructure de l'agent Teleport..."
sudo systemctl daemon-reload
sudo systemctl enable --now teleport

echo "✅ [${NODE_NAME}] Raccordement terminé avec succès sous l'étiquette 'env: ${ENV_LABEL}' !"