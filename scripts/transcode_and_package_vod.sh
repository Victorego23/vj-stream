#!/usr/bin/env bash
# ==============================================================================
# TOM TV - Script de Limpieza, Estandarización y Empaquetado Multi-Audio VOD
# Solución de Arquitectura: Aislamiento estricto de pistas para evitar cruces
# y superposición de voces secundarias (TTS / AD / Comentarios) en Smart TV y móvil.
# ==============================================================================

set -euo pipefail

INPUT_FILE="${1:-}"
OUTPUT_DIR="${2:-}"

# Verificación de dependencias de sistema
command -v ffmpeg >/dev/null 2>&1 || { echo >&2 "[ERROR] ffmpeg no está instalado en el sistema."; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo >&2 "[ERROR] ffprobe no está instalado en el sistema."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "[ERROR] jq no está instalado en el sistema."; exit 1; }

if [[ -z "$INPUT_FILE" || -z "$OUTPUT_DIR" ]]; then
  echo "========================================================================"
  echo " USO: $0 <archivo_origen.(mkv|mp4)> <directorio_salida_hls>"
  echo " Ejemplo: $0 pelicula_master.mkv /var/media/vod/pelicula_001"
  echo "========================================================================"
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "[ERROR] El archivo de origen no existe: $INPUT_FILE"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
WORKDIR=$(mktemp -d /tmp/tomtv_transcode_XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

echo "=== [1/5] Inspección con ffprobe: Descarte de AD, TTS y Comentarios ==="
PROBE_JSON=$(ffprobe -v quiet -print_format json -show_streams -show_format "$INPUT_FILE")

# Identificar pista de video principal
VIDEO_INDEX=$(echo "$PROBE_JSON" | jq -r '[.streams[] | select(.codec_type=="video")][0].index // empty')
if [[ -z "$VIDEO_INDEX" ]]; then
  echo "[ERROR] No se encontró ningún flujo de video en el archivo de entrada."
  exit 1
fi

# Extraer pistas de audio válidas excluyendo flags de Audio Description o Comentarios
VALID_AUDIO_INDEXES=($(echo "$PROBE_JSON" | jq -r '
  [.streams[] | 
   select(.codec_type=="audio") | 
   select(
     (.disposition.visual_impaired == 0 or .disposition.visual_impaired == null) and
     (.disposition.comment == 0 or .disposition.comment == null) and
     (.disposition.descriptions == 0 or .disposition.descriptions == null)
   ) | 
   .index] | .[]'))

echo "Pistas de audio limpias identificadas (índices): ${VALID_AUDIO_INDEXES[*]:-Ninguna}"

if [[ ${#VALID_AUDIO_INDEXES[@]} -eq 0 ]]; then
  echo "[ADVERTENCIA] No se detectaron pistas con tags limpios. Recurriendo a la primera pista disponible."
  VALID_AUDIO_INDEXES=(0)
fi

# Índices para las 3 opciones requeridas:
# 1: Español Latino (por defecto)
# 2: Idioma Original (Nativo / Inglés)
# 3: Español Castellano (España)
A_LATINO=${VALID_AUDIO_INDEXES[0]}
A_ORIGINAL=${VALID_AUDIO_INDEXES[1]:-$A_LATINO}
A_CASTELLANO=${VALID_AUDIO_INDEXES[2]:-$A_LATINO}

echo "Mapeo de Pistas:"
echo "  - Opción 1 (Español Latino): stream 0:$A_LATINO"
echo "  - Opción 2 (Idioma Original): stream 0:$A_ORIGINAL"
echo "  - Opción 3 (Español Castellano): stream 0:$A_CASTELLANO"

echo "=== [2/5] Normalización de Audio EBU R128 (-16 LUFS) y Remuestreo AAC ==="
# Normalización EBU R128 integrada con True Peak -1.5 dBTP para máxima claridad de diálogos
ffmpeg -y -hide_banner -loglevel warning -i "$INPUT_FILE" \
  -filter_complex \
  "[0:$A_LATINO]loudnorm=I=-16:TP=-1.5:LRA=11[a_lat]; \
   [0:$A_ORIGINAL]loudnorm=I=-16:TP=-1.5:LRA=11[a_orig]; \
   [0:$A_CASTELLANO]loudnorm=I=-16:TP=-1.5:LRA=11[a_cas]" \
  -map "[a_lat]" -c:a aac -b:a 192k -ar 48000 -ac 2 "$WORKDIR/audio_latino.mp4" \
  -map "[a_orig]" -c:a aac -b:a 192k -ar 48000 -ac 2 "$WORKDIR/audio_original.mp4" \
  -map "[a_cas]" -c:a aac -b:a 192k -ar 48000 -ac 2 "$WORKDIR/audio_castellano.mp4"

echo "=== [3/5] Aislamiento de Flujo de Video (Desacoplado) ==="
# Extraer únicamente el video en formato MP4 fragmentable para HLS
ffmpeg -y -hide_banner -loglevel warning -i "$INPUT_FILE" \
  -map 0:"$VIDEO_INDEX" -c:v copy -an "$WORKDIR/video_clean.mp4"

echo "=== [4/5] Segmentación HLS Independiente (Garantía Anti-Cruce) ==="
# 1. Segmentar Video (Sin audio en sus paquetes de transporte)
ffmpeg -y -hide_banner -loglevel warning -i "$WORKDIR/video_clean.mp4" \
  -c:v copy \
  -f hls \
  -hls_time 6 \
  -hls_playlist_type vod \
  -hls_segment_filename "$OUTPUT_DIR/video_%04d.ts" \
  "$OUTPUT_DIR/video.m3u8"

# 2. Segmentar Audio Latino
ffmpeg -y -hide_banner -loglevel warning -i "$WORKDIR/audio_latino.mp4" \
  -c:a copy \
  -f hls \
  -hls_time 6 \
  -hls_playlist_type vod \
  -hls_segment_filename "$OUTPUT_DIR/audio_lat_%04d.ts" \
  "$OUTPUT_DIR/audio_latino.m3u8"

# 3. Segmentar Audio Original
ffmpeg -y -hide_banner -loglevel warning -i "$WORKDIR/audio_original.mp4" \
  -c:a copy \
  -f hls \
  -hls_time 6 \
  -hls_playlist_type vod \
  -hls_segment_filename "$OUTPUT_DIR/audio_orig_%04d.ts" \
  "$OUTPUT_DIR/audio_original.m3u8"

# 4. Segmentar Audio Castellano
ffmpeg -y -hide_banner -loglevel warning -i "$WORKDIR/audio_castellano.mp4" \
  -c:a copy \
  -f hls \
  -hls_time 6 \
  -hls_playlist_type vod \
  -hls_segment_filename "$OUTPUT_DIR/audio_cas_%04d.ts" \
  "$OUTPUT_DIR/audio_castellano.m3u8"

echo "=== [5/5] Generación del Master Playlist HLS (master.m3u8) ==="
cat << 'EOF' > "$OUTPUT_DIR/master.m3u8"
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS

# ================= AUDIO RENDITIONS (AISLADAS) =================
# Opción 1: Español Latino (Predeterminado para TomTV)
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="Español Latino (🇲🇽)",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="es-419",URI="audio_latino.m3u8"

# Opción 2: Idioma Original (Subtitulada)
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="Idioma Original (Subtitulada)",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="orig",URI="audio_original.m3u8"

# Opción 3: Español España (Castellano 🇪🇸)
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="Español España (Castellano 🇪🇸)",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="es-ES",URI="audio_castellano.m3u8"

# ================= VIDEO VARIANT (SIN AUDIO EMBEBIDO) =================
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="audio-group"
video.m3u8
EOF

echo "========================================================================"
echo " [ÉXITO] Contenido empaquetado y listo para distribución en:"
echo " $OUTPUT_DIR/master.m3u8"
echo "========================================================================"
