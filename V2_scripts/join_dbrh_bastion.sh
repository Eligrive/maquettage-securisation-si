#!/bin/bash
# Script de setup de l'agent Teleport à exécuter sur uc-db-rh (192.168.104.3)

BASTION_IP="192.168.103.2"
SHARED_JOIN_TOKEN="Token_De_Jointure_Teleport_V2_UniCampus_2026"

echo "📦 Installation de Teleport Agent..."
curl https://apt.releases.teleport.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/teleport-archive-keyring.gpg
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.gpg] https://apt.releases.teleport.dev/${ID?} ${VERSION_CODENAME?} stable/v15" | sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null
sudo apt-get update && sudo apt-get install -y teleport

echo "⚙️ Configuration automatique de l'agent (DB RH)..."
cat << EOF | sudo tee /etc/teleport.yaml
teleport:
  nodename: uc-db-rh
  data_dir: /var/lib/teleport
  auth_server: $BASTION_IP:3025
  # Utilisation du token pré-partagé
  auth_token: $SHARED_JOIN_TOKEN

ssh_service:
  enabled: "no"

db_service:
  enabled: "yes"
  databases:
    - name: "rh"
      protocol: "mysql"
      uri: "localhost:3306"
      static_labels:
        env: rh
EOF

echo "🔒 Isolement de MariaDB (Fermeture de l'exposition globale)..."
sudo sed -i 's/bind-address = 0.0.0.0/bind-address = 127.0.0.1/g' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb

echo "🔄 Démarrage et jointure de l'agent Teleport..."
sudo systemctl enable --now teleport
echo "✅ Base de données RH raccordée de manière autonome au Bastion !"