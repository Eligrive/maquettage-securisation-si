"""
v7 du classeur : construction complète de l'atelier 4.

- Supprime la feuille placeholder A4
- Crée A4.0 Échelle de vraisemblance
- Crée A4.1 Graphes d'attaque (6 graphes matplotlib embarqués)
- Crée A4.2 Synthèse opérationnelle (tableau récap BSC, vulnérabilités, vraisemblance)
- Met à jour le plan dans Introduction
"""

import os
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np
from openpyxl import load_workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.drawing.image import Image as XLImage

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "EBIOS_RM_UniCampus.xlsx")
DST = SRC  # écrase sur place
GRAPH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".build_a4_graphs")
os.makedirs(GRAPH_DIR, exist_ok=True)

# ============================================================
# Styles Excel
# ============================================================
C_HEADER_BG = "1F4E78"
C_HEADER_FG = "FFFFFF"
C_SECTION_BG = "D9E1F2"
C_ALT_ROW = "F2F2F2"
C_NOTE_BG = "FFF2CC"
C_V1 = "C6EFCE"; C_V2 = "FFEB9C"; C_V3 = "FFD699"; C_V4 = "FFC7CE"
C_G2 = "FFEB9C"; C_G3 = "FFD699"; C_G4 = "FFC7CE"

FONT_TITLE = Font(name="Arial", size=16, bold=True, color=C_HEADER_FG)
FONT_SECTION = Font(name="Arial", size=12, bold=True, color="1F4E78")
FONT_SUBTITLE = Font(name="Arial", size=13, bold=True, color="1F4E78")
FONT_HEADER = Font(name="Arial", size=11, bold=True, color=C_HEADER_FG)
FONT_BODY = Font(name="Arial", size=10)
FONT_BODY_BOLD = Font(name="Arial", size=10, bold=True)
FONT_NOTE = Font(name="Arial", size=10, italic=True, color="595959")

FILL_TITLE = PatternFill("solid", start_color=C_HEADER_BG)
FILL_SECTION = PatternFill("solid", start_color=C_SECTION_BG)
FILL_HEADER = PatternFill("solid", start_color=C_HEADER_BG)
FILL_ALT = PatternFill("solid", start_color=C_ALT_ROW)
FILL_NOTE = PatternFill("solid", start_color=C_NOTE_BG)
FILL_V1 = PatternFill("solid", start_color=C_V1)
FILL_V2 = PatternFill("solid", start_color=C_V2)
FILL_V3 = PatternFill("solid", start_color=C_V3)
FILL_V4 = PatternFill("solid", start_color=C_V4)
V_FILL = {"V1": FILL_V1, "V2": FILL_V2, "V3": FILL_V3, "V4": FILL_V4}
G_FILL = {"G2": PatternFill("solid", start_color=C_G2),
          "G3": PatternFill("solid", start_color=C_G3),
          "G4": PatternFill("solid", start_color=C_G4)}

ALIGN_WRAP = Alignment(wrap_text=True, vertical="top", horizontal="left")
ALIGN_WRAP_CENTER = Alignment(wrap_text=True, vertical="center", horizontal="center")
ALIGN_WRAP_LEFT_CENTER = Alignment(wrap_text=True, vertical="center", horizontal="left", indent=1)

THIN = Side(border_style="thin", color="BFBFBF")
BORDER_ALL = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def set_widths(ws, widths):
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w


def add_title(ws, n_cols, title):
    ws.merge_cells(start_row=1, end_row=2, start_column=1, end_column=n_cols)
    c = ws.cell(row=1, column=1, value=title)
    c.font = FONT_TITLE; c.fill = FILL_TITLE; c.alignment = ALIGN_WRAP_CENTER
    ws.row_dimensions[1].height = 26; ws.row_dimensions[2].height = 26


def add_note(ws, row, n_cols, text, height=70):
    ws.merge_cells(start_row=row, end_row=row, start_column=1, end_column=n_cols)
    c = ws.cell(row=row, column=1, value=text)
    c.font = FONT_NOTE; c.fill = FILL_NOTE; c.alignment = ALIGN_WRAP; c.border = BORDER_ALL
    ws.row_dimensions[row].height = height


