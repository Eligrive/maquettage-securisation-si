#!/bin/bash
# Provisioning uc-web-rh (Ubuntu 22.04) — cf. architecture §4.2, §4.4
# Portail web RH (Apache+PHP) interrogeant la base uc-db-rh (192.168.107.20).
# Injection SQL volontaire, HTTP en clair.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apache2 php php-mysqli libapache2-mod-php

cat > /var/www/html/index.php <<'PHP'
<?php
// Portail RH UniCampus+ — DEMO VOLONTAIREMENT VULNERABLE (injection SQL)
$db = @new mysqli('192.168.107.20', 'rhapp', 'rh2024', 'rh');
echo "<h1>Portail RH UniCampus+</h1>";
if ($db->connect_errno) { echo "<p>DB indisponible</p>"; exit; }
$login = $_GET['login'] ?? '';
if ($login !== '') {
  // Requete concatenee -> injection SQL possible (par conception)
  $q = "SELECT login,nom,poste,salaire FROM employes WHERE login='" . $login . "'";
  $r = $db->query($q);
  if ($r) { while ($row = $r->fetch_assoc()) {
    echo "<p>{$row['nom']} — {$row['poste']} — {$row['salaire']} EUR</p>";
  } } else { echo "<p>Erreur SQL : " . htmlspecialchars($db->error) . "</p>"; }
} else {
  echo '<form><input name="login" placeholder="login"><button>Rechercher</button></form>';
}
PHP
rm -f /var/www/html/index.html

# --- Documents RH (leurres) exposés ---
mkdir -p /var/www/html/rh-docs
cp /opt/loot/*.pdf /var/www/html/rh-docs/ 2>/dev/null || true
chown -R www-data:www-data /var/www/html

systemctl enable apache2
systemctl restart apache2

echo "uc-web-rh provisioning done"
