#!/usr/bin/env bash
# Les outils d'une AppImage, déposés d'avance et vérifiés, d'après packaging/outils-appimage.txt.
#
#   scripts/outils-appimage.sh deposer <architecture>
#       télécharge chaque outil de l'architecture dans le dossier où le bundler les cherche, vérifie
#       son empreinte, puis écrit sur la sortie standard le chemin du runtime, à passer en
#       LDAI_RUNTIME_FILE à la construction
#   scripts/outils-appimage.sh controler <architecture>
#       après la construction : le dossier ne porte que les outils déposés et les deux scripts que
#       le bundler embarque, et l'AppImage produite commence par le runtime déposé, hors des quatre
#       sections que l'outil d'assemblage remplit (.digest_md5, .upd_info, .sha256_sig, .sig_key)
#
# <architecture> : x86_64 ou aarch64, ce que rend « uname -m » sur les machines de la CI.
set -euo pipefail
cd "$(dirname "$0")/.."
LISTE=packaging/outils-appimage.txt
# Le bundler écrit ces deux scripts depuis son propre binaire : rien n'est téléchargé pour eux.
EMBARQUES=$'linuxdeploy-plugin-gstreamer.sh\nlinuxdeploy-plugin-gtk.sh'
# Le dossier d'outils du bundler : dirs::cache_dir() suivi de « tauri ».
DOSSIER=${XDG_CACHE_HOME:-$HOME/.cache}/tauri

outils() {
  local arch=$1 contenu
  contenu=$(tr -d '\r' < "$LISTE" | grep -vE '^[[:space:]]*(#|$)' | awk -v a="$arch" '$1 == a' || true)
  if [ -z "$contenu" ]; then
    echo "✗ $LISTE : aucun outil pour l'architecture « $arch »" >&2
    exit 1
  fi
  printf '%s\n' "$contenu"
}

deposer() {
  local arch=$1 liste a nom somme adresse reste runtime=''
  liste=$(outils "$arch")
  mkdir -p "$DOSSIER"
  if [ -n "$(ls -A "$DOSSIER")" ]; then
    echo "✗ $DOSSIER porte déjà des fichiers : le bundler les prendrait sans vérification" >&2
    exit 1
  fi
  while read -r a nom somme adresse reste; do
    if [ -z "$adresse" ] || [ -n "$reste" ] || ! printf '%s' "$somme" | grep -qE '^[0-9a-f]{64}$'; then
      echo "✗ $LISTE : ligne « $a $nom » mal formée" >&2
      exit 1
    fi
    curl -fsSL --proto '=https' --tlsv1.2 -o "$DOSSIER/$nom.part" "$adresse"
    if ! printf '%s  %s\n' "$somme" "$DOSSIER/$nom.part" | sha256sum -c --quiet - >&2; then
      echo "✗ $nom : l'empreinte ne correspond pas à $LISTE" >&2
      rm -f "$DOSSIER/$nom.part"
      exit 1
    fi
    mv "$DOSSIER/$nom.part" "$DOSSIER/$nom"
    chmod +x "$DOSSIER/$nom"
    echo "✓ $nom" >&2
    case "$nom" in runtime-*) runtime="$DOSSIER/$nom" ;; esac
  done <<< "$liste"
  if [ -z "$runtime" ]; then
    echo "✗ $LISTE : aucun runtime pour l'architecture « $arch »" >&2
    exit 1
  fi
  printf '%s\n' "$runtime"
}

controler() {
  local arch=$1 liste attendus presents runtime appimage n
  liste=$(outils "$arch")
  attendus=$( (printf '%s\n' "$liste" | awk '{print $2}'; printf '%s\n' "$EMBARQUES") | sort)
  presents=$(cd "$DOSSIER" && find . -mindepth 1 | sed 's|^\./||' | sort)
  if [ "$attendus" != "$presents" ]; then
    echo "✗ $DOSSIER ne porte pas exactement les outils déposés : le bundler a téléchargé ou laissé autre chose" >&2
    diff <(printf '%s\n' "$attendus") <(printf '%s\n' "$presents") | sed -n 's/^< /  manque : /p; s/^> /  en trop : /p' >&2
    exit 1
  fi
  echo "✓ $DOSSIER : les outils déposés, rien d'autre"
  runtime="$DOSSIER/$(printf '%s\n' "$liste" | awk '$2 ~ /^runtime-/ {print $2}')"
  appimage=$(find src-tauri/target -path '*/bundle/appimage/*' -type f -name '*.AppImage' 2>/dev/null)
  n=$(printf '%s' "$appimage" | grep -c . || true)
  if [ "$n" -ne 1 ]; then
    echo "✗ $n AppImage produite(s) au lieu d'une" >&2
    exit 1
  fi
  python3 -I - "$runtime" "$appimage" <<'PY'
import struct, sys
# Sections que l'outil d'assemblage écrit dans le runtime qu'il copie : vides dans le runtime
# publié, remplies dans l'AppImage (empreinte, informations de mise à jour, signature).
RESERVEES = {b".digest_md5", b".upd_info", b".sha256_sig", b".sig_key"}
runtime, appimage = (open(f, "rb").read() for f in sys.argv[1:3])
nom = sys.argv[2].rsplit("/", 1)[-1]
if runtime[:6] != b"\x7fELF\x02\x01":
    sys.exit(f"✗ {sys.argv[1]} : pas un ELF 64 bits petit-boutiste")
shoff, = struct.unpack_from("<Q", runtime, 0x28)
taille_entete, nombre, index_noms = struct.unpack_from("<HHH", runtime, 0x3A)
entetes = [struct.unpack_from("<IIQQQQ", runtime, shoff + i * taille_entete) for i in range(nombre)]
noms = entetes[index_noms][4]
tete = bytearray(appimage[:len(runtime)])
masquees = 0
for e in entetes:
    debut = noms + e[0]
    if runtime[debut:runtime.index(b"\0", debut)] in RESERVEES:
        tete[e[4]:e[4] + e[5]] = runtime[e[4]:e[4] + e[5]]
        masquees += 1
if masquees != len(RESERVEES):
    sys.exit(f"✗ le runtime porte {masquees} des {len(RESERVEES)} sections attendues")
if bytes(tete) != runtime:
    sys.exit(f"✗ {nom} ne commence pas par le runtime déposé")
print(f"✓ {nom} commence par le runtime déposé, hors de ses {masquees} sections remplies à l'assemblage")
PY
}

case "${1:-}" in
  deposer) deposer "${2:?architecture}" ;;
  controler) controler "${2:?architecture}" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
