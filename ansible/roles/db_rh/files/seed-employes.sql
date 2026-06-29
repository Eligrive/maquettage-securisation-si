-- Déposé par Ansible (rôle db_rh). RIBs fictifs FR + clé IBAN factice.
-- V2 : plus aucun hash de mot de passe en base (authentification déléguée au
-- SSO Keycloak, cf. schema.sql §4.4). La base RH ne contient que de la donnée
-- métier (login = identifiant SSO, nom, poste, salaire, rib).
INSERT INTO employes (login, nom, poste, salaire, rib) VALUES
  ('jdupont',   'Jean-Pierre Dupont', 'Maitre de Conferences', 3200, 'FR7630001007941234567890185'),
  ('lmartin',   'Lea Martin',         'Etudiante',                0, 'FR7610107001011234567890132'),
  ('cfournier', 'Claire Fournier',    'VP Finances',           5400, 'FR7612548029981234567890174'),
  ('sleblanc',  'Sophie Leblanc',     'Chercheuse',            3800, 'FR7620041010051234567890150');
