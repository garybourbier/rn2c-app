#!/usr/bin/env bash
# La release que releases/latest.json doit désigner : la plus haute release publiée, de la forme
# vX.Y.Z, dont l'arbre porte scripts/latest-json.py (celles de cette chaîne). Une release d'avant la
# chaîne est ignorée et nommée, même numérotée au-dessus. Aucune : rien n'est écrit, code 0, et
# latest.json doit être retiré.
#
#   GITHUB_REPOSITORY=propriétaire/dépôt GH_TOKEN=… scripts/release-courante.sh
#
# Une erreur de l'API (autre que « ce fichier n'existe pas à cette étiquette ») fait échouer : on ne
# conclut pas « hors chaîne » sur une panne.
set -euo pipefail
ici=$(cd "$(dirname "$0")" && pwd)
: "${GITHUB_REPOSITORY:?propriétaire/dépôt}"

publiees=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/releases" \
  --jq '.[] | select(.draft | not) | select(.prerelease | not) | .tag_name')
valides=''
while read -r e; do
  [ -n "$e" ] || continue
  if [ "${e#v}" != "$e" ] && "$ici/version.sh" --forme "${e#v}" 2> /dev/null; then
    valides="$valides$e"$'\n'
  else
    echo "release ignorée, pas de la forme vX.Y.Z : $e" >&2
  fi
done <<< "$publiees"

while read -r e; do
  [ -n "$e" ] || continue
  if erreur=$(gh api "repos/${GITHUB_REPOSITORY}/contents/scripts/latest-json.py?ref=refs/tags/$e" \
    --jq .name 2>&1 > /dev/null); then
    echo "$e"
    exit 0
  fi
  case "$erreur" in
    *"HTTP 404"*) echo "release ignorée, d'avant cette chaîne : $e" >&2 ;;
    *) echo "✗ $e : l'API ne répond pas ($erreur)" >&2; exit 1 ;;
  esac
done < <(printf '%s' "$valides" | sort -V -r)
