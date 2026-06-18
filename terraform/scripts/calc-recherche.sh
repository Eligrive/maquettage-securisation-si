#!/bin/bash
# Provisioning uc-calc-recherche (Ubuntu 22.04) — cf. architecture §4.2
# Calcul recherche : NFS et Samba ouverts, Jupyter sans auth (0.0.0.0:8888),
# PostgreSQL local. Héberge les données de recherche (leurres).
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nfs-kernel-server samba postgresql python3-pip python3-venv

# --- Partage de données recherche ---
mkdir -p /srv/recherche
cp /opt/loot/*.pdf /srv/recherche/ 2>/dev/null || true
chmod -R 0777 /srv/recherche

# --- NFS : export monde entier, no_root_squash (vuln volontaire) ---
echo '/srv/recherche *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
exportfs -ra
systemctl enable nfs-kernel-server
systemctl restart nfs-kernel-server

# --- Samba : partage ouvert en invité + partage "partenaires" authentifié ---
# Le partage authentifié sert SO4 : un acteur étatique récupère des credentials
# d'application "partenaire" (PA1) ayant accès aux données scientifiques
# partagées avec le labo partenaire (cf. justif §X).
cat >> /etc/samba/smb.conf <<'EOF'

[recherche]
   path = /srv/recherche
   browseable = yes
   read only = no
   guest ok = yes
   force user = root

[partenaires]
   path = /srv/recherche
   browseable = yes
   read only = no
   valid users = pa1, sleblanc, jdupont
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

# --- Comptes Unix nominatifs (cred reuse) + compte partenaire PA1 ---
useradd -m -s /bin/bash jdupont  2>/dev/null || true; echo 'jdupont:unicampus2024'  | chpasswd
useradd -m -s /bin/bash sleblanc 2>/dev/null || true; echo 'sleblanc:recherche2024' | chpasswd
useradd -m -s /bin/bash dsi      2>/dev/null || true; echo 'dsi:admin2024'          | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi
# Compte applicatif d'un labo partenaire (PA1) -> creds "fuités" servant SO4
useradd -m -s /bin/bash pa1 2>/dev/null || true; echo 'pa1:partenaire2024' | chpasswd
# Mot de passe Samba pour pa1 (et sleblanc/jdupont pour le partage authentifié)
(echo 'partenaire2024'; echo 'partenaire2024') | smbpasswd -a -s pa1
(echo 'recherche2024';  echo 'recherche2024')  | smbpasswd -a -s sleblanc
(echo 'unicampus2024';  echo 'unicampus2024')  | smbpasswd -a -s jdupont

# --- Jupyter sans token ni mot de passe, écoute 0.0.0.0:8888 (vuln) ---
# Install dans un venv isolé. Pourquoi pas `pip3 install --break-system-packages
# notebook` directement ? Sur Ubuntu 24.04 le paquet apt `python3-traitlets`
# a un RECORD manquant et pip refuse de le mettre à jour ; la version notebook
# qu'on installe demande une traitlets plus récente -> import error
# "warn() missing required keyword-only argument 'stacklevel'" -> service
# crash en boucle. Le venv isole proprement les deps.
python3 -m venv /opt/jupyter-venv
/opt/jupyter-venv/bin/pip install --quiet --upgrade pip
/opt/jupyter-venv/bin/pip install --quiet notebook
useradd -m -s /bin/bash recherche 2>/dev/null || true
chown -R recherche:sleblanc /srv/recherche 2>/dev/null || chown -R recherche:recherche /srv/recherche
cat > /etc/systemd/system/jupyter.service <<'EOF'
[Unit]
Description=Jupyter Notebook (maquette vulnérable)
After=network.target

[Service]
User=recherche
WorkingDirectory=/srv/recherche
ExecStart=/opt/jupyter-venv/bin/jupyter-notebook --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' --notebook-dir=/srv/recherche
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable jupyter
systemctl restart jupyter

echo "uc-calc-recherche provisioning done"
