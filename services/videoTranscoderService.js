/**
 * Servicio de Validación y Normalización de Video Transcoder / Remuxer
 * Garantiza integridad de escala, dimensiones pares y espacio de color estándar (yuv420p)
 * para evitar artefactos de decodificación (franja verde inferior y líneas horizontales).
 */

class VideoTranscoderService {
  constructor() {
    this.DEFAULT_PIX_FMT = 'yuv420p';
    this.DEFAULT_VIDEO_CODEC = 'libx264';
    this.DEFAULT_PROFILE = 'high';
    this.DEFAULT_LEVEL = '4.1';
  }

  /**
   * Garantiza que las dimensiones de video sean números pares estrictos (múltiplos de 2).
   * La submuestreación de croma YUV 4:2:0 requiere dimensiones pares para que los planos
   * U y V no dejen filas sin inicializar (que se visualizan como franjas verdes).
   * @param {number} width
   * @param {number} height
   * @returns {{width: number, height: number, isAdjusted: boolean}}
   */
  ensureEvenDimensions(width, height) {
    const w = Math.max(2, Math.round(width || 1920));
    const h = Math.max(2, Math.round(height || 1080));
    
    const evenW = w % 2 === 0 ? w : w + 1;
    const evenH = h % 2 === 0 ? h : h + 1;

    return {
      width: evenW,
      height: evenH,
      isAdjusted: evenW !== w || evenH !== h
    };
  }

  /**
   * Genera los filtros y parámetros obligatorios de FFmpeg para cualquier pipeline
   * de procesamiento, transcodificación o remuxeo en Node.js / Docker:
   * 1. Fuerza el formato de pixel estrictamente a 'yuv420p'.
   * 2. Aplica pad=ceil(iw/2)*2:ceil(ih/2)*2 para garantizar ancho y alto múltiplos de 2.
   * 3. Establece perfil H.264 High/Main con aceleración por hardware universal.
   * @param {Object} [options]
   * @returns {string[]} Argumentos de línea de comandos de FFmpeg
   */
  getFFmpegFilterArgs(options = {}) {
    const {
      maxHeight = null,
      crf = 22,
      preset = 'veryfast',
      tune = 'film',
      audioCodec = 'copy'
    } = options;

    const filters = [];

    // Si se especifica escala máxima, mantener aspecto pero truncar a múltiplos de 2
    if (maxHeight) {
      filters.push(`scale=-2:min(ih\\,${maxHeight})`);
    }

    // Filtro estricto para forzar dimensiones pares sin distorsión (evita franja verde en SD)
    filters.push('pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:black');

    const args = [
      '-vf', filters.join(','),
      '-pix_fmt', this.DEFAULT_PIX_FMT,
      '-c:v', this.DEFAULT_VIDEO_CODEC,
      '-profile:v', this.DEFAULT_PROFILE,
      '-level', this.DEFAULT_LEVEL,
      '-crf', String(crf),
      '-preset', preset,
      '-tune', tune,
      '-c:a', audioCodec,
      '-movflags', '+faststart'
    ];

    return args;
  }

  /**
   * Valida metadatos técnicos de un flujo de video para detectar riesgos de artefactos
   * antes de entregarlo al cliente.
   * @param {Object} streamInfo - Metadatos de resolución y códec
   * @returns {{isValid: boolean, warnings: string[], isH264: boolean, isEvenResolution: boolean}}
   */
  validateStreamMetadata(streamInfo = {}) {
    const warnings = [];
    const width = Number(streamInfo.width);
    const height = Number(streamInfo.height);
    const codec = (streamInfo.codec || streamInfo.codec_name || '').toLowerCase();
    const pixFmt = (streamInfo.pixFmt || streamInfo.pix_fmt || '').toLowerCase();

    let isEven = true;
    if (width && width % 2 !== 0) {
      isEven = false;
      warnings.push(`Ancho impar detectado (${width}px). Riesgo de desalineación de croma.`);
    }
    if (height && height % 2 !== 0) {
      isEven = false;
      warnings.push(`Alto impar detectado (${height}px). Causa común de franja verde inferior.`);
    }

    if (pixFmt && pixFmt !== 'yuv420p') {
      warnings.push(`Espacio de color no estándar (${pixFmt}). Recomendado: yuv420p.`);
    }

    const isHevc = codec.includes('hevc') || codec.includes('h265') || codec.includes('265');
    const isAv1 = codec.includes('av1');
    const isLegacy = codec.includes('mpeg4') || codec.includes('xvid') || codec.includes('msmpeg4');
    const isH264 = codec.includes('h264') || codec.includes('avc');

    if (isHevc || isAv1) {
      warnings.push(`Códec pesado (${codec.toUpperCase()}). Puede generar líneas horizontales en clientes sin decodificador dedicado.`);
    }

    if (isLegacy) {
      warnings.push(`Códec legado (${codec}). Puede causar fallos de relación de aspecto en decodificadores modernos.`);
    }

    return {
      isValid: warnings.length === 0,
      warnings,
      isH264,
      isEvenResolution: isEven,
      recommendedPixFmt: this.DEFAULT_PIX_FMT
    };
  }

