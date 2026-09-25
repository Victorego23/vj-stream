const axios = require('axios');
const realDebridService = require('./realDebridService');
const tmdbService = require('./tmdbService');

/**
 * Servicio inteligente de resolución ultra-rápida de transmisiones para VJ STREAM.
 * Integra:
 * 1. Prioridad absoluta e infalible para Español Latino (Cinecalidad, 🇲🇽) y Castellano (🇪🇸).
 * 2. Detección instantánea de torrents ya cacheados en Real-Debrid ([RD+]) en < 500ms.
 * 3. Caché en memoria para respuestas inmediatas (~1ms).
 * 4. Filtro estricto Anti-CAM (cero grabaciones de cine).
 * 5. Priorización de contenedores MP4 con resolución 1080p para arranque instantáneo sin buffering.
 */
class StreamResolverService {
  constructor() {
    this.timeout = 7000;
    // Caché en memoria: key -> { timestamp, data }
    this.cache = new Map();
    this.CACHE_TTL_MS = 2.5 * 60 * 60 * 1000; // 2.5 horas
  }

  /**
   * Genera una clave única para la caché en memoria.
   * @private
   */
  _getCacheKey(mediaInfo) {
    const { mediaType = 'movie', id, imdbId, season = 1, episode = 1 } = mediaInfo;
    const identifier = imdbId || id || mediaInfo.title;
    return `${mediaType}:${identifier}:${season}:${episode}`;
  }

