#!/usr/bin/env bash
# Le numéro de l'appli vit à trois endroits, qui doivent dire la même chose :
#   src-tauri/tauri.conf.json  ce que Tauri inscrit dans chaque paquet, et d'où il tire le versionCode Android ;
#   src-tauri/Cargo.toml       CARGO_PKG_VERSION, que l'appli compare à releases/latest.json ;
#   src-tauri/Cargo.lock       le paquet rn2c.
# Le numéro est celui du serveur RN2C : une promotion du serveur porte la même étiquette ici.
#
#   scripts/version.sh X.Y.Z                 écrit X.Y.Z aux trois endroits, puis vérifie
#   scripts/version.sh --verifier [vX.Y.Z]   vérifie l'accord des trois (et de l'étiquette, si elle
#                                            est donnée), puis écrit le numéro sur la sortie standard
#   scripts/version.sh --forme X.Y.Z         vérifie seulement la forme d'un numéro
#
# Sans extension GNU : sed et awk POSIX, pour un mainteneur sous macOS comme pour la CI.
set -euo pipefail
cd "$(dirname "$0")/.."

CONF=src-tauri/tauri.conf.json
TOML=src-tauri/Cargo.toml
LOCK=src-tauri/Cargo.lock

# Un porteur introuvable fait échouer : un numéro qui ne serait plus lu nulle part ne doit pas passer pour juste.
lire() {
  local fichier=$1 valeur=$2 n
  n=$(printf '%s' "$valeur" | grep -c . || true)
  if [ "$n" -ne 1 ]; then
    echo "✗ $fichier : $n numéro(s) lu(s) au lieu d'un — le motif ne reconnaît plus le fichier" >&2
    exit 1
  fi
  printf '%s' "$valeur"
}

# La première ligne « version = » de Cargo.toml (celle de [package]), et la ligne « version = »
# qui suit « name = "rn2c" » dans Cargo.lock : chacune n'est lue, ou écrite, que si elle a la
# forme exacte version = "…".
# shellcheck disable=SC2016 # des programmes awk : leur $0 est celui d'awk
TOML_AWK='!vu && /^version = / { vu = 1; if ($0 ~ /^version = "[^"]+"$/) { trouve() } }'
# shellcheck disable=SC2016
LOCK_AWK='suit && /^version = "[^"]+"$/ { trouve() } { suit = ($0 == "name = \"rn2c\"") }'

lire_awk() {
  awk "function trouve() { split(\$0, c, \"\\\"\"); print c[2] } $1" "$2"
}

# Réécrit le fichier en place sans « sed -i » (sa forme diffère entre GNU et BSD) : la copie
# temporaire est recopiée par-dessus, ce qui garde les droits du fichier.
ecrire_awk() {
  local tmp
  tmp=$(mktemp)
  awk -v n="$3" "function trouve() { \$0 = \"version = \\\"\" n \"\\\"\" } $1 { print }" "$2" > "$tmp"
  cat "$tmp" > "$2"
  rm -f "$tmp"
}

# Trois nombres, sans zéro en tête (cargo le refuse). Le .msi borne majeur et mineur à 255 ; Tauri
# calcule le versionCode Android en majeur·1000000 + mineur·1000 + correctif, donc correctif ≤ 999,
# et refuse 0.0.0.
forme() {
  local v=$1 majeur mineur correctif
  if ! printf '%s' "$v" | grep -qE '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$'; then
    echo "✗ $v : trois nombres de trois chiffres au plus, sans zéro en tête, séparés par des points" >&2
    exit 1
  fi
  IFS=. read -r majeur mineur correctif <<< "$v"
  if [ "$majeur" -gt 255 ] || [ "$mineur" -gt 255 ] || [ "$correctif" -gt 999 ]; then
    echo "✗ $v : 255.255.999 au plus (le .msi, puis le versionCode Android)" >&2
    exit 1
  fi
  if [ "$v" = 0.0.0 ]; then
    echo "✗ 0.0.0 : Tauri refuse un versionCode nul" >&2
    exit 1
  fi
}

verifier() {
  local etiquette=${1:-} conf toml lock
  conf=$(lire "$CONF" "$(sed -nE 's/^  "version": "([^"]+)",?$/\1/p' "$CONF")")
  toml=$(lire "$TOML" "$(lire_awk "$TOML_AWK" "$TOML")")
  lock=$(lire "$LOCK" "$(lire_awk "$LOCK_AWK" "$LOCK")")
  if [ "$conf" != "$toml" ] || [ "$conf" != "$lock" ]; then
    echo "✗ les porteurs divergent : tauri.conf.json $conf · Cargo.toml $toml · Cargo.lock $lock" >&2
    exit 1
  fi
  forme "$conf"
  if [ -n "$etiquette" ] && [ "$etiquette" != "v$conf" ]; then
    echo "✗ l'étiquette $etiquette ne correspond pas au numéro des fichiers, $conf" >&2
    exit 1
  fi
  printf '%s\n' "$conf"
}

case "${1:-}" in
  --verifier)
    verifier "${2:-}"
    ;;
  --forme)
    forme "${2:?numéro}"
    ;;
  [0-9]*.[0-9]*.[0-9]*)
    nouveau=$1
    forme "$nouveau"
    verifier > /dev/null
    tmp=$(mktemp)
    sed -E "s/^  \"version\": \"[^\"]+\"/  \"version\": \"$nouveau\"/" "$CONF" > "$tmp"
    cat "$tmp" > "$CONF"
    rm -f "$tmp"
    ecrire_awk "$TOML_AWK" "$TOML" "$nouveau"
    ecrire_awk "$LOCK_AWK" "$LOCK" "$nouveau"
    verifier
    ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
