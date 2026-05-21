#!/bin/bash
# Provisioning uc-srv-moodle (Ubuntu 22.04) — cf. architecture §4.2, §6.2
# LMS Moodle : Apache + PHP + MariaDB locale, HTTP en clair, aucune politique
# de mot de passe. Comptes stockés dans mdl_user (bcrypt).
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

DBNAME=moodle
DBUSER=moodle
DBPASS=unicampus2024
ADMINPASS=Admin2024              # volontairement faible, aucune politique
WWWROOT="http://192.168.107.12"
MOODLE_BRANCH=MOODLE_404_STABLE

apt-get update
apt-get install -y apache2 mariadb-server git \
  php php-cli php-curl php-gd php-intl php-mbstring php-mysqli \
  php-xml php-zip php-soap php-xmlrpc libapache2-mod-php

# --- MariaDB locale (bind 127.0.0.1) + base Moodle ---
sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/50-server.cnf || true
systemctl enable mariadb
systemctl restart mariadb
mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DBNAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# PHP : MariaDB attend cette valeur pour Moodle
for INI in /etc/php/*/apache2/php.ini /etc/php/*/cli/php.ini; do
  [ -f "$INI" ] && sed -i 's/^max_input_vars.*/max_input_vars = 5000/' "$INI"
done

# --- Récupération de Moodle ---
git clone --depth=1 -b ${MOODLE_BRANCH} https://github.com/moodle/moodle.git /var/www/html/moodle
mkdir -p /var/moodledata
chown -R www-data:www-data /var/www/html/moodle /var/moodledata
chmod -R 0777 /var/moodledata   # permissif (vuln volontaire)

# --- Installation CLI non interactive ---
sudo -u www-data php /var/www/html/moodle/admin/cli/install.php \
  --non-interactive --agree-license \
  --wwwroot="${WWWROOT}" --dataroot=/var/moodledata \
  --dbtype=mariadb --dbhost=127.0.0.1 --dbname=${DBNAME} \
  --dbuser=${DBUSER} --dbpass=${DBPASS} \
  --fullname="UniCampus+ Moodle" --shortname="UC" \
  --adminuser=admin --adminpass="${ADMINPASS}" \
  --adminemail=admin@unicampus.local || true

# --- Apache : Moodle à la racine, HTTP en clair ---
cat > /etc/apache2/sites-available/000-default.conf <<'EOF'
<VirtualHost *:80>
    DocumentRoot /var/www/html/moodle
    <Directory /var/www/html/moodle>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
a2enmod rewrite
systemctl enable apache2
systemctl restart apache2

# --- Dépôt des documents pédagogiques (leurres) ---
mkdir -p /var/www/html/moodle/uc-docs
cp /opt/loot/*.pdf /var/www/html/moodle/uc-docs/ 2>/dev/null || true
chown -R www-data:www-data /var/www/html/moodle/uc-docs

echo "uc-srv-moodle provisioning done"