def add_section(ws, row, n_cols, text, height=22):
    ws.merge_cells(start_row=row, end_row=row, start_column=1, end_column=n_cols)
    c = ws.cell(row=row, column=1, value=text)
    c.font = FONT_SECTION; c.fill = FILL_SECTION; c.alignment = ALIGN_WRAP_LEFT_CENTER
    ws.row_dimensions[row].height = height


def style_headers(ws, row, n_cols, height=32):
    for col in range(1, n_cols + 1):
        c = ws.cell(row=row, column=col)
        c.font = FONT_HEADER; c.fill = FILL_HEADER
        c.alignment = ALIGN_WRAP_CENTER; c.border = BORDER_ALL
    ws.row_dimensions[row].height = height


# ============================================================
# DONNÉES DES 6 SCÉNARIOS OPÉRATIONNELS
# ============================================================
# Format : chaque SO a 4 phases, chaque phase contient des actions élémentaires.
# Chaque action a un id, un label court (pour la boîte), un long (pour le tableau)
# et un flag retenu (True si dans le chemin retenu).
# Les connexions définissent les flèches : (from_id, to_id, retenu).

# Curation v3 : actions vraiment pertinentes uniquement (variable par phase),
# chaîne retenue identique à v1 (pour préserver A4.2 et A5), connexions épurées
# (chaque alternative a une seule flèche sortante vers son successeur le plus
# logique - jamais alt -> alt - pour éviter le spaghetti).
so_data = [
    {
        "code": "SO1",
        "title": "Étudiant malveillant compromet les résultats académiques",
        "ss_parent": "SS1",
        "sr": "SR-A Étudiant malveillant",
        "ov": "Compromettre les résultats académiques",
        "er_target": "ER03",
        "gravity": "G3",
        "vraisemblance": "V3",
        "vraisemblance_label": "Très vraisemblable",
        "phases": {
            "CONNAÎTRE": [
                {"id": "c1", "label": "Scan VLAN\n192.168.107.0/24\ndepuis WiFi étudiant", "retenu": True},
                {"id": "c2", "label": "Énumération LDAP\nanonyme\n(comptes enseignants)", "retenu": True},
                {"id": "c3", "label": "OSINT enseignants\n(réseaux sociaux,\nsite UniCampus)", "retenu": False},
            ],
            "RENTRER": [
                {"id": "r1", "label": "Phishing ciblé\nd'un enseignant\n(pièce jointe piégée)", "retenu": True},
                {"id": "r2", "label": "Brute-force\nMoodle\n(pas de rate-limit)", "retenu": False},
                {"id": "r3", "label": "Attaque dictionnaire\nLDAP via\nbind anonyme", "retenu": False},
            ],
            "TROUVER": [
                {"id": "t1", "label": "Connexion Moodle\navec credentials\nenseignant", "retenu": True},
                {"id": "t2", "label": "Accès direct\nBDD Moodle\n(via compromission)", "retenu": False},
            ],
            "EXPLOITER": [
                {"id": "e1", "label": "Modification\ndes notes\ndans mdl_grade_*", "retenu": True},
                {"id": "e2", "label": "Vol de sujets\nd'examens\nfuturs", "retenu": False},
            ],
        },
        "connexions": [
            # Chaîne retenue
            ("c1", "r1", True), ("c2", "r1", True), ("r1", "t1", True), ("t1", "e1", True),
            # Alternatives (1 flèche par alt vers son successeur le plus logique)
            ("c3", "r1", False),  # OSINT alimente le phishing
            ("r2", "t1", False),  # brute-force aboutit au même login Moodle
            ("r3", "t1", False),  # creds LDAP -> connexion Moodle
            ("t2", "e1", False),  # BDD directe -> modif notes
            ("t1", "e2", False),  # accès légitime -> vol sujets aussi possible
        ],
        "bsc": ["BS01 Moodle", "BS02 BDD Moodle", "BS04 LDAP", "BS13 Réseau campus"],
        "vulns": [
            "Bind LDAP anonyme sur uc-srv-ldap (slapd sans TLS)",
            "WiFi étudiant et serveurs sur le même VLAN 192.168.107.0/24 (pas de cloisonnement)",
            "Pas de MFA ni de rate-limit sur Moodle",
            "Aucun log centralisé : modification non détectable a posteriori",
        ],
    },
    {
        "code": "SO2",
        "title": "Cybercriminel déploie un rançongiciel",
        "ss_parent": "SS2",
        "sr": "SR-B Cybercriminel motivé financièrement",
        "ov": "Bloquer le SI pour obtenir une rançon",
        "er_target": "ER01",
        "gravity": "G4",
        "vraisemblance": "V4",
        "vraisemblance_label": "Certain ou déjà produit",
        "phases": {
            "CONNAÎTRE": [
                {"id": "c1", "label": "OSINT personnel\n(LinkedIn,\nsite web)", "retenu": True},
                {"id": "c2", "label": "Mails via leak\ndatabases\n(HIBP, dehashed)", "retenu": False},
                {"id": "c3", "label": "Recon Shodan /\nport scan\nfaçade Internet", "retenu": False},
            ],
            "RENTRER": [
                {"id": "r1", "label": "Phishing ciblé\n(pièce jointe\nmacro/ISO)", "retenu": True},
                {"id": "r2", "label": "Supply-chain via\néditeur logiciel\n(PR1 compromis)", "retenu": False},
                {"id": "r3", "label": "Exploitation CVE\nsur service exposé\nfaçade Internet", "retenu": False},
                {"id": "r4", "label": "Brute-force VPN\nlegacy PPTP\n(MPPE-128 RC4)", "retenu": False},
            ],
            "TROUVER": [
                {"id": "t1", "label": "Vol clé SSH\nen clair sur\nuc-poste-dsi /.ssh/", "retenu": True},
                {"id": "t2", "label": "Élévation\nsudo NOPASSWD\nposte DSI", "retenu": True},
                {"id": "t3", "label": "Latéralisation\nVLAN unique\n(pas de cloisonnement)", "retenu": False},
            ],
            "EXPLOITER": [
                {"id": "e1", "label": "Chiffrement simultané\nMoodle / RH /\nRecherche / Mail", "retenu": True},
                {"id": "e2", "label": "Rançon et\nnégociation\n(C2 externe)", "retenu": True},
                {"id": "e3", "label": "Destruction des\nsauvegardes\naccessibles", "retenu": False},
            ],
        },
        "connexions": [
            # Chaîne retenue
            ("c1", "r1", True), ("r1", "t1", True), ("t1", "t2", True),
            ("t2", "e1", True), ("e1", "e2", True),
            # Alternatives
            ("c2", "r1", False),  # mails leak -> phishing
            ("c3", "r3", False),  # recon -> exploitation CVE
            ("c3", "r4", False),  # recon -> identifie VPN exposé
            ("r2", "t1", False),  # supply chain -> compromission poste
            ("r3", "t1", False),  # CVE -> poste
            ("r4", "t3", False),  # VPN -> latéralisation
            ("t3", "e1", False),  # latéral -> chiffrement
            ("e1", "e3", False),  # destruction sauvegardes pendant chiffrement
        ],
        "bsc": ["BS01 Moodle", "BS05 Web RH", "BS07 BDD RH", "BS08 Mail", "BS10 NFS recherche", "BS13 Réseau campus"],
        "vulns": [
            "Clé SSH d'admin DSI stockée en clair sur uc-poste-dsi (/home/ubuntu/.ssh/)",
            "Sudo NOPASSWD pour ubuntu sur toutes les VMs",
            "VPN PPTP legacy avec MPPE-128 (RC4 déprécié) et compte partagé (campus/unicampus2024)",
            "Aucun cloisonnement réseau : un seul VLAN pour serveurs et postes",
            "Pas de sauvegarde immuable (ni offline) -> rançon = seule option de récupération",
        ],
    },
    {
        "code": "SO3",
        "title": "Cybercriminel exfiltre les données personnelles",
        "ss_parent": "SS3",
        "sr": "SR-B Cybercriminel motivé financièrement",
        "ov": "Exfiltrer la base RH et données personnelles",
        "er_target": "ER02",
        "gravity": "G4",
        "vraisemblance": "V3",
        "vraisemblance_label": "Très vraisemblable",
        "phases": {
            "CONNAÎTRE": [
                {"id": "c1", "label": "Port scan externe\n(identification\nuc-web-rh)", "retenu": True},
                {"id": "c2", "label": "Bind LDAP anonyme\n(énumération\ncomptes admin)", "retenu": False},
                {"id": "c3", "label": "Identification\nrelation web<->BDD\n(3306 exposé)", "retenu": False},
            ],
            "RENTRER": [
                {"id": "r1", "label": "Injection SQL\nsur uc-web-rh\n(login bypass)", "retenu": True},
                {"id": "r2", "label": "MITM HTTP\n(capture creds\nen clair)", "retenu": False},
                {"id": "r3", "label": "Phishing\nadmin RH", "retenu": False},
            ],
            "TROUVER": [
                {"id": "t1", "label": "Lecture directe\nuc-db-rh\n(0.0.0.0:3306)", "retenu": True},
                {"id": "t2", "label": "Dump hashs SHA1\n+ cracking offline\n(sans sel)", "retenu": False},
                {"id": "t3", "label": "Pivot vers Moodle\n(notes = données\nperso RGPD)", "retenu": False},
            ],
            "EXPLOITER": [
                {"id": "e1", "label": "Exfiltration\nbase RH complète\n(500 personnels)", "retenu": True},
                {"id": "e2", "label": "Exfiltration\nétudiants via\nLDAP", "retenu": True},
                {"id": "e3", "label": "Revente sur\nmarché noir", "retenu": True},
                {"id": "e4", "label": "Conservation hashs\npour usurpation\nfuture", "retenu": False},
            ],
        },
        "connexions": [
            # Chaîne retenue
            ("c1", "r1", True), ("r1", "t1", True), ("t1", "e1", True),
            ("t1", "e2", True), ("e1", "e3", True), ("e2", "e3", True),
            # Alternatives
            ("c2", "r3", False),  # énumération admin -> phishing ciblé
            ("c3", "r1", False),  # relation web/BDD identifiée -> SQLi
            ("r2", "t1", False),  # creds MITM -> BDD directe
            ("r3", "t1", False),
            ("t2", "e1", False),  # hashs craqués -> accès RH
            ("t3", "e2", False),  # pivot Moodle -> données étudiants
            ("e1", "e4", False),  # en exfiltrant on garde aussi les hashs
        ],
        "bsc": ["BS05 Web RH", "BS07 BDD RH", "BS04 LDAP", "BS01 Moodle"],
        "vulns": [
            "Injection SQL non corrigée dans le portail uc-web-rh",
            "uc-db-rh MariaDB exposée 0.0.0.0:3306, hashs en SHA1 sans sel",
            "HTTP en clair sur uc-web-rh (capture credentials triviale)",
            "Bind LDAP anonyme expose la liste complète des comptes",
            "Pas de détection d'exfiltration (logs locaux non centralisés)",
        ],
    },
    {
        "code": "SO4",
        "title": "Acteur étatique exfiltre le patrimoine scientifique",
        "ss_parent": "SS4",
        "sr": "SR-C Acteur étatique (APT)",
        "ov": "Exfiltrer les résultats de recherche sensibles",
        "er_target": "ER04",
        "gravity": "G3",
        "vraisemblance": "V2",
        "vraisemblance_label": "Vraisemblable",
        "phases": {
            "CONNAÎTRE": [
                {"id": "c1", "label": "Reconnaissance\nlongue durée\nlabos partenaires", "retenu": True},
                {"id": "c2", "label": "Identification\nchercheurs cibles\n(publications)", "retenu": True},
                {"id": "c3", "label": "OSINT UniCampus\n(site, conférences)", "retenu": False},
                {"id": "c4", "label": "Projets sensibles\n(ANR, dual-use,\nbrevets)", "retenu": False},
            ],
            "RENTRER": [
                {"id": "r1", "label": "Compromission\nlabo partenaire PA1\n(maillon faible)", "retenu": True},
                {"id": "r2", "label": "Spear-phishing\nchercheur\nUniCampus", "retenu": False},
                {"id": "r3", "label": "Attaque directe\nuc-calc-recherche\n(0-day APT)", "retenu": False},
                {"id": "r4", "label": "Insider via\ndoctorant thèse\npartagée", "retenu": False},
            ],
            "TROUVER": [
                {"id": "t1", "label": "Accès NFS/Samba\npartenaire (données\npartagées)", "retenu": True},
                {"id": "t2", "label": "Latéralisation\nVLAN UniCampus", "retenu": False},
                {"id": "t3", "label": "Accès Jupyter\nnotebooks\n(8888, sans auth)", "retenu": False},
                {"id": "t4", "label": "Lecture PostgreSQL\nlocal\n(127.0.0.1:5432)", "retenu": False},
            ],
            "EXPLOITER": [
                {"id": "e1", "label": "Exfiltration\nlente et discrète\n(low and slow)", "retenu": True},
                {"id": "e2", "label": "Persistance pour\ncollecte continue\n(implant)", "retenu": True},
                {"id": "e3", "label": "Modification subtile\nfaisant échouer\nla recherche", "retenu": False},
            ],
        },
        "connexions": [
            # Chaîne retenue
            ("c1", "r1", True), ("c2", "r1", True), ("r1", "t1", True),
            ("t1", "e1", True), ("e1", "e2", True),
            # Alternatives
            ("c3", "r1", False),
            ("c4", "r2", False),  # projets ciblés -> spear-phishing
            ("c4", "r3", False),  # projets ciblés -> 0-day
            ("r2", "t2", False),  # chercheur compromis -> latéral
            ("r3", "t3", False),  # accès direct calc -> Jupyter
            ("r4", "t1", False),  # doctorant -> partages NFS
            ("t2", "e1", False),
            ("t3", "e1", False),
            ("t4", "e1", False),
            ("e1", "e3", False),  # exfil + sabotage subtil
        ],
        "bsc": ["BS09 calc-recherche", "BS10 NFS recherche", "BS11 PostgreSQL recherche", "BS12 Postes recherche"],
        "vulns": [
            "NFS et Samba exposés sans authentification sur uc-calc-recherche",
            "Jupyter sans token ni mot de passe sur 0.0.0.0:8888",
            "Pas de cloisonnement entre VLAN UniCampus et infrastructure des partenaires",
            "Données scientifiques sensibles stockées en clair, sans classification",
            "Aucune supervision capable de détecter une exfiltration low-and-slow",
        ],
    },
    {
        "code": "SO5",
        "title": "Personnel mécontent détourne la paie",
        "ss_parent": "SS5",
        "sr": "SR-D Personnel mécontent / insider",
        "ov": "Détourner sa paie ou celle de collègues",
        "er_target": "ER05",
        "gravity": "G3",
        "vraisemblance": "V2",
        "vraisemblance_label": "Vraisemblable",
        "phases": {
            "CONNAÎTRE": [
                {"id": "c1", "label": "Connaissance\ninterne du SI RH\n(personnel actif/ex)", "retenu": True},
                {"id": "c2", "label": "Identification du\ncycle de paie\n(dates clés)", "retenu": False},
            ],
            "RENTRER": [
                {"id": "r1", "label": "Compte légitime\nactif", "retenu": True},
                {"id": "r2", "label": "Compte non révoqué\naprès départ", "retenu": False},
                {"id": "r3", "label": "Phishing collègue\nayant accès RH", "retenu": False},
            ],
            "TROUVER": [
                {"id": "t1", "label": "Navigation directe\nuc-web-rh\n(creds valides)", "retenu": True},
                {"id": "t2", "label": "Accès direct\nuc-db-rh\n(0.0.0.0:3306)", "retenu": False},
            ],
            "EXPLOITER": [
                {"id": "e1", "label": "Modification RIB\nde versement\n(détournement)", "retenu": True},
                {"id": "e2", "label": "Ajout de primes\nfictives\n(fraude perso)", "retenu": False},
                {"id": "e3", "label": "Modification du\nsalaire de base", "retenu": False},
            ],
        },
        "connexions": [
            # Chaîne retenue
            ("c1", "r1", True), ("r1", "t1", True), ("t1", "e1", True),
            # Alternatives
            ("c2", "r1", False),  # connaissance cycle -> timing l'attaque
            ("r2", "t1", False),
            ("r3", "t1", False),
            ("t2", "e1", False),  # accès BDD direct -> modif RIB
            ("t1", "e2", False),
            ("t1", "e3", False),
        ],
        "bsc": ["BS05 Web RH", "BS07 BDD RH"],
        "vulns": [
            "Pas de séparation des privilèges côté application RH (un seul rôle)",
            "Comptes non révoqués au départ (pas de processus IAM)",
            "Aucune validation à 4 yeux pour la modification de RIB / salaire",
            "Pas de journal d'audit applicatif des modifications RH",
        ],
    },
    {
        "code": "SO6",
        "title": "Personnel mécontent détruit par vengeance",
        "ss_parent": "SS6",
        "sr": "SR-D Personnel mécontent / insider",
        "ov": "Détruire les données critiques par vengeance",
        "er_target": "ER01",
        "gravity": "G3",
        "vraisemblance": "V2",
        "vraisemblance_label": "Vraisemblable",
        "phases": {
            "CONNAÎTRE": [
                {"id": "c1", "label": "Connaissance\ninterne du SI\n(personnel mécontent)", "retenu": True},
                {"id": "c2", "label": "Connaissance de\nl'absence de\nsauvegardes", "retenu": False},
            ],
            "RENTRER": [
                {"id": "r1", "label": "Compte légitime\nactif", "retenu": True},
                {"id": "r2", "label": "Compte non révoqué\naprès départ", "retenu": False},
                {"id": "r3", "label": "Compte VPN partagé\n(campus /\nunicampus2024)", "retenu": False},
            ],
            "TROUVER": [
                {"id": "t1", "label": "Accès direct\nserveurs (privilèges\nutilisateur)", "retenu": True},
                {"id": "t2", "label": "Élévation\nsudo NOPASSWD\n(uc-poste-dsi)", "retenu": False},
            ],
            "EXPLOITER": [
                {"id": "e1", "label": "Suppression données\ncritiques\n(RH, recherche)", "retenu": True},
                {"id": "e2", "label": "Chiffrement manuel\ndes fichiers\n(pas de récupération)", "retenu": False},
                {"id": "e3", "label": "Pas de sauvegardes\nimmuables ->\nirréversible", "retenu": True},
            ],
        },
        "connexions": [
            # Chaîne retenue
            ("c1", "r1", True), ("r1", "t1", True), ("t1", "e1", True), ("e1", "e3", True),
            # Alternatives
            ("c2", "r1", False),
            ("r2", "t1", False),
            ("r3", "t1", False),
            ("t2", "e1", False),
            ("t1", "e2", False),
        ],
        "bsc": ["BS05 Web RH", "BS07 BDD RH", "BS09 calc-recherche", "BS10 NFS recherche"],
        "vulns": [
            "Sudo NOPASSWD pour ubuntu sur toutes les VMs (élévation triviale)",
            "Compte VPN partagé jamais changé (présent dans email DSI exfiltrable)",
            "Aucune sauvegarde immuable hors-ligne : suppression = perte définitive",
            "Pas de contrôle d'accès granulaire sur les partages NFS recherche",
        ],
    },
]

