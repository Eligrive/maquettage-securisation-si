#!/bin/bash
# Script d'installation de l'agent Teleport à exécuter sur uc-calc-recherche (192.168.102.1)

BASTION_IP="192.168.103.2"
SHARED_JOIN_TOKEN="Token_De_Jointure_Teleport_V2_UniCampus_2026"

echo "📦 Installation de Teleport Agent..."
curl https://apt.releases.teleport.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/teleport-archive-keyring.gpg
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.gpg] https://apt.releases.teleport.dev/${ID?} ${VERSION_CODENAME?} stable/v15" | sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null
sudo apt-get update && sudo apt-get install -y teleport

echo "⚙️ Configuration automatique de l'agent (SSH + DB)..."
cat << EOF | sudo tee /etc/teleport.yaml
teleport:
  nodename: uc-calc-recherche
  data_dir: /var/lib/teleport
  auth_server: $BASTION_IP:3025
  # Utilisation du token pré-partagé
  auth_token: $SHARED_JOIN_TOKEN 

ssh_service:
  enabled: "yes"
  labels:
    env: recherche

db_service:
  enabled: "yes"
  databases:
    - name: "lrid_results"
      protocol: "postgres"
      uri: "localhost:5432"
      static_labels:
        env: recherche
EOF

echo "🔒 Verrouillage des accès de la V1..."
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sudo systemctl restart sshd

sudo sed -i "s/listen_addresses = '*'/listen_addresses = 'localhost'/g" /etc/postgresql/14/main/postgresql.conf
sudo systemctl restart postgresql

echo "🔄 Démarrage et jointure de l'agent Teleport..."
sudo systemctl enable --now teleport
echo "✅ Machine Recherche raccordée de manière autonome au Bastion !"