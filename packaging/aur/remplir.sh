#!/usr/bin/env bash
# Remplit les gabarits du PKGBUILD et du .SRCINFO de rn2c-bin pour une version : le numéro, et la
# somme sha256 de chacun des deux .deb que la release publie.
#
#   packaging/aur/remplir.sh X.Y.Z <dossier où chercher les .deb> <dossier de sortie>
set -euo pipefail
numero=$1 debs=$2 sortie=$3
ici=$(cd "$(dirname "$0")" && pwd)

# Le nom compte autant que le contenu : le PKGBUILD télécharge la release sous ce nom exact, celui
# de packaging/fichiers.txt.
somme() {
  local nom f n
  nom=$("$ici/../../scripts/fichiers.sh" nom "$numero" "$1")
  f=$(find "$debs" -type f -name "$nom")
  n=$(printf '%s' "$f" | grep -c . || true)
  if [ "$n" -ne 1 ]; then
    echo "✗ $nom : $n fichier(s) sous $debs au lieu d'un" >&2
    exit 1
  fi
  sha256sum "$f" | cut -d' ' -f1
}

x86_64=$(somme linux-deb)
aarch64=$(somme linux-deb-arm64)
mkdir -p "$sortie"
sed -e "s/@PKGVER@/$numero/" -e "s/@SHA256_X86_64@/$x86_64/" -e "s/@SHA256_AARCH64@/$aarch64/" \
  "$ici/PKGBUILD" > "$sortie/PKGBUILD"
grep -v '^#' "$ici/SRCINFO" \
  | sed -e "s/@PKGVER@/$numero/g" -e "s/@SHA256_X86_64@/$x86_64/" -e "s/@SHA256_AARCH64@/$aarch64/" \
  > "$sortie/.SRCINFO"
if grep -n '@[A-Z0-9_]*@' "$sortie/PKGBUILD" "$sortie/.SRCINFO"; then
  echo "✗ des champs du gabarit restent à remplir" >&2
  exit 1
fi
for cle in linux-deb linux-deb-arm64; do
  nom=$("$ici/../../scripts/fichiers.sh" nom "$numero" "$cle")
  if ! sed "s/\${pkgver}/$numero/g" "$sortie/PKGBUILD" | grep -qF "/v$numero/$nom\""; then
    echo "✗ le PKGBUILD ne télécharge pas $nom, le nom de packaging/fichiers.txt" >&2
    exit 1
  fi
  if ! grep -qF "/v$numero/$nom" "$sortie/.SRCINFO"; then
    echo "✗ le .SRCINFO ne nomme pas $nom, le nom de packaging/fichiers.txt" >&2
    exit 1
  fi
done
echo "PKGBUILD et .SRCINFO $numero : x86_64 $x86_64 · aarch64 $aarch64"
