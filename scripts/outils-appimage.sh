#!/usr/bin/env bash
# Les outils d'une AppImage, déposés d'avance et vérifiés, d'après packaging/outils-appimage.txt.
#
#   scripts/outils-appimage.sh deposer <architecture>
#       télécharge chaque outil de l'architecture dans le dossier où le bundler les cherche, vérifie
#       son empreinte, puis écrit sur la sortie standard le chemin du runtime, à passer en
#       LDAI_RUNTIME_FILE à la construction
#   scripts/outils-appimage.sh controler <architecture>
#       après la construction : le dossier ne porte que les outils déposés et les deux scripts que
#       le bundler embarque, et l'AppImage produite commence par le runtime déposé
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
  if ! cmp -s -n "$(wc -c < "$runtime")" "$runtime" "$appimage"; then
    echo "✗ $(basename "$appimage") ne commence pas par le runtime déposé" >&2
    exit 1
  fi
  echo "✓ $(basename "$appimage") commence par le runtime déposé"
}

case "${1:-}" in
  deposer) deposer "${2:?architecture}" ;;
  controler) controler "${2:?architecture}" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