  /**
   * Limpia un término de búsqueda para maximizar coincidencias.
   * @private
   */
  sanitizeTitle(title) {
    if (!title) return '';
    return title
      .replace(/[:!?.,'"]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Pondera y clasifica un stream según idioma, calidad y compatibilidad.
   * Garantiza que el Español Latino y Castellano superen a cualquier versión en inglés u otro idioma.
   * @private
   */
  scoreStream(stream) {
    const title = (stream.title || '').toLowerCase();
    const name = (stream.name || '').toLowerCase();
    const filename = (stream.behaviorHints?.filename || '').toLowerCase();
    const fullText = `${title} ${name} ${filename}`;

    // 1. FILTRO ANTI-CAM ESTRICTO: Descartar de inmediato grabaciones de cine
    if (realDebridService.isCamOrLowQuality(fullText)) {
      return { stream, score: -999999, audioLanguage: 'CAM', isSpanishAudio: false };
    }

    let score = 0;
    let audioLanguage = 'Audio Original';
    let isSpanishAudio = false;

    // 2. DETECCIÓN ESTRICTA DE ESPAÑOL LATINO (MÁXIMA PRIORIDAD PARA CLIENTES)
    // Cinecalidad, banderas de México, tags explícitos latino, dual-lat, etc.
    const isLatino = /cinecalidad|🇲🇽|latino|\blat\b|dual-lat|audio\s*latino|audio-lat|lat-cinecalidad/i.test(fullText);
    const isCastellano = /mejortorrent|wolfmax4k|🇪🇸|castellano|\bcast\b|\besp\b|\bspa\b|spanish|español/i.test(fullText);
    const isDualOrMulti = /dual|multi/i.test(fullText);

    if (isLatino) {
      score += 2600;
      audioLanguage = 'Español Latino';
      isSpanishAudio = true;
    } else if (isCastellano) {
      score += 1900;
      audioLanguage = 'Castellano';
      isSpanishAudio = true;
    } else if (isDualOrMulti && (isLatino || isCastellano || /esp|spa|lat/i.test(fullText))) {
      score += 1200;
      audioLanguage = 'Dual (Español)';
      isSpanishAudio = true;
    } else if (isDualOrMulti) {
      // Dual o Multi genérico (posible multi-audio europeo o asiático)
      score += 200;
      audioLanguage = 'Multi Audio';
    } else {
      // Versión puramente en inglés u otro idioma extranjero: penalización severa
      score -= 800;
    }

    // 3. CALIDAD DE VIDEO Y RESOLUCIÓN ÓPTIMA PARA SMART TV Y MÓVIL
    if (/1080p|1080i|fhd/i.test(fullText)) {
      score += 200; // Máxima fluidez y estabilidad sin trabas
    } else if (/4k|2160p|uhd/i.test(fullText)) {
      score += 130;
    } else if (/720p|hd/i.test(fullText)) {
      score += 50;
    }

    // 4. FORMATO DE CONTENEDOR (MP4 vs MKV)
    // Los MP4 inician instantáneamente en ExoPlayer de Android TV y permiten saltos rápidos
    if (fullText.includes('.mp4') || filename.endsWith('.mp4')) {
      score += 120;
    }

    // 5. Detectar etiqueta visual
    let qualityLabel = '1080p FHD';
    if (/4k|2160p|uhd/i.test(fullText)) qualityLabel = '4K UHD';
    else if (/720p/i.test(fullText)) qualityLabel = '720p HD';

    return {
      stream,
      score,
      audioLanguage,
      isSpanishAudio,
      qualityLabel,
      filename: stream.behaviorHints?.filename || stream.title?.split('\n')[0] || 'VJ-STREAM'
    };
  }

  /**
   * Detecta si una URL corresponde a un video estático de error o advertencia de Torrentio / Real-Debrid
   * (como la advertencia naranja de 'File was removed from debrid service due to copyright infringement').
   * @param {string} url
   * @returns {boolean}
   */
  isErrorVideoUrl(url) {
    if (!url || typeof url !== 'string') return true;
    const lower = url.toLowerCase();
    return (
      lower.includes('torrentio.strem.fun/videos') ||
      lower.includes('/videos/failed_') ||
      lower.includes('failed_unexpected') ||
      lower.includes('infringing') ||
      lower.includes('file_removed') ||
      lower.includes('copyright_infringement') ||
      lower.includes('dmca') ||
      lower.includes('error.mp4')
    );
  }

  /**
   * Verifica de forma proactiva si la URL de streaming es válida, accesible y reproduce un video real.
   * Descarta de inmediato pantallas de error de derechos de autor (HTTP 451, 403, páginas HTML o clips diminutos).
   * @param {string} url
   * @returns {Promise<boolean>}
   */
  async isStreamPlayable(url) {
    if (!url || typeof url !== 'string') return false;
    if (this.isErrorVideoUrl(url)) return false;

    try {
      const headRes = await axios.head(url, {
        timeout: 3800,
        maxRedirects: 2,
        validateStatus: status => status >= 200 && status < 400
      });

      const contentType = (headRes.headers['content-type'] || '').toLowerCase();
      const contentLength = parseInt(headRes.headers['content-length'], 10);

      // Si responde con HTML en lugar de video, es una página de error o bloqueo
      if (contentType.includes('text/html')) {
        return false;
      }

      // Los videos de advertencia de error/copyright pesan menos de 2 MB (ej: ~136 KB).
      // Un stream multimedia real de película o serie supera holgadamente los 5 MB.
      if (!isNaN(contentLength) && contentLength < 5 * 1024 * 1024) {
        console.warn(`[VJ STREAM Auto-Resolver] 🚫 Stream descartado: tamaño sospechoso (${contentLength} bytes, posible clip de advertencia de error).`);
        return false;
      }

      return true;
    } catch (e) {
      if (e.response && (e.response.status === 403 || e.response.status === 451 || e.response.status === 404)) {
        return false;
      }
      // Si el servidor CDN no admite HEAD (405 Method Not Allowed), probar con un GET de rango mínimo (1 KB)
      if (e.response && e.response.status === 405) {
        try {
          const rangeRes = await axios.get(url, {
            headers: { 'Range': 'bytes=0-1024' },
            timeout: 3500,
            validateStatus: status => status === 200 || status === 206
          });
          const ct = (rangeRes.headers['content-type'] || '').toLowerCase();
          return !ct.includes('text/html');
        } catch (_) {
          return false;
        }
      }
      // Si falla por timeout pero apunta a un CDN genuino de Real-Debrid (.cloud o .com) y no es video de error
      return (url.toLowerCase().includes('real-debrid') && !this.isErrorVideoUrl(url));
    }
  }

  /**
   * Resuelve el enlace directo al CDN de Real-Debrid siguiendo la redirección HTTP 302
   * y descarta enlaces que redirijan a videos de advertencia por copyright.
   * @private
   */
  async _resolveDirectCdnUrl(resolveUrl) {
    if (!resolveUrl) return null;
    try {
      const response = await axios.get(resolveUrl, {
        maxRedirects: 0,
        validateStatus: status => status >= 200 && status < 400,
        timeout: 4800
      });
      const location = response.headers.location;
      if (!location) return resolveUrl;

      if (this.isErrorVideoUrl(location)) {
        console.warn(`[VJ STREAM Auto-Resolver] 🚫 Redirección detectada a advertencia de error de debrid: ${location}`);
        return null;
      }

      return location;
    } catch (e) {
      if (e.response && e.response.headers && e.response.headers.location) {
        const location = e.response.headers.location;
        if (this.isErrorVideoUrl(location)) return null;
        return location;
      }
      return null;
    }
  }

  /**
   * Búsqueda instantánea en catálogo con Real-Debrid conectado (devuelve torrents ya cacheados [RD+]).
   * @private
   */
  async _searchInstantCachedStreams(imdbId, mediaType = 'movie', season = 1, episode = 1) {
    const apiKey = process.env.REALDEBRID_API_KEY;
    if (!apiKey || !imdbId) return [];

    try {
      const target = mediaType === 'tv' ? `${imdbId}:${season}:${episode}` : imdbId;
      const endpoint = mediaType === 'tv' ? 'series' : 'movie';
      const url = `https://torrentio.strem.fun/realdebrid=${apiKey}/stream/${endpoint}/${target}.json`;

      const res = await axios.get(url, { timeout: 6000 }).catch(() => null);
      if (!res?.data?.streams) return [];

      const scored = res.data.streams
        .map(s => this.scoreStream(s))
        .filter(x => x.score > -10000); // Excluir CAM descartados

      // Ordenar por puntuación descendente (Español Latino al frente absoluto)
      scored.sort((a, b) => b.score - a.score);
      return scored;
    } catch (_) {
      return [];
    }
  }

  /**
   * Respaldo: Busca magnets en APIs públicas de torrents comerciales (YTS, Torrentio sin auth).
   * @private
   */
  async searchPublicTrackers(query, year) {
    const magnets = [];
    const sanitized = this.sanitizeTitle(query);

    try {
      const ytsUrl = `https://yts.mx/api/v2/list_movies.json?query_term=${encodeURIComponent(sanitized)}&limit=5`;
      const ytsRes = await axios.get(ytsUrl, { timeout: 3500 }).catch(() => null);

      if (ytsRes?.data?.data?.movies) {
        for (const movie of ytsRes.data.data.movies) {
          if (movie.torrents && movie.torrents.length > 0) {
            for (const t of movie.torrents) {
              const hash = t.hash;
              const quality = t.quality || '1080p';
              const type = t.type || 'bluray';
              const name = `${movie.title} (${movie.year}) [${quality}] [${type}] [VJ STREAM]`;

              const magnet = `magnet:?xt=urn:btih:${hash}&dn=${encodeURIComponent(name)}&tr=udp://open.demonii.com:1337/announce&tr=udp://tracker.openbittorrent.com:80`;
              magnets.push({
                magnet,
                name,
                quality: `${quality} ${type}`
              });
            }
          }
        }
      }
    } catch (_) {}

    return magnets;
  }

  /**
   * Resuelve automáticamente el mejor stream priorizando Español (Latino / Castellano) y alta velocidad.
   * @param {Object} mediaInfo
   */
  async resolveBestStream(mediaInfo) {
    const { title, originalTitle, year, mediaType = 'movie', id, season = 1, episode = 1, bypassCache = false, excludeUrls = [] } = mediaInfo;
    const cacheKey = this._getCacheKey(mediaInfo);

    // 0. VERIFICAR CACHÉ EN MEMORIA (Tiempo de respuesta: ~1ms)
    if (!bypassCache) {
      const cached = this.cache.get(cacheKey);
      if (cached && (Date.now() - cached.timestamp < this.CACHE_TTL_MS)) {
        // Verificar que la URL en caché no esté en las excluidas ni sea un video de error
        const isExcluded = excludeUrls.length > 0 && excludeUrls.includes(cached.data?.streamUrl);
        const isErrorVideo = this.isErrorVideoUrl(cached.data?.streamUrl);

        if (!isExcluded && !isErrorVideo) {
          console.log(`[VJ STREAM Auto-Resolver] ⚡ Transmisión servida desde CACHÉ ULTRA-RÁPIDO para: "${title}"`);
          return cached.data;
        } else {
          console.log(`[VJ STREAM Auto-Resolver] 🔄 Entrada en caché descartada (excluida o error anterior). Re-resolviendo...`);
          this.cache.delete(cacheKey);
        }
      }
    } else {
      this.cache.delete(cacheKey);
    }

    console.log(`[VJ STREAM Auto-Resolver] 🔍 Buscando transmisión automática en ESPAÑOL para: "${title}" (ID: ${id || 'N/A'}${mediaType === 'tv' ? ` S${season}E${episode}` : ''})`);

    // 1. Obtener IMDb ID a través de TMDB si no viene en el payload
    let imdbId = mediaInfo.imdbId;
    if (!imdbId && id) {
      try {
        const client = tmdbService.getAxiosClient();
        const extRes = await client.get(`/${mediaType === 'tv' ? 'tv' : 'movie'}/${id}/external_ids`);
        imdbId = extRes.data?.imdb_id;
      } catch (_) {}
    }

    // 2. PASO 1: BÚSQUEDA INSTANTÁNEA EN CACHÉ DE REAL-DEBRID (TORRENTIO RD)
    // Permite reproducción inmediata en menos de 0.5 segundos con audio en Español garantizado
    if (imdbId) {
      const instantStreams = await this._searchInstantCachedStreams(imdbId, mediaType, season, episode);

      if (instantStreams.length > 0) {
        console.log(`[VJ STREAM Auto-Resolver] 📋 Evaluando ${instantStreams.length} fuentes instantáneas cacheadas para "${title}"...`);

        // Probar candidatos de mayor a menor puntuación hasta encontrar uno 100% libre de errores y sin copyright
        const maxCandidatesToTest = Math.min(instantStreams.length, 10);
        for (let i = 0; i < maxCandidatesToTest; i++) {
          const candidate = instantStreams[i];
          if (!candidate.stream || !candidate.stream.url) continue;

          // Si el usuario reportó esta URL como errónea, saltarla de inmediato
          if (excludeUrls.includes(candidate.stream.url)) {
            continue;
          }

          console.log(`[VJ STREAM Auto-Resolver] 🎯 Probando fuente [${i + 1}/${maxCandidatesToTest}] (${candidate.audioLanguage} - ${candidate.score} pts): "${candidate.filename}"`);
          const directCdnUrl = await this._resolveDirectCdnUrl(candidate.stream.url);

          if (!directCdnUrl || excludeUrls.includes(directCdnUrl)) {
            console.warn(`[VJ STREAM Auto-Resolver] ⚠️ Fuente [${i + 1}] no resolvió enlace directo o fue descartada. Pasando a siguiente fuente...`);
            continue;
          }

          // Comprobar activamente que el CDN entrega un video real y NO la pantalla naranja de copyright
          const playable = await this.isStreamPlayable(directCdnUrl);
          if (!playable) {
            console.warn(`[VJ STREAM Auto-Resolver] 🛡️ Fallback Automático: Fuente [${i + 1}] detectada con advertencia de copyright o stream dañado ("File was removed due to copyright"). Saltando a otra fuente sin error al usuario...`);
            continue;
          }

          console.log(`[VJ STREAM Auto-Resolver] ✅ Transmisión verificada y 100% limpia: "${candidate.filename}"`);
          const result = {
            success: true,
            streamUrl: directCdnUrl,
            qualityLabel: candidate.qualityLabel,
            audioLanguage: candidate.audioLanguage,
            isSpanishAudio: candidate.isSpanishAudio,
            filename: candidate.filename,
            title: title
          };

          // Guardar en caché para próximas reproducciones instantáneas
          this.cache.set(cacheKey, { timestamp: Date.now(), data: result });
          return result;
        }
      }
    }

    // 3. PASO 2: RESPALDO CON REAL-DEBRID RESOLVER NATIVO (Por si no estaba en la caché directa)
    console.log(`[VJ STREAM Auto-Resolver] 🔄 Consultando respaldo nativo Real-Debrid para "${title}"...`);
    let fallbackMagnets = [];

    if (imdbId) {
      try {
        const url = mediaType === 'tv'
          ? `https://torrentio.strem.fun/stream/series/${imdbId}:${season}:${episode}.json`
          : `https://torrentio.strem.fun/stream/movie/${imdbId}.json`;
        const res = await axios.get(url, { timeout: 4500 }).catch(() => null);
        if (res?.data?.streams) {
          for (const st of res.data.streams) {
            if (st.infoHash) {
              const filename = st.behaviorHints?.filename || st.title?.split('\n')[0] || 'VJ-STREAM';
              if (!realDebridService.isCamOrLowQuality(filename)) {
                fallbackMagnets.push({
                  magnet: `magnet:?xt=urn:btih:${st.infoHash}&dn=${encodeURIComponent(filename)}&tr=udp://open.demonii.com:1337/announce`,
                  name: filename
                });
              }
            }
          }
        }
      } catch (_) {}
    }

    // Buscar en YTS / Trackers públicos si es película
    if (fallbackMagnets.length === 0 && mediaType !== 'tv') {
      if (originalTitle) {
        const orig = await this.searchPublicTrackers(originalTitle, year);
        fallbackMagnets.push(...orig);
      }
      if (title && title !== originalTitle) {
        const span = await this.searchPublicTrackers(title, year);
        fallbackMagnets.push(...span);
      }
    }

    // Ordenar magnets de respaldo priorizando español
    fallbackMagnets.sort((a, b) => {
      const aName = (a.name || '').toLowerCase();
      const bName = (b.name || '').toLowerCase();
      const aLat = /cinecalidad|latino|dual-lat|\blat\b/i.test(aName);
      const bLat = /cinecalidad|latino|dual-lat|\blat\b/i.test(bName);
      if (aLat && !bLat) return -1;
      if (!aLat && bLat) return 1;

      const aEsp = /castellano|spanish|español|dual/i.test(aName);
      const bEsp = /castellano|spanish|español|dual/i.test(bName);
      if (aEsp && !bEsp) return -1;
      if (!aEsp && bEsp) return 1;
      return 0;
    });

    for (const candidate of fallbackMagnets.slice(0, 5)) {
      try {
        const result = await realDebridService.resolveMagnetToStream(candidate.magnet, {
          files: 'all',
          unrestrictAll: true
        });

        if (result && result.streams && result.streams.length > 0) {
          for (const streamOption of result.streams) {
            if (excludeUrls.includes(streamOption.streamUrl)) continue;

            const isClean = await this.isStreamPlayable(streamOption.streamUrl);
            if (!isClean) {
              console.warn(`[VJ STREAM Auto-Resolver] ⚠️ Enlace de magnet respaldo bloqueado o de advertencia: "${streamOption.filename}". Probando siguiente...`);
              continue;
            }

            console.log(`[VJ STREAM Auto-Resolver] ✅ Transmisión de respaldo verificada: "${streamOption.filename}"`);
            const streamData = {
              success: true,
              streamUrl: streamOption.streamUrl,
              qualityLabel: streamOption.qualityLabel,
              audioLanguage: streamOption.audioLanguage,
              isSpanishAudio: streamOption.isSpanishAudio,
              filename: streamOption.filename,
              title: title
            };

            this.cache.set(cacheKey, { timestamp: Date.now(), data: streamData });
            return streamData;
          }
        }
      } catch (_) {}
    }

    // 4. PASO 3: BLOQUEO ANTI-CAM (Si no hay versión digital disponible)
    console.log(`[VJ STREAM Anti-CAM] 🛡️ Calidad comercial protegida: Sin versión digital para "${title}".`);
    return {
      success: false,
      isCinemaOnly: true,
      message: `"${title}" está actualmente en salas de cine. VJ STREAM protege la calidad de tus clientes bloqueando grabaciones de baja calidad. Estará disponible en 4K/1080p en su lanzamiento digital oficial.`
    };
  }
}

module.exports = new StreamResolverService();
