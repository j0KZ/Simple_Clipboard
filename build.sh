#!/bin/bash
# Compila Portapapeles y arma el bundle .app.
#   ./build.sh           -> compila en ./build/Portapapeles.app
#   ./build.sh --run     -> compila, reemplaza la instancia corriendo y la lanza
#   ./build.sh --install -> además copia la app a /Applications y la lanza desde ahí
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Portapapeles"
BUNDLE_ID="com.j0kz.Portapapeles"
VERSION="1.1.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▸ Compilando (release)…"
# SWIFT_BUILD_FLAGS permite redirigir las cachés de SwiftPM fuera de $HOME. Lo necesita el
# sandbox de compilación de Homebrew, que no deja escribir ahí. Vacío en un build normal.
swift build -c release ${SWIFT_BUILD_FLAGS:-}
BIN="$(swift build -c release --show-bin-path ${SWIFT_BUILD_FLAGS:-})/Portapapeles"

echo "▸ Armando el bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Portapapeles"

# Localizaciones. Van fuera de Sources/ para que SwiftPM no las trate como recursos del
# target: el bundle lo armamos aquí a mano.
for LPROJ in Resources/*.lproj; do
    [ -d "$LPROJ" ] || continue
    cp -R "$LPROJ" "$APP/Contents/Resources/"
done

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift tools/MakeIcon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "  (icono omitido)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>Portapapeles</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <!-- Inglés es el idioma base: si el sistema no está en español, la app sale en inglés. -->
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>es</string></array>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Firma ad-hoc salvo que se pase un certificado en CODESIGN_ID. La ad-hoc cambia de hash en
# cada compilación, pero eso NO revoca Accesibilidad: macOS asocia el permiso a la ruta del
# bundle, no al hash. Lo que sí lo pierde es mover la app de sitio.
if [[ -n "${CODESIGN_ID:-}" ]]; then
    echo "▸ Firmando con $CODESIGN_ID…"
    codesign --force --deep --sign "$CODESIGN_ID" "$APP"
else
    echo "▸ Firmando (ad-hoc)…"
    codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (sin firma)"
fi

echo "✓ Listo: $APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ Instalando en /Applications…"
    pkill -f "$APP_NAME.app/Contents/MacOS/Portapapeles" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    open "/Applications/$APP_NAME.app"
    echo "✓ Instalada y corriendo desde /Applications"
elif [[ "${1:-}" == "--run" ]]; then
    pkill -f "$APP_NAME.app/Contents/MacOS/Portapapeles" 2>/dev/null || true
    sleep 0.5
    open "$APP"
    echo "✓ Corriendo"
fi
