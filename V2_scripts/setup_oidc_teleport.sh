#!/bin/bash

# Scritp de setup de l'oidc Teleport 


echo "🔗 Connexion du Bastion Teleport au SSO Keycloak..."

# Doit correspondre EXACTEMENT au secret défini dans le script Keycloak
TELEPORT_SECRET="Secret_Teleport_OIDC_2024_Ultra_Securise"

# ==========================================
# 1. CONNECTEUR OIDC
# ==========================================
cat << EOF > oidc-keycloak.yaml
kind: oidc
version: v3
metadata:
  name: keycloak
spec:
  redirect_url: "https://bastion.unicampus.fr/v1/webapi/oidc/callback"
  client_id: "teleport-bastion"
  client_secret: "$TELEPORT_SECRET"
  issuer_url: "https://sso.unicampus.fr/realms/master"
  
  claims_to_roles:
    - claim: "roles"
      value: "Admin_DSI"
      roles: ["role-teleport-admin-dsi"]
    - claim: "roles"
      value: "Admin_DBA"
      roles: ["role-teleport-admin-dba"]
    - claim: "roles"
      value: "Chercheur"
      roles: ["role-teleport-chercheur"]
EOF

# ==========================================
# 2. RÔLE : ADMIN DSI (Infrastructure)
# ==========================================
cat << 'EOF' > role-admin-dsi.yaml
kind: role
version: v5
metadata:
  name: role-teleport-admin-dsi
spec:
  allow:
    logins: ['ubuntu', 'dsi']
    node_labels:
      '*': '*'
EOF

# ==========================================
# 3. RÔLE : ADMIN DBA (Bases de données)
# ==========================================
cat << 'EOF' > role-admin-dba.yaml
kind: role
version: v5
metadata:
  name: role-teleport-admin-dba
spec:
  allow:
    db_labels:
      '*': '*'
    # Valeurs exactes issues de db-rh.sh et calc-recherche.sh
    db_names: ['lrid_results', 'rh']
    db_users: ['recherche', 'rhapp', 'root']
EOF

# ==========================================
# 4. RÔLE : CHERCHEUR (Recherche uniquement)
# ==========================================
cat << 'EOF' > role-chercheur.yaml
kind: role
version: v5
metadata:
  name: role-teleport-chercheur
spec:
  allow:
    db_labels:
      'env': 'recherche'
    # Valeurs exactes issues de calc-recherche.sh
    db_names: ['lrid_results']
    db_users: ['recherche']
EOF

# ==========================================
# 5. INJECTION DANS TELEPORT
# ==========================================
echo "⚙️ Application des politiques de sécurité RBAC..."
sudo tctl create -f oidc-keycloak.yaml
sudo tctl create -f role-admin-dsi.yaml
sudo tctl create -f role-admin-dba.yaml
sudo tctl create -f role-chercheur.yaml

rm oidc-keycloak.yaml role-admin-dsi.yaml role-admin-dba.yaml role-chercheur.yaml

echo "✅ Pont OIDC établi avec succès."