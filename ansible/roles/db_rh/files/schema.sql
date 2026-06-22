-- Déposé par Ansible (rôle db_rh). Base RH + comptes (vulns volontaires).
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
