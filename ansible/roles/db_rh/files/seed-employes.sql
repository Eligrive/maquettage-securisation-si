-- Déposé par Ansible (rôle db_rh). RIBs fictifs FR + clé IBAN factice -> SO5
-- (détournement de versement). Mots de passe hashés SHA1 (faible, volontaire).
INSERT INTO employes (login, nom, poste, salaire, rib, password_sha1) VALUES
  ('jdupont',   'Jean-Pierre Dupont', 'Maitre de Conferences', 3200, 'FR7630001007941234567890185', SHA1('unicampus2024')),
  ('lmartin',   'Lea Martin',         'Etudiante',                0, 'FR7610107001011234567890132', SHA1('Printemps2024')),
  ('cfournier', 'Claire Fournier',    'VP Finances',           5400, 'FR7612548029981234567890174', SHA1('finance2024')),
  ('sleblanc',  'Sophie Leblanc',     'Chercheuse',            3800, 'FR7620041010051234567890150', SHA1('recherche2024'));
