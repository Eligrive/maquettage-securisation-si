#!/bin/bash
# Script d'installation de keycloak

echo "Préparation du dossier Keycloak..."
sudo mkdir -p /opt/keycloak
cd /opt/keycloak

echo "Création du fichier docker-compose.yml..."
# Attention : Les espaces (l'indentation) sont stricts en YAML !
cat << 'EOF' | sudo tee docker-compose.yml
version: '3.8'

volumes:
  postgres_data:
    driver: local

services:
  postgres:
    image: postgres:15
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: password

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    # La commande "start" lance le mode production de Quarkus
    command: start
    environment:
      # --- Base de données ---
      KC_DB: postgres
      KC_DB_URL_HOST: postgres
      KC_DB_URL_DATABASE: keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: password
      
      # --- Création de l'administrateur ---
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: Mon_mot_de_passe
      
      # --- Configuration Reverse Proxy (Nginx) ---
      KC_PROXY: edge
      KC_HOSTNAME: sso.unicampus.fr
      # Autorise Keycloak à écouter en HTTP (car Nginx gère le HTTPS)
      KC_HTTP_ENABLED: "true" 
      
    ports:
      - "8080:8080"
    depends_on:
      - postgres
EOF

echo "Lancement des conteneurs en arrière-plan..."
sudo docker compose up -d

echo "Keycloak est en cours de démarrage !"
echo "Patiente environ 30 secondes, puis connecte-toi sur http://sso.unicampus.fr"