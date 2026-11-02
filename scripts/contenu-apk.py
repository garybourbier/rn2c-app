#!/usr/bin/env python3
"""Le relevé du contenu d'un APK : l'empreinte sha256 de chaque entrée, hors fichiers de signature.

    scripts/contenu-apk.py <apk>              écrit le relevé sur la sortie standard
    scripts/contenu-apk.py <apk> <relevé>     compare l'APK au relevé, et échoue s'ils diffèrent

Signer un APK n'ajoute ou ne remplace que des fichiers de signature (META-INF/MANIFEST.MF,
META-INF/*.SF, *.RSA, *.DSA, *.EC, META-INF/SIG-*) et un bloc hors des entrées (schémas v2 et
suivants) : toute autre entrée de l'APK signé est celle que la CI a construite. La CI joint à la
release le relevé de l'APK non signé ; la publication compare l'APK signé à ce relevé.
Un nom d'entrée en double fait échouer : Android et ce relevé pourraient ne pas lire la même.
"""
import collections
import hashlib
import re
import sys
import zipfile

SIGNATURE = re.compile(r"^META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA|EC)|SIG-[^/]*)$")


def releve(chemin):
    with zipfile.ZipFile(chemin) as apk:
        compte = collections.Counter(e.filename for e in apk.infolist())
        doubles = sorted(n for n, k in compte.items() if k > 1)
        if doubles:
            sys.exit(f"✗ {chemin} : entrée(s) en double : {', '.join(doubles)}")
        lignes = []
        for entree in apk.infolist():
            if entree.is_dir() or SIGNATURE.match(entree.filename):
                continue
            lignes.append(f"{hashlib.sha256(apk.read(entree)).hexdigest()}  {entree.filename}")
    if not lignes:
        sys.exit(f"✗ {chemin} : aucune entrée hors signature")
    return sorted(lignes, key=lambda l: l.split("  ", 1)[1])


def main(args):
    if len(args) == 1:
        print("\n".join(releve(args[0])))
        return
    if len(args) != 2:
        sys.exit(__doc__)
    apk = dict(reversed(l.split("  ", 1)) for l in releve(args[0]))
    with open(args[1], encoding="utf-8") as f:
        attendu = dict(reversed(l.rstrip("\r\n").split("  ", 1)) for l in f if l.strip())
    fautes = [f"manque : {n}" for n in sorted(set(attendu) - set(apk))]
    fautes += [f"en trop : {n}" for n in sorted(set(apk) - set(attendu))]
    fautes += [f"diffère : {n}" for n in sorted(set(apk) & set(attendu)) if apk[n] != attendu[n]]
    if fautes:
        sys.exit(f"✗ {args[0]} n'est pas l'APK du relevé {args[1]} :\n  " + "\n  ".join(fautes))
    print(f"✓ {args[0]} : {len(apk)} entrées, identiques au relevé hors signature")


if __name__ == "__main__":
    main(sys.argv[1:])
