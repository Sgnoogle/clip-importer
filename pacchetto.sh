#!/bin/bash
# Crea ~/Downloads/ClipImporter.zip con l'app pronta (universale: Apple Silicon + Intel)
# e il codice sorgente. Uso:  bash pacchetto.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Clip Importer"
OUT="dist"
APP="$OUT/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/it.lproj" "$OUT/tmp"

for arch in arm64 x86_64; do
    echo "→ Compilazione ($arch)…"
    xcrun swiftc -O -swift-version 5 -parse-as-library \
        -target "$arch-apple-macos13.0" -sdk "$SDK" \
        Sources/*.swift -o "$OUT/tmp/ClipImporter-$arch"
done
lipo -create "$OUT/tmp/ClipImporter-arm64" "$OUT/tmp/ClipImporter-x86_64" \
     -output "$APP/Contents/MacOS/ClipImporter"
rm -rf "$OUT/tmp"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"

echo "→ Creazione dello zip…"
STAGE="$OUT/ClipImporter"
mkdir -p "$STAGE/Codice sorgente"
cp -R "$APP" "$STAGE/"
cp LEGGIMI.md "$STAGE/LEGGIMI.md"
rsync -a --exclude build --exclude dist --exclude .DS_Store ./ "$STAGE/Codice sorgente/"

ZIP="$HOME/Downloads/ClipImporter.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$STAGE" "$ZIP"
rm -rf "$STAGE"
echo "✓ Pronto: $ZIP"
