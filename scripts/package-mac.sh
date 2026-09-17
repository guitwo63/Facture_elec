#!/usr/bin/env bash
# Empaquette FacturXMacApp en .app + .dmg, prêts à distribuer.
#
# Pas de signature Developer ID ni de notarisation : l'app est seulement
# signée "ad hoc" (gratuit, requis sur Apple Silicon pour qu'un exécutable
# puisse simplement se lancer). Résultat : au premier lancement sur un autre
# Mac, Gatekeeper affichera "développeur non identifié" — il faudra
# clic droit > Ouvrir (ou Réglages Système > Confidentialité et sécurité).
#
# Usage :
#   scripts/package-mac.sh              # build natif (l'architecture de cette machine)
#   scripts/package-mac.sh --universal  # build universel arm64 + x86_64
#
# Variables optionnelles :
#   BUNDLE_ID=fr.arverneo.facturxmacapp scripts/package-mac.sh
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_EXEC="FacturXMacApp"
DISPLAY_NAME="Factur-X"
BUNDLE_ID="${BUNDLE_ID:-fr.arverneo.facturxmacapp}"

BUILD_ARGS=(-c release)
if [[ "${1:-}" == "--universal" ]]; then
    echo "==> Build universel (arm64 + x86_64)"
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
else
    echo "==> Build natif ($(uname -m))"
fi

swift build "${BUILD_ARGS[@]}"
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_EXEC"

if [[ ! -f "$BIN_PATH" ]]; then
    echo "Binaire introuvable : $BIN_PATH" >&2
    exit 1
fi

RAW_VERSION="$(git describe --tags --always 2>/dev/null || echo "0.0.0")"
RAW_VERSION="${RAW_VERSION#v}"
VERSION_SHORT="${RAW_VERSION%%-*}"

DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "==> Assemblage de $APP_BUNDLE (version $RAW_VERSION)"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_EXEC"
chmod +x "$CONTENTS/MacOS/$APP_EXEC"

ICON_KEY=""
ICON_SRC="Sources/FacturXMacApp/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$CONTENTS/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$RAW_VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION_SHORT</string>
    <key>CFBundleExecutable</key><string>$APP_EXEC</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    $ICON_KEY
</dict>
</plist>
PLIST

echo "==> Signature ad hoc (gratuite, sans compte Developer)"
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Création du DMG"
DMG_STAGE="$(mktemp -d)"
trap 'rm -rf "$DMG_STAGE"' EXIT
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

DMG_PATH="$DIST_DIR/Factur-X-$VERSION_SHORT.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" -quiet

echo ""
echo "Terminé :"
echo "  App : $APP_BUNDLE"
echo "  DMG : $DMG_PATH"