# ============================================================
# GÉNÉRATION DES GRAPHES D'ATTAQUE
# ============================================================
def generate_attack_graph(so, output_path):
    """Génère un graphe d'attaque matplotlib pour un scénario opérationnel."""
    phases_order = ["CONNAÎTRE", "RENTRER", "TROUVER", "EXPLOITER"]
    phase_colors = ['#1F4E78', '#2E75B6', '#5B9BD5', '#9DC3E6']

    # Dimensions de la figure
    fig_width = 16
    fig_height = 9
    fig, ax = plt.subplots(figsize=(fig_width, fig_height), dpi=85)

    # Coordonnées des colonnes (x)
    col_xs = {phase: 1.5 + i * 4 for i, phase in enumerate(phases_order)}
    col_width = 3.0

    # Calculer les positions y pour chaque action
    box_width = 2.6
    box_height = 1.0
    y_top = 7.5
    y_bottom = 2.0

    positions = {}  # id -> (x, y)

    for phase in phases_order:
        actions = so["phases"][phase]
        n = len(actions)
        x = col_xs[phase]
        if n == 1:
            y_positions = [(y_top + y_bottom) / 2]
        else:
            y_positions = list(np.linspace(y_top - box_height/2,
                                            y_bottom + box_height/2, n))
        for i, action in enumerate(actions):
            positions[action["id"]] = (x, y_positions[i])

    # En-têtes de phases (colonnes)
    for i, phase in enumerate(phases_order):
        x = col_xs[phase]
        ax.add_patch(FancyBboxPatch((x - col_width/2, 8.4), col_width, 0.7,
                                     boxstyle="round,pad=0.05",
                                     facecolor=phase_colors[i],
                                     edgecolor='none', zorder=3))
        ax.text(x, 8.75, phase, ha='center', va='center',
                fontsize=13, fontweight='bold', color='white', zorder=4)
        # Bandeau de fond pour chaque colonne
        ax.add_patch(plt.Rectangle((x - col_width/2, 1), col_width, 7.3,
                                    facecolor='#F4F4F4', edgecolor='none',
                                    alpha=0.5, zorder=0))

    # Dessiner les flèches (connexions)
    # On commence par les non-retenues (gris), puis les retenues (rouge) par-dessus
    connexions_sorted = sorted(so["connexions"], key=lambda x: x[2])

    for from_id, to_id, retenu in connexions_sorted:
        if from_id not in positions or to_id not in positions:
            continue
        x1, y1 = positions[from_id]
        x2, y2 = positions[to_id]
        # Partir du bord droit de la boîte source, arriver au bord gauche de la boîte cible
        x1_edge = x1 + box_width / 2
        x2_edge = x2 - box_width / 2
        if retenu:
            color = '#C00000'
            lw = 2.5
            alpha = 0.95
            z = 5
            arrowstyle = '-|>,head_width=0.4,head_length=0.5'
        else:
            color = '#AAAAAA'
            lw = 1.0
            alpha = 0.55
            z = 2
            arrowstyle = '-|>,head_width=0.25,head_length=0.35'

        arrow = FancyArrowPatch((x1_edge, y1), (x2_edge, y2),
                                arrowstyle=arrowstyle,
                                color=color,
                                linewidth=lw, alpha=alpha,
                                zorder=z,
                                connectionstyle="arc3,rad=0.05")
        ax.add_patch(arrow)

    # Dessiner les boîtes (par-dessus les flèches)
    for phase in phases_order:
        for action in so["phases"][phase]:
            x, y = positions[action["id"]]
            retenu = action["retenu"]
            face_color = '#FFE6E6' if retenu else 'white'
            edge_color = '#C00000' if retenu else '#777777'
            edge_lw = 2.0 if retenu else 1.0
            text_weight = 'bold' if retenu else 'normal'

            box = FancyBboxPatch((x - box_width/2, y - box_height/2),
                                  box_width, box_height,
                                  boxstyle="round,pad=0.05,rounding_size=0.1",
                                  facecolor=face_color,
                                  edgecolor=edge_color,
                                  linewidth=edge_lw, zorder=6)
            ax.add_patch(box)
            ax.text(x, y, action["label"],
                    ha='center', va='center',
                    fontsize=9, fontweight=text_weight, zorder=7)

    # Titre
    fig.suptitle(f"{so['code']} — {so['title']}",
                 fontsize=14, fontweight='bold', y=0.98)

    # Sous-titre : scénario stratégique parent + SR + OV + gravité + vraisemblance
    subtitle = (f"Scénario stratégique parent : {so['ss_parent']}   |   "
                f"Source de risque : {so['sr']}   |   "
                f"Objectif : {so['ov']}")
    fig.text(0.5, 0.93, subtitle, ha='center', fontsize=10, color='#333333')

    # Pied : gravité et vraisemblance
    footer = (f"Gravité héritée : {so['gravity']}   |   "
              f"Vraisemblance globale : {so['vraisemblance']} — {so['vraisemblance_label']}   |   "
              f"ER ciblé(s) : {so['er_target']}")
    fig.text(0.5, 0.03, footer, ha='center', fontsize=9.5,
             color='#1F4E78', fontweight='bold')

    # Légende des flèches
    legend_elements = [
        plt.Line2D([0], [0], color='#C00000', lw=2.5, label='Chemin retenu pour l\'analyse'),
        plt.Line2D([0], [0], color='#AAAAAA', lw=1.0, alpha=0.7, label='Chemin alternatif possible'),
    ]
    ax.legend(handles=legend_elements, loc='upper right',
              bbox_to_anchor=(0.98, 0.92), fontsize=9, frameon=True,
              facecolor='white', edgecolor='gray')

    ax.set_xlim(-0.3, 17)
    ax.set_ylim(0.5, 9.5)
    ax.axis('off')

    plt.subplots_adjust(left=0.01, right=0.99, top=0.91, bottom=0.06)
    plt.savefig(output_path, dpi=85, bbox_inches='tight', facecolor='white')
    plt.close()


