const axios = require('axios');
const realDebridService = require('./realDebridService');
const tmdbService = require('./tmdbService');

/**
 * Servicio inteligente de resolución automática de transmisiones para VJ STREAM.
 * Busca magnets de alta calidad, filtra grabaciones de cine (Anti-CAM),
 * prioriza audio en español y desbrida con Real-Debrid de forma 100% transparente.
 */
class StreamResolverService {
  constructor() {
    this.timeout = 8000;
    // Enlace de streaming certificado de alta velocidad (Big Buck Bunny 4K) como respaldo de emergencia
    this.emergencyFallbackStream = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
  }

  /**
   * Limpia un término de búsqueda para maximizar coincidencias de torrents limpios.
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
   * Obtiene candidatos de torrents directamente a través de Torrentio usando el IMDb ID.
   * Aplica filtro estricto Anti-CAM para descartar grabaciones de sala de cine.
   * @private
   */
  async searchTorrentio(imdbId, mediaType = 'movie', season = 1, episode = 1) {
    if (!imdbId) return [];
    const magnets = [];
    try {
      const url = mediaType === 'tv'
        ? `https://torrentio.strem.fun/stream/series/${imdbId}:${season}:${episode}.json`
        : `https://torrentio.strem.fun/stream/movie/${imdbId}.json`;
      
      const res = await axios.get(url, { timeout: 4500 }).catch(() => null);
      if (res?.data?.streams) {
        for (const st of res.data.streams) {
          if (st.infoHash) {
            const rawTitle = st.title || '';
            const rawName = st.name || '';
            const filename = st.behaviorHints?.filename || rawTitle.split('\n')[0] || 'VJ-STREAM';

            // FILTRADO ESTRICTO ANTI-CAM: Descartar si el título, nombre o archivo contiene marcas de grabación de cine
            if (realDebridService.isCamOrLowQuality(rawTitle) || 
                realDebridService.isCamOrLowQuality(rawName) || 
                realDebridService.isCamOrLowQuality(filename)) {
              console.log(`[VJ STREAM Anti-CAM] 🚫 Grabación de cine descartada: "${filename}"`);
              continue;
            }

            const magnet = `magnet:?xt=urn:btih:${st.infoHash}&dn=${encodeURIComponent(filename)}&tr=udp://open.demonii.com:1337/announce&tr=udp://tracker.openbittorrent.com:80`;
            magnets.push({
              magnet,
              name: filename,
              quality: st.name || '1080p'
            });
          }
        }
      }
    } catch (_) {}
    return magnets;
  }

  /**
   * Busca magnets en APIs públicas de torrents comerciales (ej. YTS para películas 1080p/4K).
   * @private
   */
  async searchPublicTrackers(query, year) {
    const magnets = [];
    const sanitized = this.sanitizeTitle(query);

    try {
      // 1. Consulta YTS API (Calidades limpias 720p/1080p/4K WEB-DL y BluRay sin CAM)
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
   * Resuelve automáticamente el mejor stream sin ninguna intervención técnica del usuario.
   * @param {Object} mediaInfo
   */
  async resolveBestStream(mediaInfo) {
    const { title, originalTitle, year, mediaType = 'movie', id, season = 1, episode = 1 } = mediaInfo;
    console.log(`[VJ STREAM Auto-Resolver] 🔍 Buscando transmisión automática para: "${title}" (ID: ${id || 'N/A'}${mediaType === 'tv' ? ` S${season}E${episode}` : ''})`);

    let bestCandidates = [];

    // 1. Obtener IMDb ID a través de TMDB si no viene en el payload
    let imdbId = mediaInfo.imdbId;
    if (!imdbId && id) {
      try {
        const client = tmdbService.getAxiosClient();
        const extRes = await client.get(`/${mediaType === 'tv' ? 'tv' : 'movie'}/${id}/external_ids`);
        imdbId = extRes.data?.imdb_id;
      } catch (_) {}
    }

    // 2. Si tenemos IMDb ID, consultar Torrentio (Catálogo masivo universal de torrents limpios con filtro Anti-CAM)
    if (imdbId) {
      const torrentioResults = await this.searchTorrentio(imdbId, mediaType, season, episode);
      bestCandidates.push(...torrentioResults);
    }

    // 3. Respaldo YTS: Buscar con título en inglés / original (solo películas comerciales limpias)
    if (bestCandidates.length === 0 && mediaType !== 'tv' && originalTitle && originalTitle !== title) {
      const resultsOriginal = await this.searchPublicTrackers(originalTitle, year);
      bestCandidates.push(...resultsOriginal);
    }

    // 4. Respaldo YTS: Buscar con título en español
    if (bestCandidates.length === 0 && mediaType !== 'tv' && title) {
      const resultsSpanish = await this.searchPublicTrackers(title, year);
      bestCandidates.push(...resultsSpanish);
    }

    // 5. Filtrar cualquier candidato que pueda ser CAM (Filtro Estricto Anti-CAM)
    bestCandidates = bestCandidates.filter(c => !realDebridService.isCamOrLowQuality(c.name));

    // 6. Priorizar inteligentemente candidatos con Audio en Español (Latino / Castellano / Dual)
    bestCandidates.sort((a, b) => {
      const aName = (a.name || '').toLowerCase();
      const bName = (b.name || '').toLowerCase();
      const aHasEsp = /latino|castellano|spanish|español|dual|multi/i.test(aName);
      const bHasEsp = /latino|castellano|spanish|español|dual|multi/i.test(bName);
      if (aHasEsp && !bHasEsp) return -1;
      if (!aHasEsp && bHasEsp) return 1;
      return 0;
    });

    // 7. Intentar desbridar los mejores candidatos con Real-Debrid (hasta 6 candidatos)
    for (const candidate of bestCandidates.slice(0, 6)) {
      try {
        console.log(`[VJ STREAM Auto-Resolver] ⚡ Intentando desbridar candidato: "${candidate.name}"`);
        const result = await realDebridService.resolveMagnetToStream(candidate.magnet, {
          files: 'all',
          unrestrictAll: true
        });

        if (result && result.streams && result.streams.length > 0) {
          const topStream = result.streams[0];
          console.log(`[VJ STREAM Auto-Resolver] ✅ Transmisión lista: ${topStream.qualityLabel} | ${topStream.audioLanguage}`);
          return {
            success: true,
            streamUrl: topStream.streamUrl,
            qualityLabel: topStream.qualityLabel,
            audioLanguage: topStream.audioLanguage,
            isSpanishAudio: topStream.isSpanishAudio,
            filename: topStream.filename,
            title: title
          };
        }
      } catch (err) {
        console.warn(`[VJ STREAM Auto-Resolver] Candidato no disponible de inmediato:`, err.message);
      }
    }

    // 8. Si no hay versión digital limpia en 1080p/4K, BLOQUEAR grabaciones de cine
    console.log(`[VJ STREAM Anti-CAM] 🛡️ Calidad comercial protegida: Sin versión digital para "${title}".`);
    return {
      success: false,
      isCinemaOnly: true,
      message: `"${title}" está actualmente en salas de cine. VJ STREAM protege la calidad de tus clientes bloqueando grabaciones de baja calidad. Estará disponible en 4K/1080p en su lanzamiento digital oficial.`
    };
  }
}

module.exports = new StreamResolverService();
