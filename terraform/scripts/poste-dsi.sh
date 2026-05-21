#!/bin/bash
# Provisioning uc-poste-dsi (Ubuntu 22.04) — cf. architecture §3.4, §6.3
# Poste DSI / admin : sudo NOPASSWD, documents administratifs sensibles,
# emplacement prévu pour la clé privée d'admin (déposée hors-template).
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y openssh-client nfs-common smbclient

# --- sudo NOPASSWD pour ubuntu (cf. §6.3) ---
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-uc-nopasswd
chmod 0440 /etc/sudoers.d/90-uc-nopasswd

# --- Documents administratifs / DSI (leurres) ---
mkdir -p /home/ubuntu/Documents
cp /opt/loot/*.pdf /home/ubuntu/Documents/ 2>/dev/null || true
chown -R ubuntu:ubuntu /home/ubuntu/Documents

# --- Clé d'admin ---
# Par conception (§6.3), l'admin DSI conserve sa clé privée EN CLAIR dans
# /home/ubuntu/.ssh/id_rsa pour accéder en SSH à tous les serveurs.
# On NE versionne PAS de clé privée ici : déposer manuellement la clé privée
# correspondant à la keypair du groupe (cf. keypair.tf) dans ce fichier.
install -d -o ubuntu -g ubuntu -m 0700 /home/ubuntu/.ssh
cat > /home/ubuntu/NOTE-cle-admin.txt <<'EOF'
Déposer ici la clé privée d'admin (correspondant à uc-keypair-admin) :
  /home/ubuntu/.ssh/id_rsa   (chmod 600)
Elle donne un accès SSH root/ubuntu à toutes les VMs de la maquette.
EOF
chown ubuntu:ubuntu /home/ubuntu/NOTE-cle-admin.txt

echo "uc-poste-dsi provisioning done"
