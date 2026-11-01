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

verifier() {
  local etiquette=${1:-} conf toml lock
  conf=$(lire "$CONF" "$(sed -nE 's/^  "version": "([^"]+)",?$/\1/p' "$CONF")")
  toml=$(lire "$TOML" "$(sed -nE '0,/^version = /s/^version = "([^"]+)"$/\1/p' "$TOML")")
  lock=$(lire "$LOCK" "$(sed -nE '/^name = "rn2c"$/{n;s/^version = "([^"]+)"$/\1/p}' "$LOCK")")
  if [ "$conf" != "$toml" ] || [ "$conf" != "$lock" ]; then
    echo "✗ les porteurs divergent : tauri.conf.json $conf · Cargo.toml $toml · Cargo.lock $lock" >&2
    exit 1
  fi
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
  [0-9]*.[0-9]*.[0-9]*)
    nouveau=$1
    # Le .msi exige trois nombres : majeur et mineur jusqu'à 255, correctif jusqu'à 65535.
    if ! printf '%s' "$nouveau" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "✗ $nouveau : trois nombres séparés par des points, rien d'autre" >&2
      exit 1
    fi
    IFS=. read -r majeur mineur correctif <<< "$nouveau"
    if [ "$majeur" -gt 255 ] || [ "$mineur" -gt 255 ] || [ "$correctif" -gt 65535 ]; then
      echo "✗ $nouveau : le .msi n'accepte pas ce numéro (255.255.65535 au plus)" >&2
      exit 1
    fi
    verifier > /dev/null
    sed -i -E "s/^  \"version\": \"[^\"]+\"/  \"version\": \"$nouveau\"/" "$CONF"
    sed -i -E "0,/^version = /s/^version = \"[^\"]+\"$/version = \"$nouveau\"/" "$TOML"
    sed -i -E "/^name = \"rn2c\"$/{n;s/^version = \"[^\"]+\"$/version = \"$nouveau\"/}" "$LOCK"
    verifier
    ;;
  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
