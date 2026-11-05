#!/bin/bash
# Installa (o aggiorna) Clip Importer in /Applications con un solo comando:
#   curl -fsSL https://raw.githubusercontent.com/Sgnoogle/clip-importer/main/install.sh | bash
set -euo pipefail

URL="https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter.zip"
APP="Clip Importer.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Scarico Clip Importer…"
curl -fL --progress-bar "$URL" -o "$TMP/ClipImporter.zip"
ditto -x -k "$TMP/ClipImporter.zip" "$TMP/x"
SRC="$(find "$TMP/x" -maxdepth 2 -name "$APP" -type d | head -1)"
[ -n "$SRC" ] || { echo "Errore: app non trovata nello zip."; exit 1; }

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "→ Installo in ${DEST}…"
pkill -x ClipImporter 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/$APP"
ditto "$SRC" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

open "$DEST/$APP"
echo "✓ Fatto! Clip Importer è in ${DEST}: trovi l'icona della scheda SD nella barra dei menu."
