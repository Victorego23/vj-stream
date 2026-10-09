#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT DE COMPILACIÓN Y EMPAQUETADO PARA LG SMART TV (webOS)
# ==============================================================================

echo "=========================================================="
echo "  🚀 INICIANDO BUILD DE TOM TV PARA LG webOS (IPK)       "
echo "=========================================================="

# 1. Directorio raíz del proyecto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 2. Compilar Flutter Web en modo Release optimizado para TV
echo "📦 [Paso 1/3] Compilando Flutter Web en modo Release..."
flutter build web --release --base-href "" --web-renderer html

# 3. Preparar directorio de empaquetado webOS
BUILD_DIR="$PROJECT_ROOT/build/web"
WEBOS_STAGE="$PROJECT_ROOT/build/webos_pkg"

echo "📂 [Paso 2/3] Estructurando archivos del paquete LG webOS..."
rm -rf "$WEBOS_STAGE"
mkdir -p "$WEBOS_STAGE"

# Copiar artefactos web al directorio de empaquetado
cp -R "$BUILD_DIR/"* "$WEBOS_STAGE/"

# Inyectar el descriptor oficial appinfo.json de webOS
cp "$PROJECT_ROOT/web/webos/appinfo.json" "$WEBOS_STAGE/appinfo.json"

# 4. Empaquetar usando LG webOS CLI (ares-package) si está disponible
echo "🛠️ [Paso 3/3] Generando paquete .ipk para LG webOS..."
OUTPUT_DIR="$PROJECT_ROOT/build/dist"
mkdir -p "$OUTPUT_DIR"

if command -v ares-package &> /dev/null; then
    ares-package "$WEBOS_STAGE" -o "$OUTPUT_DIR"
    echo "✅ Paquete generado exitosamente en: $OUTPUT_DIR/*.ipk"
    echo "💡 Puedes instalarlo en tu televisor LG usando: ares-install $OUTPUT_DIR/lat.tomtv.app_*.ipk"
else
    echo "ℹ️ ares-package (webOS CLI) no detectado en PATH."
    echo "💡 La carpeta empaquetada lista para ares-package se encuentra en:"
    echo "   $WEBOS_STAGE"
    echo "💡 Una vez instalado webOS CLI, simplemente ejecuta:"
    echo "   ares-package $WEBOS_STAGE -o $OUTPUT_DIR"
fi

echo "=========================================================="
echo "  🎉 COMPILACIÓN PARA LG webOS COMPLETADA CON ÉXITO      "
echo "=========================================================="
