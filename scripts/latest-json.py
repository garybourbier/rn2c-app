#!/usr/bin/env python3
"""Écrit releases/latest.json d'après une release publiée.

Les applis de bureau à partir de la 0.8.1 lisent ce fichier sur master pour proposer la mise à jour :
elles comparent « version » à leur propre numéro, montrent « notes », et un lien par clé de
« downloads » qu'elles connaissent. Les 0.2.x le cherchent sur une branche main qui n'existe pas :
elles ne voient aucune mise à jour.

    scripts/latest-json.py <release.json> <releases/latest.json> <propriétaire/dépôt>

<release.json> est la réponse de l'API GitHub pour la release (gh api …/releases/tags/vX.Y.Z).
Les listes lues sont celles de l'arbre où vit ce script : à la publication, l'étiquette.

Le fichier n'est écrit que si la release est celle du dépôt donné, porte exactement les fichiers de
packaging/fichiers.txt, chacun à l'adresse de la release, ceux de bureau déposés par la CI et l'APK
par un compte de packaging/mainteneurs.txt, et si ses notes nomment chaque fichier et disent, avant
leur premier titre, ce qui change. Sinon le script échoue et n'écrit rien. Le fichier présent
n'est pas lu : le workflow passe la plus haute release publiée, et le script la recopie même
quand elle est plus basse que celle du fichier, ce qui répare une release retirée comme une
publication incomplète. Ce que le workflow vérifie en plus (provenance des fichiers que la CI
joint, certificat, numéro et contenu de l'APK) est dans latest-json.yml.
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


def nettoyer(corps):
    corps = (corps or "").replace("\r\n", "\n").replace("\r", "\n")
    return "".join(c for c in corps if c == "\n" or unicodedata.category(c) not in ("Cc", "Cf"))


def notes(corps):
    """Le texte des notes avant leur premier titre, sans mise en forme : ce que l'écran montre."""
    avant = re.split(r"^#", nettoyer(corps), maxsplit=1, flags=re.M)[0]
    return re.sub(r"[*_`>]", "", " ".join(avant.split()))


def main(chemin_release, chemin_latest, depot):
    release = json.load(open(chemin_release, encoding="utf-8"))
    etiquette = release["tag_name"]
    version = etiquette[1:] if etiquette.startswith("v") else ""
    forme = subprocess.run([os.path.join(RACINE, "scripts", "version.sh"), "--forme", version])
    if forme.returncode != 0:
        sys.exit(f"✗ étiquette {etiquette} : pas de la forme vX.Y.Z")
    if release.get("draft") or release.get("prerelease"):
        sys.exit("✗ la release n'est pas publiée, ou c'est une préversion")

    texte = notes(release.get("body"))
    if not texte or A_ECRIRE in texte:
        sys.exit("✗ les notes ne disent pas, avant leur premier titre, ce que cette version change")

    if release.get("html_url") != f"https://github.com/{depot}/releases/tag/{etiquette}":
        sys.exit(f"✗ la release n'est pas celle de {depot} : {release.get('html_url')}")
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
    corps = nettoyer(release.get("body"))
    for nom in sorted(attendus):
        if nom not in corps:
            fautes.append(f"les notes ne nomment pas {nom}")
    if fautes:
        sys.exit("✗ latest.json n'est pas écrit :\n  " + "\n  ".join(fautes))

    contenu = {
        "version": version,
        "pub_date": release["published_at"],
        "notes": texte[:300],
        "downloads": dict(sorted(liens.items())),
    }
    os.makedirs(os.path.dirname(os.path.abspath(chemin_latest)), exist_ok=True)
    with open(chemin_latest, "w", encoding="utf-8") as f:
        json.dump(contenu, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"latest.json : {version}, {len(liens)} fichiers")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