# Générer les 6 graphes
graph_paths = {}
for so in so_data:
    path = os.path.join(GRAPH_DIR, f"{so['code']}.png")
    generate_attack_graph(so, path)
    graph_paths[so['code']] = path
    print(f"Graphe {so['code']} généré : {path}")


# ============================================================
# CONSTRUCTION DU CLASSEUR
# ============================================================
wb = load_workbook(SRC)

# Ce script ne reconstruit QUE la feuille A4.1 (les graphes d'attaque).
# A4.0 et A4.2 sont laissées intactes : leur contenu est identique entre v1
# et v2 (différences cosmétiques uniquement).
if "A4.1 Graphes d'attaque" in wb.sheetnames:
    del wb["A4.1 Graphes d'attaque"]

# Insertion juste avant A4.2 (qui existe déjà) si présente, sinon avant A5.
if "A4.2 Synthèse vraisemblance" in wb.sheetnames:
    a4_1_pos = wb.sheetnames.index("A4.2 Synthèse vraisemblance")
else:
    a4_1_pos = next(i for i, s in enumerate(wb.sheetnames) if s.startswith("A5"))


# ============================================================
# A4.1 — GRAPHES D'ATTAQUE
# ============================================================
ws = wb.create_sheet("A4.1 Graphes d'attaque", a4_1_pos)
set_widths(ws, [4, 25, 25, 25, 25, 25, 25, 25, 25])

