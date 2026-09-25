const axios = require('axios');

/**
 * Expresión regular estricta para bloquear y descartar automáticamente
 * grabaciones de cine y formatos de baja calidad (Anti-CAM para VJ STREAM).
 */
const CAM_REGEX = /\b(cam|camrip|ts|telesync|hdcam|hd-cam|pdvd|scr|screener|dvdscr|workprint|hqcam|tc|telecine)\b/i;

/**
 * Servicio para interactuar con la API REST v1.0 de Real-Debrid.
 * Integra filtrado Anti-CAM y priorización de audio en español para VJ STREAM.
 */
class RealDebridService {
  constructor() {
    this.baseURL = 'https://api.real-debrid.com/rest/1.0';
  }

  /**
   * Obtiene una instancia configurada de Axios con las cabeceras de autorización.
   * @private
   */
  getAxiosClient() {
    const apiKey = process.env.REALDEBRID_API_KEY;

    if (!apiKey) {
      throw new Error('REALDEBRID_API_KEY no está configurada en las variables de entorno.');
    }

    return axios.create({
      baseURL: this.baseURL,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      timeout: 15000
    });
  }

  /**
   * Verifica de forma estricta e infalible si un archivo, torrent o tag es una grabación CAM/TS de cine.
   * @param {string} filename 
   * @returns {boolean}
   */
  isCamOrLowQuality(filename) {
    if (!filename) return false;
    const text = String(filename).toLowerCase();
    
    // Lista exhaustiva de marcadores de grabación de sala de cine (CAM, TS, Telesync, Screener)
    const patterns = [
      /\b(cam|camrip|cam-rip|hdcam|hd-cam|hqcam|newcam|cleancam|clean-cam|camv2|camv3)\b/i,
      /\b(ts|hdts|hd-ts|telesync|tele-sync|pdvd|predvd|tc|telecine|cine-ts)\b/i,
      /\b(scr|screener|dvdscr|bdscr|workprint|sample)\b/i,
      /\b(cine|grabado\s*en\s*cine|cinema|cinerip|multiplex)\b/i,
      /\b(1xbet|line\s*audio|clean\s*audio|mic\s*audio|vostfr\s*cam)\b/i,
      /cam[._-]?h264|cam[._-]?xvid|cam[._-]?ac3|cam[._-]?lat/i,
      /hd-?cam|hd-?ts|tele-?sync/i
    ];

    return patterns.some(pattern => pattern.test(text));
  }

  /**
   * Analiza el nombre de un archivo y extrae metadatos de calidad comercial (1080p, 4K, HDR, BluRay, WEB-DL).
   * @param {string} filename 
   * @returns {{label: string, resolution: string, source: string, isHdr: boolean, score: number}}
   */
  detectQuality(filename) {
    const name = (filename || '').toLowerCase();
    let resolution = '1080p';
    let source = 'WEB-DL';
    let isHdr = false;
    let score = 50;

    if (/\b(4k|uhd|2160p)\b/i.test(name)) {
      resolution = '4K UHD';
      score += 40;
    } else if (/\b(1080p|1080i|fhd)\b/i.test(name)) {
      resolution = '1080p';
      score += 45; // Fluidez y compatibilidad instantánea en Android TV y móvil
    } else if (/\b(720p|hd)\b/i.test(name)) {
      resolution = '720p';
      score += 20;
    }

    if (/\b(web-dl|webdl|webrip|web)\b/i.test(name)) {
      source = 'WEB-DL';
      score += 35; // Compatibilidad universal de audio y video
    } else if (/\b(bluray|bdrip|brrip)\b/i.test(name)) {
      source = 'BluRay';
      score += 30;
    } else if (/\b(remux)\b/i.test(name)) {
      source = 'REMUX';
      score += 15; // Despriorizar remux gigantescos (>50GB con TrueHD incompatible)
    }

    if (/\b(hdr|hdr10|hdr10\+|dv|dolby\s*vision)\b/i.test(name)) {
      isHdr = true;
      score += 10;
    }

    if (name.endsWith('.mp4') || /\b\.mp4\b/i.test(name)) {
      score += 25; // Formato MP4 con soporte nativo absoluto en ExoPlayer
    }

    return {
      label: `${resolution} ${source}${isHdr ? ' HDR' : ''}`.trim(),
      resolution,
      source,
      isHdr,
      score
    };
  }

