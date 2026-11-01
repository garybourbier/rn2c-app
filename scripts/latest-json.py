#!/usr/bin/env python3
"""Écrit releases/latest.json d'après une release publiée.

Les applis de bureau lisent ce fichier sur master pour proposer la mise à jour : elles comparent
« version » à leur propre numéro, montrent « notes », et un lien par clé de « downloads » qu'elles
connaissent. Les clés des fichiers x86_64 sont celles que lisent les versions déjà installées :
elles ne changent pas de nom.

    scripts/latest-json.py <release.json> <releases/latest.json>

<release.json> est la réponse de l'API GitHub pour la release (gh api …/releases/tags/vX.Y.Z).
Une release plus ancienne que celle du fichier ne le réécrit pas : latest.json ne recule jamais.
"""
import json
import re
import sys

CLES = [
    ("linux-appimage", r"_amd64\.AppImage$"),
    ("linux-appimage-arm64", r"_aarch64\.AppImage$"),
    ("linux-deb", r"_amd64\.deb$"),
    ("linux-deb-arm64", r"_arm64\.deb$"),
    ("linux-rpm", r"\.x86_64\.rpm$"),
    ("linux-rpm-arm64", r"\.aarch64\.rpm$"),
    ("windows-nsis", r"_x64-setup\.exe$"),
    ("windows-msi", r"_x64_[A-Za-z-]+\.msi$"),
    ("windows-portable", r"-portable-win64\.zip$"),
    ("macos-dmg", r"_universal\.dmg$"),
    ("android-apk", r"-signed\.apk$"),
]


def numero(v):
    return tuple(int(x) for x in v.split("."))


def notes(corps):
    """Le premier paragraphe des notes de la release, sans sa mise en forme."""
    premier = (corps or "").strip().split("\n\n")[0]
    return re.sub(r"[*_`#>]", "", " ".join(premier.split()))[:300]


def main(chemin_release, chemin_latest):
    release = json.load(open(chemin_release, encoding="utf-8"))
    version = release["tag_name"].removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit(f"✗ étiquette {release['tag_name']} : pas de la forme vX.Y.Z")
    if release.get("draft") or release.get("prerelease"):
        sys.exit("✗ la release n'est pas publiée, ou c'est une préversion")

    try:
        actuelle = json.load(open(chemin_latest, encoding="utf-8"))["version"]
    except FileNotFoundError:
        actuelle = "0.0.0"
    if numero(version) <= numero(actuelle):
        print(f"latest.json porte déjà {actuelle} : {version} ne le remplace pas")
        return

    liens = {}
    for cle, motif in CLES:
        trouves = [a for a in release["assets"] if re.search(motif, a["name"])]
        if len(trouves) > 1:
            sys.exit(f"✗ {cle} : {len(trouves)} fichiers répondent ({', '.join(a['name'] for a in trouves)})")
        if trouves:
            liens[cle] = trouves[0]["browser_download_url"]
        else:
            print(f"⚠️ {cle} : aucun fichier de la release ne lui correspond", file=sys.stderr)

    contenu = {
        "version": version,
        "pub_date": release["published_at"],
        "notes": notes(release.get("body")),
        "downloads": liens,
    }
    with open(chemin_latest, "w", encoding="utf-8") as f:
        json.dump(contenu, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"latest.json : {actuelle} → {version}, {len(liens)} fichier(s)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
