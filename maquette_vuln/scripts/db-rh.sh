#!/bin/bash
# Provisioning uc-db-rh (Ubuntu 22.04) — cf. architecture §4.3, §6.2
# Base RH MariaDB exposée sur 0.0.0.0, comptes hashés en SHA1, root distant.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y mariadb-server

# --- Écoute sur toutes les interfaces (vuln volontaire) ---
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl enable mariadb
systemctl restart mariadb

# --- Base RH + comptes (SHA1, mots de passe faibles) ---
mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS rh;

-- Compte applicatif utilisé par uc-web-rh
CREATE USER IF NOT EXISTS 'rhapp'@'%' IDENTIFIED BY 'rh2024';
GRANT ALL PRIVILEGES ON rh.* TO 'rhapp'@'%';

-- Root accessible à distance (mauvaise pratique volontaire)
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

USE rh;
CREATE TABLE IF NOT EXISTS employes (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  login         VARCHAR(64),
  nom           VARCHAR(128),
  poste         VARCHAR(128),
  salaire       INT,
  rib           VARCHAR(34),
  password_sha1 CHAR(40)
);
-- RIBs fictifs FR + clé IBAN factice -> servent SO5 (détournement de versement)
INSERT INTO employes (login, nom, poste, salaire, rib, password_sha1) VALUES
  ('jdupont',   'Jean-Pierre Dupont', 'Maitre de Conferences', 3200, 'FR7630001007941234567890185', SHA1('unicampus2024')),
  ('lmartin',   'Lea Martin',         'Etudiante',                0, 'FR7610107001011234567890132', SHA1('Printemps2024')),
  ('cfournier', 'Claire Fournier',    'VP Finances',           5400, 'FR7612548029981234567890174', SHA1('finance2024')),
  ('sleblanc',  'Sophie Leblanc',     'Chercheuse',            3800, 'FR7620041010051234567890150', SHA1('recherche2024'));
SQL

# --- Comptes Unix (cred reuse) : compte dsi uniquement (BDD = pas d'utilisateur métier) ---
useradd -m -s /bin/bash dsi 2>/dev/null || true; echo 'dsi:admin2024' | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi

echo "uc-db-rh provisioning done"