  /**
   * Analiza el nombre de un archivo para detectar pistas de audio en Español (Latino / Castellano / Dual).
   * @param {string} filename 
   * @returns {{language: string, isSpanish: boolean, score: number}}
   */
  detectAudioLanguage(filename) {
    const name = (filename || '').toLowerCase();
    let language = 'Audio Original';
    let isSpanish = false;
    let score = 10;

    if (/\b(latino|lat|audio\s*latino)\b/i.test(name)) {
      language = 'Español Latino';
      isSpanish = true;
      score = 100;
    } else if (/\b(castellano|cast|spanish|esp|spa)\b/i.test(name)) {
      language = 'Castellano';
      isSpanish = true;
      score = 90;
    } else if (/\b(dual|multi|multi-audio|audio\s*dual)\b/i.test(name)) {
      language = 'Dual / Multi (Español)';
      isSpanish = true;
      score = 80;
    }

    return { language, isSpanish, score };
  }

  /**
   * Añade un magnet link o hash a Real-Debrid.
   * Endpoint: POST /torrents/addMagnet
   * @param {string} magnet - Magnet link o hash del torrent.
   * @returns {Promise<{id: string, uri: string}>}
   */
  async addMagnet(magnet) {
    try {
      if (!magnet) {
        throw new Error('El parámetro "magnet" es obligatorio.');
      }

      const client = this.getAxiosClient();
      const params = new URLSearchParams();
      params.append('magnet', magnet);

      const response = await client.post('/torrents/addMagnet', params.toString());
      return response.data;
    } catch (error) {
      this.handleError('addMagnet', error);
    }
  }

  /**
   * Selecciona los archivos a descargar/procesar en el torrent añadido.
   * Endpoint: POST /torrents/selectFiles/{id}
   * @param {string} torrentId
   * @param {string} [fileIds='all']
   * @returns {Promise<boolean>}
   */
  async selectFiles(torrentId, fileIds = 'all') {
    try {
      if (!torrentId) {
        throw new Error('El parámetro "torrentId" es obligatorio.');
      }

      const client = this.getAxiosClient();
      const params = new URLSearchParams();
      params.append('files', fileIds);

      const response = await client.post(`/torrents/selectFiles/${torrentId}`, params.toString());
      return response.status === 204 || response.status === 200;
    } catch (error) {
      this.handleError(`selectFiles (torrentId: ${torrentId})`, error);
    }
  }

  /**
   * Obtiene información detallada del torrent.
   * Endpoint: GET /torrents/info/{id}
   * @param {string} torrentId
   * @returns {Promise<Object>}
   */
  async getTorrentInfo(torrentId) {
    try {
      if (!torrentId) {
        throw new Error('El parámetro "torrentId" es obligatorio.');
      }

      const client = this.getAxiosClient();
      const response = await client.get(`/torrents/info/${torrentId}`);
      return response.data;
    } catch (error) {
      this.handleError(`getTorrentInfo (torrentId: ${torrentId})`, error);
    }
  }

  /**
   * Desbrida un enlace para obtener la URL directa de descarga/streaming.
   * Endpoint: POST /unrestrict/link
   * @param {string} link
   * @param {string} [password]
   * @returns {Promise<Object>}
   */
  async unrestrictLink(link, password = null) {
    try {
      if (!link) {
        throw new Error('El parámetro "link" es obligatorio para desbridar.');
      }

      const client = this.getAxiosClient();
      const params = new URLSearchParams();
      params.append('link', link);
      if (password) {
        params.append('password', password);
      }

      const response = await client.post('/unrestrict/link', params.toString());
      return response.data;
    } catch (error) {
      this.handleError('unrestrictLink', error);
    }
  }

  /**
   * Elimina un torrent de la cuenta de Real-Debrid.
   * Endpoint: DELETE /torrents/delete/{id}
   * @param {string} torrentId
   * @returns {Promise<boolean>}
   */
  async deleteTorrent(torrentId) {
    try {
      if (!torrentId) return false;
      const client = this.getAxiosClient();
      const response = await client.delete(`/torrents/delete/${torrentId}`);
      return response.status === 204 || response.status === 200;
    } catch (error) {
      this.handleError(`deleteTorrent (torrentId: ${torrentId})`, error);
    }
  }

