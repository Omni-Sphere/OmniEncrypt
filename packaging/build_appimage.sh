#!/bin/bash
# build_appimage.sh - Build an AppImage for OmniEncrypt on Linux
# Usage: bash packaging/build_appimage.sh [build_dir]
#
# Prerequisites:
#   - OmniEncrypt must be compiled first (cmake .. && make)
#   - linuxdeploy must be available (auto-downloaded if not found)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${1:-$PROJECT_DIR/build}"

if [ ! -f "$BUILD_DIR/OmniEncrypt" ]; then
    echo "Error: OmniEncrypt executable not found in $BUILD_DIR"
    echo "Please compile first: cd build && cmake .. && make"
    exit 1
fi

echo "=== Building OmniEncrypt AppImage ==="

# Limpiar AppDir anterior
APPDIR="$BUILD_DIR/AppDir"
rm -rf "$APPDIR"

# Crear estructura AppDir
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copiar ejecutable
cp "$BUILD_DIR/OmniEncrypt" "$APPDIR/usr/bin/omniencrypt"

# Copiar libOmniUtils.so
if [ -f "$PROJECT_DIR/OmniUtils/libOmniUtils.so" ]; then
    cp "$PROJECT_DIR/OmniUtils/libOmniUtils.so" "$APPDIR/usr/lib/"
elif [ -f "$BUILD_DIR/libOmniUtils.so" ]; then
    cp "$BUILD_DIR/libOmniUtils.so" "$APPDIR/usr/lib/"
fi

# Copiar .desktop file
cp "$PROJECT_DIR/omniencrypt.desktop" "$APPDIR/usr/share/applications/"
cp "$PROJECT_DIR/omniencrypt.desktop" "$APPDIR/"

# Crear icono placeholder si no existe
if [ ! -f "$PROJECT_DIR/omniencrypt.png" ]; then
    echo "Warning: No icon file found. Creating a placeholder."
    # Generar un PNG mínimo de 1x1 pixel como placeholder
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > "$APPDIR/omniencrypt.png"
else
    cp "$PROJECT_DIR/omniencrypt.png" "$APPDIR/"
fi
cp "$APPDIR/omniencrypt.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/"

# Crear AppRun
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
SELF_DIR="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$SELF_DIR/usr/lib:${LD_LIBRARY_PATH}"
exec "$SELF_DIR/usr/bin/omniencrypt" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Descargar linuxdeploy si no existe
LINUXDEPLOY="$BUILD_DIR/linuxdeploy-x86_64.AppImage"
if [ ! -f "$LINUXDEPLOY" ]; then
    echo "Downloading linuxdeploy..."
    wget -q -O "$LINUXDEPLOY" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
    chmod +x "$LINUXDEPLOY"
fi

# Generar AppImage
echo "Generating AppImage..."
export OUTPUT="$BUILD_DIR/OmniEncrypt-x86_64.AppImage"
"$LINUXDEPLOY" --appdir "$APPDIR" --output appimage 2>/dev/null || {
    # Fallback: usar appimagetool directamente si linuxdeploy falla
    echo "linuxdeploy failed, trying manual AppImage creation..."
    APPIMAGETOOL="$BUILD_DIR/appimagetool-x86_64.AppImage"
    if [ ! -f "$APPIMAGETOOL" ]; then
        wget -q -O "$APPIMAGETOOL" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x "$APPIMAGETOOL"
    fi
    ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUTPUT"
}

echo ""
echo "=== AppImage created: $OUTPUT ==="
echo "Run with: chmod +x $OUTPUT && ./$OUTPUT"
