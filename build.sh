#!/bin/bash
# Compila Clip Importer e lo installa nella cartella Applicazioni.
# Uso: apri il Terminale in questa cartella e scrivi:  bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Per compilare servono gli Strumenti da riga di comando di Apple."
    echo "Si apre ora la finestra di installazione: al termine rilancia  bash build.sh"
    xcode-select --install || true
    exit 1
fi

APP_NAME="Clip Importer"
BUILD="build/$APP_NAME.app"
ARCH="$(uname -m)"

echo "→ Compilazione ($ARCH)…"
rm -rf build
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources/it.lproj"
xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos13.0" \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    Sources/*.swift \
    -o "$BUILD/Contents/MacOS/ClipImporter"

cp Resources/Info.plist "$BUILD/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUILD/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$BUILD" >/dev/null 2>&1 || true

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "→ Installazione in ${DEST}…"
pkill -x ClipImporter 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/$APP_NAME.app"
cp -R "$BUILD" "$DEST/"

open "$DEST/$APP_NAME.app"
echo "✓ Fatto! Clip Importer è in $DEST e ora vive nella barra dei menu (icona della scheda SD)."