  /**
   * Genera los filtros y parámetros obligatorios de FFmpeg para aislar y limpiar
   * pistas de audio VOD, descartando narraciones (TTS/AD), comentarios del director
   * y normalizando la sonoridad a estándar de streaming EBU R128 (-16 LUFS).
   * @param {Object} [options]
   * @returns {string[]} Argumentos de FFmpeg
   */
  getAudioCleaningFilterArgs(options = {}) {
    const {
      audioBitrate = '192k',
      sampleRate = 48000,
      channels = 2,
      targetLufs = -16,
      truePeak = -1.5,
      codec = 'aac'
    } = options;

    return [
      '-filter:a', `loudnorm=I=${targetLufs}:TP=${truePeak}:LRA=11`,
      '-c:a', codec,
      '-b:a', audioBitrate,
      '-ar', String(sampleRate),
      '-ac', String(channels)
    ];
  }

  /**
   * Valida si una pista de audio contiene marcadores de narración sintética (TTS),
   * Audio Description (AD) o comentarios secundarios que puedan solaparse con la pista principal.
   * @param {Object} audioStreamInfo - Metadatos de la pista de ffprobe
   * @returns {{isClean: boolean, reasons: string[]}}
   */
  validateAudioStream(audioStreamInfo = {}) {
    const reasons = [];
    const disposition = audioStreamInfo.disposition || {};
    const tags = audioStreamInfo.tags || {};
    const title = (tags.title || tags.handler_name || '').toLowerCase();

    if (disposition.visual_impaired === 1 || disposition.descriptions === 1) {
      reasons.push('Pista marcada como Audio Description (AD / Visual Impaired)');
    }
    if (disposition.comment === 1) {
      reasons.push('Pista marcada como comentario del director');
    }
    if (disposition.hearing_impaired === 1) {
      reasons.push('Pista marcada para discapacidad auditiva con posibles descriptores de audio');
    }

    const ttsPattern = /\b(tts|lector|audiolectura|sintetico|voiceover|voice-over|voice\s*over|\bvo\b|\bmvo\b|\bdvo\b|\bavo\b|narraci[oó]n)\b/i;
    if (ttsPattern.test(title)) {
      reasons.push(`Pista con marcador de doblaje no oficial/sintético en título: "${title}"`);
    }

    return {
      isClean: reasons.length === 0,
      reasons
    };
  }

  /**
   * Genera un manifiesto Master HLS (.m3u8) desacoplado para multi-audio.
   * Asegura que cada idioma esté estrictamente aislado bajo directivas #EXT-X-MEDIA:TYPE=AUDIO
   * para que el reproductor jamás reciba dos pistas superpuestas en el mismo contenedor de transporte.
   * @param {Object} config
   * @param {Array<{resolution: string, bandwidth: number, uri: string}>} config.videoVariants
   * @param {Array<{id: string, name: string, language: string, uri: string, isDefault: boolean}>} config.audioTracks
   * @returns {string} Contenido completo del manifiesto .m3u8
   */
  generateHlsMasterPlaylist(config) {
    const { videoVariants = [], audioTracks = [] } = config;
    const lines = [
      '#EXTM3U',
      '#EXT-X-VERSION:6',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      ''
    ];

    lines.push('# === PISTAS DE AUDIO AISLADAS (INDEPENDIENTES) ===');
    for (const audio of audioTracks) {
      const isDef = audio.isDefault ? 'YES' : 'NO';
      const autoSel = audio.isDefault ? 'YES' : 'NO';
      lines.push(
        `#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="${audio.name}",` +
        `DEFAULT=${isDef},AUTOSELECT=${autoSel},LANGUAGE="${audio.language}",URI="${audio.uri}"`
      );
    }

    lines.push('');
    lines.push('# === VARIANTES DE VIDEO (SIN AUDIO MUXED) ===');
    for (const v of videoVariants) {
      lines.push(
        `#EXT-X-STREAM-INF:BANDWIDTH=${v.bandwidth},RESOLUTION=${v.resolution},AUDIO="audio-group"`
      );
      lines.push(v.uri);
    }

    return lines.join('\n');
  }
}

module.exports = new VideoTranscoderService();
