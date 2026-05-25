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
// Portail RH UniCampus+ — DEMO VOLONTAIREMENT VULNERABLE
//   - Aucune authentification (un seul rôle implicite, cf. SO5)
//   - SQLi sur le formulaire de recherche (cf. SO3)
//   - Pas de journalisation applicative des modifications
//   - Pas de validation à 4 yeux des changements RIB / salaire
$db = @new mysqli('192.168.107.20', 'rhapp', 'rh2024', 'rh');
echo "<h1>Portail RH UniCampus+</h1>";
if ($db->connect_errno) { echo "<p>DB indisponible</p>"; exit; }

// --- Modification RIB / salaire (SO5) — aucune auth, aucun audit ---
if (($_POST['action'] ?? '') === 'update') {
  $login   = $_POST['login']   ?? '';
  $salaire = (int)($_POST['salaire'] ?? 0);
  $rib     = $_POST['rib']     ?? '';
  $q = "UPDATE employes SET salaire=$salaire, rib='$rib' WHERE login='$login'";
  $ok = $db->query($q);
  echo $ok ? "<p style='color:green'>Modification enregistree.</p>"
          : "<p style='color:red'>Erreur : " . htmlspecialchars($db->error) . "</p>";
}

// --- Recherche (SQLi par conception) ---
$login = $_GET['login'] ?? '';
if ($login !== '') {
  $q = "SELECT login,nom,poste,salaire,rib FROM employes WHERE login='" . $login . "'";
  $r = $db->query($q);
  if ($r) { while ($row = $r->fetch_assoc()) {
    echo "<p>{$row['nom']} — {$row['poste']} — {$row['salaire']} EUR — RIB: {$row['rib']}</p>";
  } } else { echo "<p>Erreur SQL : " . htmlspecialchars($db->error) . "</p>"; }
} else {
  echo '<h2>Recherche</h2><form><input name="login" placeholder="login"><button>Rechercher</button></form>';
}

// --- Formulaire modification (SO5) ---
echo <<<HTML
<h2>Modifier RIB / salaire</h2>
<form method="post">
  <input type="hidden" name="action" value="update">
  Login : <input name="login" placeholder="login"><br>
  Salaire (EUR) : <input name="salaire" type="number"><br>
  RIB (IBAN) : <input name="rib" size="34" placeholder="FR76..."><br>
  <button>Enregistrer</button>
</form>
HTML;
PHP
rm -f /var/www/html/index.html

# --- Documents RH (leurres) exposés ---
mkdir -p /var/www/html/rh-docs
cp /opt/loot/*.pdf /var/www/html/rh-docs/ 2>/dev/null || true
chown -R www-data:www-data /var/www/html

# --- Comptes Unix nominatifs (cred reuse) : VP Finances + admin DSI ---
useradd -m -s /bin/bash cfournier 2>/dev/null || true; echo 'cfournier:finance2024' | chpasswd
useradd -m -s /bin/bash dsi       2>/dev/null || true; echo 'dsi:admin2024'         | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi

systemctl enable apache2
systemctl restart apache2

echo "uc-web-rh provisioning done"
