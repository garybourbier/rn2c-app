#!/usr/bin/env python3
"""Écrit releases/latest.json d'après une release publiée.

Les applis de bureau à partir de la 0.8.1 lisent ce fichier sur master pour proposer la mise à jour :
elles comparent « version » à leur propre numéro, montrent « notes », et un lien par clé de
« downloads » qu'elles connaissent. Les 0.2.x le cherchent sur une branche main qui n'existe pas :
elles ne voient aucune mise à jour.

    scripts/latest-json.py <release.json> <releases/latest.json>

<release.json> est la réponse de l'API GitHub pour la release (gh api …/releases/tags/vX.Y.Z).

Le fichier n'est écrit que si la release porte exactement les fichiers de packaging/fichiers.txt,
chacun à l'adresse de la release, ceux de bureau déposés par la CI et l'APK par un compte de
packaging/mainteneurs.txt, et si ses notes disent ce qui change. Sinon le script échoue et
n'écrit rien. Une release plus ancienne que celle du fichier ne le réécrit pas ; une release du
même numéro le réécrit, ce qui répare une publication incomplète.
"""
import json
import os
import re
import subprocess
import sys
import unicodedata

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROBOT = "github-actions[bot]"
A_ECRIRE = "À écrire avant de publier"


def lignes(chemin):
    with open(os.path.join(RACINE, chemin), encoding="utf-8") as f:
        return [l.split() for l in f if l.strip() and not l.lstrip().startswith("#")]


def numero(v):
    return tuple(int(x) for x in v.split("."))


def notes(corps):
    """Le premier paragraphe des notes, sans mise en forme ni caractère de contrôle."""
    corps = (corps or "").replace("\r\n", "\n").replace("\r", "\n")
    corps = "".join(c for c in corps if c == "\n" or unicodedata.category(c) not in ("Cc", "Cf"))
    premier = corps.strip().split("\n\n")[0]
    return re.sub(r"[*_`#>]", "", " ".join(premier.split()))[:300]


def main(chemin_release, chemin_latest):
    release = json.load(open(chemin_release, encoding="utf-8"))
    etiquette = release["tag_name"]
    version = etiquette[1:] if etiquette.startswith("v") else ""
    forme = subprocess.run([os.path.join(RACINE, "scripts", "version.sh"), "--forme", version])
    if forme.returncode != 0:
        sys.exit(f"✗ étiquette {etiquette} : pas de la forme vX.Y.Z")
    if release.get("draft") or release.get("prerelease"):
        sys.exit("✗ la release n'est pas publiée, ou c'est une préversion")

    try:
        actuelle = json.load(open(chemin_latest, encoding="utf-8"))["version"]
    except FileNotFoundError:
        actuelle = "0.0.0"
    if numero(version) < numero(actuelle):
        print(f"latest.json porte {actuelle} : {version} ne le remplace pas")
        return

    texte = notes(release.get("body"))
    if not texte or A_ECRIRE in texte:
        sys.exit("✗ les notes de la release ne disent pas encore ce qui change")

    lien = re.fullmatch(r"https://github\.com/([^/]+/[^/]+)/releases/tag/.+", release.get("html_url", ""))
    if not lien:
        sys.exit(f"✗ adresse de la release inattendue : {release.get('html_url')}")
    depot = lien.group(1)
    mainteneurs = {l[0].lower() for l in lignes("packaging/mainteneurs.txt")}
    attendus = {modele.replace("{v}", version): (cle, artefact) for cle, artefact, modele in lignes("packaging/fichiers.txt")}
    joints = {a["name"]: a for a in release["assets"]}

    fautes = []
    for nom in sorted(set(attendus) - set(joints)):
        fautes.append(f"manque : {nom}")
    for nom in sorted(set(joints) - set(attendus)):
        fautes.append(f"en trop : {nom}")
    liens = {}
    for nom, (cle, artefact) in attendus.items():
        fichier = joints.get(nom)
        if fichier is None:
            continue
        auteur = (fichier.get("uploader") or {}).get("login", "")
        if artefact == "android":
            if auteur.lower() not in mainteneurs:
                fautes.append(f"{nom} : déposé par « {auteur} », qui n'est pas dans packaging/mainteneurs.txt")
        elif auteur != ROBOT:
            fautes.append(f"{nom} : déposé par « {auteur} » et non par la CI")
        adresse = f"https://github.com/{depot}/releases/download/{etiquette}/{nom}"
        if fichier["browser_download_url"] != adresse:
            fautes.append(f"{nom} : adresse inattendue {fichier['browser_download_url']}")
        liens[cle] = adresse
    if fautes:
        sys.exit("✗ latest.json n'est pas écrit :\n  " + "\n  ".join(fautes))

    contenu = {
        "version": version,
        "pub_date": release["published_at"],
        "notes": texte,
        "downloads": dict(sorted(liens.items())),
    }
    os.makedirs(os.path.dirname(os.path.abspath(chemin_latest)), exist_ok=True)
    with open(chemin_latest, "w", encoding="utf-8") as f:
        json.dump(contenu, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"latest.json : {actuelle} → {version}, {len(liens)} fichiers")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
