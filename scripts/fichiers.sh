#!/usr/bin/env bash
# Les noms des fichiers d'une release, lus dans packaging/fichiers.txt.
#
#   scripts/fichiers.sh noms <numéro> [artefact]           les noms attendus, tous ou ceux d'un artefact
#   scripts/fichiers.sh nom <numéro> <clé>                 le nom d'une clé
#   scripts/fichiers.sh rassembler <artefact> <numéro> <sortie>
#                       copie dans <sortie> chaque fichier de l'artefact, trouvé une fois et une seule
#                       sous src-tauri/target/…/bundle/ ou à la racine
#   scripts/fichiers.sh controler <numéro> <dossier> <artefact>…
#                       le dossier porte exactement les fichiers de ces artefacts, rien de plus
#
# Écrit pour le bash 3.2 de macOS : ni mapfile, ni tableau associatif.
set -euo pipefail
cd "$(dirname "$0")/.."
LISTE=packaging/fichiers.txt

lignes() {
  grep -vE '^[[:space:]]*(#|$)' "$LISTE"
}

noms() {
  local v=$1 filtre=${2:-} cle artefact modele
  while read -r cle artefact modele; do
    if [ -z "$filtre" ] || [ "$artefact" = "$filtre" ]; then
      printf '%s\n' "${modele//\{v\}/$v}"
    fi
  done < <(lignes)
}

nom() {
  local v=$1 voulue=$2 cle artefact modele n=0 trouve=
  while read -r cle artefact modele; do
    if [ "$cle" = "$voulue" ]; then n=$((n + 1)); trouve=${modele//\{v\}/$v}; fi
  done < <(lignes)
  if [ "$n" -ne 1 ]; then
    echo "✗ clé $voulue : $n ligne(s) dans $LISTE au lieu d'une" >&2
    exit 1
  fi
  printf '%s\n' "$trouve"
}

rassembler() {
  local artefact=$1 v=$2 sortie=$3 nom n manque=0 attendus
  attendus=$(noms "$v" "$artefact")
  if [ -z "$attendus" ]; then
    echo "✗ artefact $artefact : aucun fichier dans $LISTE" >&2
    exit 1
  fi
  mkdir -p "$sortie"
  while read -r nom; do
    n=$( { find src-tauri/target -path '*/bundle/*' -type f -name "$nom" 2>/dev/null; [ -f "$nom" ] && echo "./$nom"; } | grep -c . || true)
    if [ "$n" -ne 1 ]; then
      echo "✗ $nom : $n fichier(s) produit(s) au lieu d'un" >&2
      manque=1
      continue
    fi
    cp "$( { find src-tauri/target -path '*/bundle/*' -type f -name "$nom" 2>/dev/null; [ -f "$nom" ] && echo "./$nom"; } )" "$sortie/"
    echo "✓ $nom"
  done <<< "$attendus"
  exit $manque
}

controler() {
  local v=$1 dossier=$2 attendus presents
  shift 2
  attendus=$(for a in "$@"; do noms "$v" "$a"; done | sort)
  presents=$(cd "$dossier" && find . -type f | sed 's|^\./||' | sort)
  if [ "$attendus" != "$presents" ]; then
    echo "✗ $dossier ne porte pas exactement les fichiers attendus :" >&2
    diff <(printf '%s\n' "$attendus") <(printf '%s\n' "$presents") | sed -n 's/^< /  manque : /p; s/^> /  en trop : /p' >&2
    exit 1
  fi
  printf '%s\n' "$attendus" | sed 's/^/✓ /'
}

case "${1:-}" in
  noms) noms "${2:?numéro}" "${3:-}" ;;
  nom) nom "${2:?numéro}" "${3:?clé}" ;;
  rassembler) rassembler "${2:?artefact}" "${3:?numéro}" "${4:?sortie}" ;;
  controler) controler "${2:?numéro}" "${3:?dossier}" "${@:4}" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
