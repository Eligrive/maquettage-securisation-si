-- Déposé par Ansible (rôle db_rh). Base RH + comptes — V2 DURCIE.
-- Remédiations analyse de risque :
--   §4.3  plus de compte root accessible à distance, compte applicatif restreint
--         à l'IP du front web-rh + moindre privilège (ni DDL, ni FILE, ni accès
--         aux autres bases -> neutralise aussi l'exécution SQLi INTO OUTFILE).
--   §4.4  plus aucun hash d'authentification stocké dans la base : l'authentification
--         est déléguée au SSO Keycloak (OIDC). Il n'y a donc plus de secret
--         crackable à exfiltrer (le risque "hashs SHA1 cassés" disparaît par
--         conception). La base RH ne contient que de la donnée métier.
CREATE DATABASE IF NOT EXISTS rh;

-- Nettoyage des comptes hérités V1 (wildcard @'%' / root distant) s'ils existent.
DROP USER IF EXISTS 'root'@'%';
DROP USER IF EXISTS 'rhapp'@'%';

-- Compte applicatif : UNIQUEMENT depuis le front web-rh (192.168.104.2) et
-- seulement les droits métier nécessaires. Pas de GRANT ALL, pas de FILE,
-- pas de privilège d'administration.
CREATE USER IF NOT EXISTS 'rhapp'@'192.168.104.2' IDENTIFIED BY 'rh2024';
GRANT SELECT, INSERT, UPDATE, DELETE ON rh.* TO 'rhapp'@'192.168.104.2';
FLUSH PRIVILEGES;

USE rh;

-- Donnée métier uniquement (plus de colonne password_sha1).
CREATE TABLE IF NOT EXISTS employes (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  login         VARCHAR(64),
  nom           VARCHAR(128),
  poste         VARCHAR(128),
  salaire       INT,
  rib           VARCHAR(34)
);

-- Journal d'audit applicatif (remédiation §5.1 : traçabilité des modifications RH).
-- Chaque écriture est imputée à une identité SSO + horodatée. Lu par l'agent
-- Wazuh (corrélation SIEM) via la sortie syslog du portail, et conservé en base.
CREATE TABLE IF NOT EXISTS audit_rh (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  ts      DATETIME DEFAULT CURRENT_TIMESTAMP,
  acteur  VARCHAR(128),
  action  VARCHAR(64),
  cible   VARCHAR(64),
  details TEXT
);

-- File de validation à 4 yeux (remédiation §4.2 / SO5 : séparation des tâches).
-- Une modification de RIB / salaire est d'abord une DEMANDE ; elle n'est appliquée
-- qu'après validation par un AUTRE administrateur RH (validateur != demandeur).
CREATE TABLE IF NOT EXISTS rib_pending (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  login           VARCHAR(64),
  nouveau_rib     VARCHAR(34),
  nouveau_salaire INT,
  demandeur       VARCHAR(128),
  ts_demande      DATETIME DEFAULT CURRENT_TIMESTAMP,
  statut          ENUM('EN_ATTENTE','VALIDE','REJETE') DEFAULT 'EN_ATTENTE',
  validateur      VARCHAR(128),
  ts_validation   DATETIME
);
