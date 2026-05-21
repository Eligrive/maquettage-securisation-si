#!/bin/bash
# Provisioning uc-calc-recherche (Ubuntu 22.04) — cf. architecture §4.2
# Calcul recherche : NFS et Samba ouverts, Jupyter sans auth (0.0.0.0:8888),
# PostgreSQL local. Héberge les données de recherche (leurres).
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nfs-kernel-server samba postgresql python3-pip

# --- Partage de données recherche ---
mkdir -p /srv/recherche
cp /opt/loot/*.pdf /srv/recherche/ 2>/dev/null || true
chmod -R 0777 /srv/recherche

# --- NFS : export monde entier, no_root_squash (vuln volontaire) ---
echo '/srv/recherche *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
exportfs -ra
systemctl enable nfs-kernel-server
systemctl restart nfs-kernel-server

# --- Samba : partage ouvert en invité ---
cat >> /etc/samba/smb.conf <<'EOF'

[recherche]
   path = /srv/recherche
   browseable = yes
   read only = no
   guest ok = yes
   force user = root
EOF
systemctl enable smbd
systemctl restart smbd

# --- PostgreSQL local : base résultats expérimentaux ---
sudo -u postgres psql <<'SQL'
CREATE DATABASE lrid_results;
CREATE USER recherche WITH PASSWORD 'recherche2024';
GRANT ALL PRIVILEGES ON DATABASE lrid_results TO recherche;
SQL

# --- Jupyter sans token ni mot de passe, écoute 0.0.0.0:8888 (vuln) ---
pip3 install --quiet notebook
useradd -m -s /bin/bash recherche 2>/dev/null || true
chown -R recherche:recherche /srv/recherche
cat > /etc/systemd/system/jupyter.service <<'EOF'
[Unit]
Description=Jupyter Notebook (maquette vulnérable)
After=network.target

[Service]
User=recherche
ExecStart=/usr/local/bin/jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' --notebook-dir=/srv/recherche
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable jupyter
systemctl restart jupyter

echo "uc-calc-recherche provisioning done"
