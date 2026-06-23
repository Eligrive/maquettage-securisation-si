#!/bin/bash
#Script d'installation de docker pour le SSO 

# 1. Nettoyage des anciennes versions conflictuelles
sudo apt remove -y docker.io docker-compose docker-doc podman-docker containerd runc

# 2. Mise à jour et installation des prérequis
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# 3. Création du dossier pour la clé de sécurité
sudo install -m 0755 -d /etc/apt/keyrings

# 4. Téléchargement de la clé GPG (Détection automatique de l'OS)
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | \
  sudo gpg --dearmor -yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 5. Ajout du dépôt officiel Docker (Détection automatique de l'OS)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 6. Installation finale du moteur Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Docker et Docker Compose sont installés avec succès !"