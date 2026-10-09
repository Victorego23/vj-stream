#!/usr/bin/env bash
set -e

# ==============================================================================
# SCRIPT DE COMPILACIÓN Y EMPAQUETADO PARA SAMSUNG SMART TV (TIZEN OS)
# ==============================================================================

echo "=========================================================="
echo "  🚀 INICIANDO BUILD DE TOM TV PARA SAMSUNG TIZEN (WGT)  "
echo "=========================================================="

# 1. Directorio raíz del proyecto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 2. Compilar Flutter Web en modo Release optimizado para TV
echo "📦 [Paso 1/3] Compilando Flutter Web en modo Release..."
flutter build web --release --base-href "" --web-renderer html

# 3. Preparar directorio de empaquetado Tizen
BUILD_DIR="$PROJECT_ROOT/build/web"
TIZEN_STAGE="$PROJECT_ROOT/build/tizen_pkg"

echo "📂 [Paso 2/3] Estructurando archivos del paquete Tizen..."
rm -rf "$TIZEN_STAGE"
mkdir -p "$TIZEN_STAGE"

# Copiar artefactos web al directorio de empaquetado
cp -R "$BUILD_DIR/"* "$TIZEN_STAGE/"

# Inyectar el descriptor de widget oficial de Tizen
cp "$PROJECT_ROOT/web/tizen/config.xml" "$TIZEN_STAGE/config.xml"

# 4. Empaquetar usando Tizen CLI si está disponible en el entorno
echo "🛠️ [Paso 3/3] Generando paquete .wgt para Samsung Tizen..."
OUTPUT_DIR="$PROJECT_ROOT/build/dist"
mkdir -p "$OUTPUT_DIR"

if command -v tizen &> /dev/null; then
    tizen package -t wgt -s default -o "$OUTPUT_DIR" -- "$TIZEN_STAGE"
    echo "✅ Paquete generado exitosamente en: $OUTPUT_DIR/TOM_TV.wgt"
else
    # Si la CLI de Tizen no está en el PATH, generar el archivo ZIP/WGT estándar
    echo "ℹ️ Tizen CLI no detectada en PATH. Creando paquete .wgt mediante empaquetador ZIP estándar..."
    cd "$TIZEN_STAGE"
    zip -r -q "$OUTPUT_DIR/TOM_TV.wgt" ./*
    echo "✅ Archivo WGT generado con éxito en: $OUTPUT_DIR/TOM_TV.wgt"
    echo "💡 Puedes instalarlo en tu televisor Samsung usando: tizen install -n TOM_TV.wgt"
fi

echo "=========================================================="
echo "  🎉 COMPILACIÓN PARA SAMSUNG TIZEN COMPLETADA CON ÉXITO   "
echo "=========================================================="
