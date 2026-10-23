#!/usr/bin/env bash
# Sideload tokenized TEI files and annotation layers from a local corpus
# repo into a running eXist-db. Assumes the base corpus (tei.xml per text)
# has already been loaded via the normal POST /corpora/{name} flow.
#
# For each text collection {text}/ the script adds:
#   tokenized.xml                        (from repo's tokenized/)
#   annotations/{layer}.xml              (from repo's annotations/{layer}/)
#
# Creates the annotations subcollection via an XQuery call if needed.
#
# Usage:
#   sideload-annotations.sh <repo-path> <corpus-name>
#
# Example:
#   sideload-annotations.sh ../eco-de de

set -eu

REPO="${1:-}"
CORPUS="${2:-}"
EXIST="${EXIST_URL:-http://localhost:8090/exist}"
AUTH="${EXIST_AUTH:-admin:}"

if [[ -z "$REPO" || -z "$CORPUS" ]]; then
  echo "usage: $0 <repo-path> <corpus-name>" >&2
  exit 1
fi

if [[ ! -d "$REPO/tokenized" ]]; then
  echo "error: $REPO/tokenized not found" >&2
  exit 1
fi

CORPORA="/db/ecocor/corpora"
BASE="$EXIST/rest$CORPORA/$CORPUS"

# Map eco_de_000033 filename → eXist text collection name (lowercased).
# Example: 1807_Kleist_Erdbeben.xml → 1807_kleist_erdbeben
text_collection() {
  local filename="$1"
  local stem="${filename%.xml}"
  echo "$stem" | tr '[:upper:]' '[:lower:]'
}

put() {
  local path="$1" file="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Content-Type: application/xml" \
    --data-binary "@$file" \
    -u "$AUTH" \
    "$BASE/$path")
  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "  FAIL $path (HTTP $code)" >&2
    return 1
  fi
}

mkcol() {
  # Create a collection via XQuery. eXist REST doesn't do MKCOL.
  local parent="$1" name="$2"
  curl -s -u "$AUTH" \
    --data-urlencode "_query=xmldb:create-collection('$parent', '$name')" \
    "$EXIST/rest/db/" > /dev/null
}

# --- tokenized ---
echo "Uploading tokenized/"
count=0
for f in "$REPO"/tokenized/*.xml; do
  [[ -f "$f" ]] || continue
  filename=$(basename "$f")
  text=$(text_collection "$filename")
  put "$text/tokenized.xml" "$f"
  count=$((count + 1))
done
echo "  $count files"

# --- annotation layers ---
if [[ -d "$REPO/annotations" ]]; then
  for layer_dir in "$REPO"/annotations/*/; do
    [[ -d "$layer_dir" ]] || continue
    layer=$(basename "$layer_dir")
    echo "Uploading annotations/$layer/"
    count=0
    for f in "$layer_dir"*.xml; do
      [[ -f "$f" ]] || continue
      filename=$(basename "$f")
      text=$(text_collection "$filename")
      mkcol "$CORPORA/$CORPUS/$text" "annotations"
      put "$text/annotations/$layer.xml" "$f"
      count=$((count + 1))
    done
    echo "  $count files"
  done
fi

echo "Done."