  /**
   * Flujo completo de resolución para VJ STREAM con:
   * 1. Bloqueo estricto Anti-CAM (descarta grabaciones de sala).
   * 2. Extracción de calidades comerciales (1080p, WEB-DL, BluRay, 4K HDR).
   * 3. Priorización de pistas de audio en español (Latino/Castellano/Dual).
   * 
   * @param {string} magnet - Magnet link
   * @param {Object} [options]
   * @returns {Promise<Object>}
   */
  async resolveMagnetToStream(magnet, options = { files: 'all', unrestrictAll: true }) {
    try {
      // 1. Agregar magnet
      const addResult = await this.addMagnet(magnet);
      const torrentId = addResult.id;

      // 2. Seleccionar archivos
      await this.selectFiles(torrentId, options.files || 'all');

      // 3. Obtener información
      const torrentInfo = await this.getTorrentInfo(torrentId);

      // Si el nombre del torrent en sí es CAM, registrar aviso
      if (this.isCamOrLowQuality(torrentInfo.filename)) {
        console.warn(`[VJ STREAM Anti-CAM] Advertencia: Torrent "${torrentInfo.filename}" detectado como posible CAM/TS.`);
      }

      // Si aún no está en caché o descargado en Real-Debrid, esperar brevemente a que el cloud de Real-Debrid procese o descargue
      let attempts = 0;
      while ((!torrentInfo.links || torrentInfo.links.length === 0) && attempts < 3 && torrentInfo.status !== 'magnet_error' && torrentInfo.status !== 'error') {
        attempts++;
        console.log(`[RealDebridService] ⏳ Esperando procesamiento/descarga en la nube para "${torrentInfo.filename}" (intento ${attempts}/3)...`);
        await new Promise(r => setTimeout(r, 2000));
        torrentInfo = await this.getTorrentInfo(torrentId);
      }

      if (!torrentInfo.links || torrentInfo.links.length === 0) {
        return {
          success: true,
          torrentId,
          status: torrentInfo.status,
          progress: torrentInfo.progress,
          message: 'El torrent ha sido añadido a tu nube de Real-Debrid para descarga.',
          streams: []
        };
      }

      // 4. Desbridar y filtrar enlaces con filtro Anti-CAM y priorización de audio en español
      const rawStreams = [];
      const linksToProcess = options.unrestrictAll ? torrentInfo.links : [torrentInfo.links[0]];

      for (const link of linksToProcess) {
        try {
          const unrestricted = await this.unrestrictLink(link);
          const filename = unrestricted.filename || '';

          // FILTRO ESTRICTO ANTI-CAM: Bloquear y descartar automáticamente grabaciones de cine
          if (this.isCamOrLowQuality(filename)) {
            console.log(`[VJ STREAM Anti-CAM] 🚫 Archivo descartado por baja calidad CAM/TS: "${filename}"`);
            continue;
          }

          // Detección de calidad e idioma de audio
          const quality = this.detectQuality(filename);
          const audio = this.detectAudioLanguage(filename);
          const totalRank = quality.score + audio.score;

          rawStreams.push({
            originalLink: link,
            streamUrl: unrestricted.download,
            filename: unrestricted.filename,
            filesize: unrestricted.filesize,
            mimeType: unrestricted.mimeType,
            streamable: unrestricted.streamable,
            qualityLabel: quality.label,
            resolution: quality.resolution,
            source: quality.source,
            isHdr: quality.isHdr,
            audioLanguage: audio.language,
            isSpanishAudio: audio.isSpanish,
            rankScore: totalRank
          });
        } catch (unrestrictErr) {
          console.warn(`[RealDebridService] Advertencia al desbridar ${link}:`, unrestrictErr.message);
        }
      }

      // Ordenar los streams por puntuación: Primero 4K/1080p con audio en español (Latino/Castellano/Dual)
      rawStreams.sort((a, b) => b.rankScore - a.rankScore);

      return {
        success: true,
        torrentId,
        filename: torrentInfo.filename,
        status: torrentInfo.status,
        progress: torrentInfo.progress,
        filteredCount: torrentInfo.links.length - rawStreams.length,
        streams: rawStreams
      };
    } catch (error) {
      this.handleError('resolveMagnetToStream', error);
    }
  }

  /**
   * Manejador centralizado y normalizador de errores para las peticiones a Real-Debrid.
   * @private
   */
  handleError(action, error) {
    let statusCode = 500;
    let message = `Error desconocido en RealDebridService.${action}`;

    if (error.response) {
      statusCode = error.response.status;
      const errorData = error.response.data;
      const apiMessage = errorData?.error || errorData?.message || JSON.stringify(errorData);
      message = `Real-Debrid API Error (${statusCode}) en ${action}: ${apiMessage}`;
    } else if (error.request) {
      message = `No hubo respuesta del servidor de Real-Debrid en ${action}.`;
    } else {
      message = error.message || message;
    }

    const customError = new Error(message);
    customError.statusCode = statusCode;
    customError.originalError = error;
    throw customError;
  }
}

module.exports = new RealDebridService();