add_title(ws, 9, "A4.1 - Scénarios opérationnels et graphes d'attaque")
add_note(ws, 4, 9,
    "Pour chacun des 6 scénarios stratégiques retenus en A3.3, un scénario opérationnel (SO) détaille les "
    "procédures techniques susceptibles d'être mises en œuvre par la source de risque. Chaque scénario est "
    "structuré selon la séquence d'attaque type CONNAÎTRE → RENTRER → TROUVER → EXPLOITER (slide 44 du cours, "
    "p.62-63 du guide ANSSI). Le chemin retenu pour l'analyse est mis en évidence par des flèches rouges ; "
    "les chemins alternatifs possibles sont représentés en gris. La méthode de cotation de la vraisemblance "
    "utilisée est l'estimation globale directe (méthode expresse ANSSI, p.65). Les biens supports critiques (BSC) "
    "et les vulnérabilités spécifiques exploitées sont listés sous chaque graphe.",
    height=130)

# Ligne courante (on incrémente au fur et à mesure)
current_row = 6

for i, so in enumerate(so_data):
    # Section header pour le SO
    add_section(ws, current_row, 9,
                f"{so['code']} - {so['title']} (parent {so['ss_parent']}, gravité {so['gravity']}, vraisemblance {so['vraisemblance']})",
                height=26)
    current_row += 1

    # Embarquer le graphe d'attaque
    img = XLImage(graph_paths[so['code']])
    # Image native 16x9 inches at 85 dpi = 1360x765 px ; on garde tel quel
    ws.add_image(img, f"A{current_row}")

    # Réserver de l'espace pour l'image (environ 28 lignes pour ~750 px)
    image_rows = 30
    current_row += image_rows

    # Tableau des biens supports critiques et vulnérabilités
    bsc_row = current_row
    ws.cell(row=bsc_row, column=1, value="")
    ws.cell(row=bsc_row, column=2, value="Biens supports critiques (BSC)")
    ws.cell(row=bsc_row, column=3, value="Vulnérabilités spécifiques exploitées")
    ws.merge_cells(start_row=bsc_row, end_row=bsc_row, start_column=3, end_column=9)
    for col in (2, 3):
        c = ws.cell(row=bsc_row, column=col)
        c.font = FONT_HEADER
        c.fill = FILL_HEADER
        c.alignment = ALIGN_WRAP_CENTER
        c.border = BORDER_ALL
    ws.row_dimensions[bsc_row].height = 24

    current_row += 1
    content_row = current_row
    ws.cell(row=content_row, column=2, value="\n".join(f"• {b}" for b in so["bsc"]))
    ws.cell(row=content_row, column=3, value="\n".join(f"• {v}" for v in so["vulns"]))
    ws.merge_cells(start_row=content_row, end_row=content_row, start_column=3, end_column=9)
    for col in (2, 3):
        c = ws.cell(row=content_row, column=col)
        c.font = FONT_BODY
        c.alignment = ALIGN_WRAP
        c.border = BORDER_ALL
    ws.row_dimensions[content_row].height = max(80, 16 * max(len(so["bsc"]), len(so["vulns"])))

    current_row += 2  # marge entre SOs

ws.sheet_view.showGridLines = False
ws.freeze_panes = "A4"
print("A4.1 OK")


wb.save(DST)
print(f"\nFichier sauvegardé : {DST}")
print(f"Feuilles : {wb.sheetnames}")
