#!/bin/bash
# Script d'installation et setup de Teleport sur la machine bastion 

# 1. Ajout du dépôt officiel Teleport pour Ubuntu
curl https://apt.releases.teleport.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/teleport-archive-keyring.gpg
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.gpg] https://apt.releases.teleport.dev/${ID?} ${VERSION_CODENAME?} stable/v15" | sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null

# 2. Installation du paquet
sudo apt-get update
sudo apt-get install -y teleport

echo "📝 Création du fichier de configuration principal..."

#!/bin/bash

echo "🚀 Installation de Teleport sur le Bastion..."

# 1. Ajout du dépôt officiel Teleport pour Ubuntu
curl https://apt.releases.teleport.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/teleport-archive-keyring.gpg
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.gpg] https://apt.releases.teleport.dev/${ID?} ${VERSION_CODENAME?} stable/v15" | sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null

# 2. Installation du paquet
sudo apt-get update
sudo apt-get install -y teleport

echo "📝 Création du fichier de configuration principal..."

# 3. Fichier de configuration du Bastion
cat << 'EOF' | sudo tee /etc/teleport.yaml
teleport:
  nodename: bastion.unicampus.fr
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO
  
auth_service:
  enabled: "yes"
  cluster_name: "bastion.unicampus.fr"
  # Le Bastion gère l'authentification localement pour le cluster
  listen_addr: 0.0.0.0:3025

proxy_service:
  enabled: "yes"
  # L'adresse publique que Nginx va contacter
  public_addr: bastion.unicampus.fr:443
  web_listen_addr: 0.0.0.0:3080
  listen_addr: 0.0.0.0:3023
  tunnel_listen_addr: 0.0.0.0:3024
  
  # Tes certificats SSL (Les mêmes que Nginx si c'est un Wildcard)
  https_keypairs:
  - key_file: TO DO 
    cert_file: TO DO 

ssh_service:
  # On désactive le service SSH local du Bastion lui-même (c'est juste un routeur)
  enabled: "no"
EOF

echo "🔄 Démarrage du service Teleport..."
sudo systemctl enable --now teleport
echo "✅ Teleport est installé et tourne sur le port 3080 (Web) !"