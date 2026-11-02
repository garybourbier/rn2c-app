#!/usr/bin/env bash
# Les noms des fichiers d'une release, lus dans packaging/fichiers.txt.
#
#   scripts/fichiers.sh noms <numéro> [artefact]           les noms attendus, tous ou ceux d'un artefact
#   scripts/fichiers.sh nom <numéro> <clé>                 le nom d'une clé
#   scripts/fichiers.sh artefacts [--ci]                   les artefacts de la liste ; avec --ci, ceux
#                                                          que la CI joint elle-même (tous sauf android)
#   scripts/fichiers.sh rassembler <artefact> <numéro> <sortie>
#                       copie dans <sortie> chaque fichier de l'artefact, trouvé une fois et une seule
#                       sous src-tauri/target/…/bundle/
#   scripts/fichiers.sh controler <numéro> <dossier> <artefact>…
#                       le dossier porte exactement les fichiers de ces artefacts, rien de plus
#   scripts/fichiers.sh verifier          la liste elle-même : trois colonnes, clés et noms uniques,
#                                         chaque nom portant {v}, sans caractère de motif
#
# Écrit pour le bash 3.2 de macOS : ni mapfile, ni tableau associatif.
set -euo pipefail
cd "$(dirname "$0")/.."
LISTE=packaging/fichiers.txt
# L'APK, joint au brouillon par un mainteneur après sa signature : le seul artefact que la CI ne
# joint pas.
SIGNE=android

# Une liste vide ou absente fait échouer : une garde qui lirait zéro nom passerait au vert à vide.
lignes() {
  local contenu
  contenu=$(tr -d '\r' < "$LISTE" | grep -vE '^[[:space:]]*(#|$)' || true)
  if [ -z "$contenu" ]; then
    echo "✗ $LISTE : aucun fichier listé" >&2
    exit 1
  fi
  printf '%s\n' "$contenu"
}

# Un artefact qui ne nomme aucun fichier fait échouer : une boucle sur ses noms ne verrait rien.
noms() {
  local v=$1 filtre=${2:-} cle artefact modele liste sortie
  liste=$(lignes)
  sortie=$(while read -r cle artefact modele; do
    if [ -z "$filtre" ] || [ "$artefact" = "$filtre" ]; then
      printf '%s\n' "${modele//\{v\}/$v}"
    fi
  done <<< "$liste")
  if [ -z "$sortie" ]; then
    echo "✗ artefact $filtre : aucun fichier dans $LISTE" >&2
    exit 1
  fi
  printf '%s\n' "$sortie"
}

nom() {
  local v=$1 voulue=$2 cle artefact modele n=0 trouve='' liste
  liste=$(lignes)
  while read -r cle artefact modele; do
    if [ "$cle" = "$voulue" ]; then n=$((n + 1)); trouve=${modele//\{v\}/$v}; fi
  done <<< "$liste"
  if [ "$n" -ne 1 ]; then
    echo "✗ clé $voulue : $n ligne(s) dans $LISTE au lieu d'une" >&2
    exit 1
  fi
  printf '%s\n' "$trouve"
}

artefacts() {
  local ci=${1:-} liste
  liste=$(lignes | awk '!vu[$2]++ {print $2}')
  if [ "$ci" = --ci ]; then
    liste=$(printf '%s\n' "$liste" | grep -vxF "$SIGNE" || true)
  fi
  if [ -z "$liste" ]; then
    echo "✗ $LISTE : aucun artefact" >&2
    exit 1
  fi
  printf '%s\n' "$liste"
}

rassembler() {
  local artefact=$1 v=$2 sortie=$3 nom n manque=0 attendus
  verifier > /dev/null
  attendus=$(noms "$v" "$artefact")
  mkdir -p "$sortie"
  while read -r nom; do
    n=$(find src-tauri/target -path '*/bundle/*' -type f -name "$nom" 2>/dev/null | grep -c . || true)
    if [ "$n" -ne 1 ]; then
      echo "✗ $nom : $n fichier(s) produit(s) au lieu d'un" >&2
      manque=1
      continue
    fi
    cp "$(find src-tauri/target -path '*/bundle/*' -type f -name "$nom")" "$sortie/"
    echo "✓ $nom"
  done <<< "$attendus"
  exit $manque
}

controler() {
  local v=$1 dossier=$2 attendus presents
  shift 2
  if [ "$#" -eq 0 ]; then
    echo "✗ aucun artefact à contrôler" >&2
    exit 1
  fi
  attendus=$(for a in "$@"; do noms "$v" "$a" || exit 1; done | sort)
  presents=$(cd "$dossier" && find . -type f | sed 's|^\./||' | sort)
  if [ "$attendus" != "$presents" ]; then
    echo "✗ $dossier ne porte pas exactement les fichiers attendus :" >&2
    diff <(printf '%s\n' "$attendus") <(printf '%s\n' "$presents") | sed -n 's/^< /  manque : /p; s/^> /  en trop : /p' >&2
    exit 1
  fi
  printf '%s\n' "$attendus" | sed 's/^/✓ /'
}

verifier() {
  local liste cle artefact modele reste fautes=0
  liste=$(lignes)
  while read -r cle artefact modele reste; do
    if [ -z "$modele" ] || [ -n "$reste" ]; then
      echo "✗ ligne « $cle $artefact $modele $reste » : trois colonnes attendues" >&2; fautes=1; continue
    fi
    if ! printf '%s' "$artefact" | grep -qE '^[a-z0-9_-]+$'; then
      echo "✗ $cle : artefact « $artefact » : minuscules, chiffres, « _ » et « - » seulement" >&2; fautes=1
    fi
    case "$modele" in *'{v}'*) ;; *) echo "✗ $cle : le nom « $modele » ne porte pas {v}" >&2; fautes=1 ;; esac
    case "$modele" in */*|*' '*) echo "✗ $cle : le nom « $modele » porte un / ou un blanc" >&2; fautes=1 ;; esac
    # find -name lirait ces caractères comme un motif, et prendrait un autre fichier pour celui-ci.
    if printf '%s' "$modele" | grep -q '[][*?\\]'; then
      echo "✗ $cle : le nom « $modele » porte un caractère de motif (* ? [ ] \\)" >&2; fautes=1
    fi
  done <<< "$liste"
  for colonne in 1 3; do
    doubles=$(printf '%s\n' "$liste" | awk -v c=$colonne '{print $c}' | sort | uniq -d)
    if [ -n "$doubles" ]; then echo "✗ en double dans $LISTE : $doubles" >&2; fautes=1; fi
  done
  if [ "$fautes" -ne 0 ]; then exit 1; fi
  echo "✓ $LISTE : $(printf '%s\n' "$liste" | grep -c .) fichiers, clés et noms uniques"
}

case "${1:-}" in
  verifier) verifier ;;
  noms) noms "${2:?numéro}" "${3:-}" ;;
  nom) nom "${2:?numéro}" "${3:?clé}" ;;
  artefacts) artefacts "${2:-}" ;;
  rassembler) rassembler "${2:?artefact}" "${3:?numéro}" "${4:?sortie}" ;;
  controler) controler "${2:?numéro}" "${3:?dossier}" "${@:4}" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
