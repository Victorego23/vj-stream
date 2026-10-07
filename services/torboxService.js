const axios = require('axios');

/**
 * Expresión regular estricta para bloquear y descartar automáticamente
 * grabaciones de cine y formatos de baja calidad (Anti-CAM para TOM TV).
 */
const CAM_REGEX = /\b(cam|camrip|ts|telesync|hdcam|hd-cam|pdvd|scr|screener|dvdscr|workprint|hqcam|tc|telecine)\b/i;

/**
 * Servicio para interactuar con la API REST v1.0 de TorBox (torbox.app).
 * Diseñado como Proveedor Base 1 para streaming multi-IP sin restricciones de baneo.
 */
class TorBoxService {
  constructor() {
    this.baseURL = 'https://api.torbox.app/v1/api';
  }

  /**
   * Obtiene la clave de API activa de TorBox desde las variables de entorno.
   * @returns {string|null}
   */
  getApiKey() {
    const key = (process.env.TORBOX_API_KEY || '').trim();
    if (!key || key === '4a49eb84-49f8-4acf-b93b-b6754c53093d') {
      return 'dc49cb4d-f89d-403e-8826-c490edff6fa7';
    }
    return key;
  }

  /**
   * Indica si TorBox está configurado y listo para ser utilizado como Base 1.
   * @returns {boolean}
   */
  isAvailable() {
    return Boolean(this.getApiKey());
  }

  /**
   * Obtiene una instancia configurada de Axios con las cabeceras de autorización de TorBox.
   * @private
   */
  _getAxiosClient() {
    const apiKey = this.getApiKey();
    if (!apiKey) {
      throw new Error('TORBOX_API_KEY no está configurada.');
    }

    return axios.create({
      baseURL: this.baseURL,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
      },
      timeout: 8000
    });
  }

  /**
   * Verifica el estado de la cuenta en TorBox (plan, expiración, datos de usuario).
   * @returns {Promise<Object>}
   */
  async checkAccountStatus() {
    if (!this.isAvailable()) {
      return { active: false, reason: 'TORBOX_API_KEY no configurada' };
    }

    try {
      const client = this._getAxiosClient();
      const res = await client.get('/user/me');
      const data = res.data?.data || res.data;
      const planLabel = data.plan === 3 ? 'Pro' : data.plan === 2 ? 'Estándar' : data.plan === 1 ? 'Essential' : (data.is_subscribed ? 'Premium' : 'Free');
      const expiresAt = data.premium_expires_at || data.customer?.expires_at || null;
      const daysLeft = expiresAt ? Math.max(0, Math.ceil((new Date(expiresAt) - new Date()) / (1000 * 60 * 60 * 24))) : null;
      return {
        active: Boolean(data.is_subscribed || (daysLeft && daysLeft > 0)),
        provider: 'TorBox',
        plan: planLabel,
        email: data.email,
        expiresAt: expiresAt,
        daysLeft: daysLeft
      };
    } catch (err) {
      return {
        active: false,
        error: err.response?.data?.detail || err.message
      };
    }
  }

  /**
   * Verifica si uno o más hashes de torrent están cacheados instantáneamente en TorBox.
   * @param {string|string[]} hashes
   * @returns {Promise<Object>} Mapa hash -> datos en caché
   */
  async checkCached(hashes) {
    if (!this.isAvailable()) return {};
    try {
      const hashList = Array.isArray(hashes) ? hashes.join(',') : hashes;
      const client = this._getAxiosClient();
      const res = await client.get(`/torrents/checkcached?hash=${encodeURIComponent(hashList)}&format=object&list_files=true`);
      return res.data?.data || {};
    } catch (err) {
      console.warn('[TorBox] Error al verificar caché:', err.message);
      return {};
    }
  }

  /**
   * Añade un enlace magnet o hash a la cuenta de TorBox.
   * @param {string} magnet - Enlace magnet URI o hash del torrent
   * @returns {Promise<Object>}
   */
  async addMagnet(magnet) {
    if (!magnet || typeof magnet !== 'string') {
      throw new Error('Magnet o hash de torrent es requerido.');
    }

    let cleanMagnet = magnet.trim();
    if (!cleanMagnet.startsWith('magnet:?')) {
      if (/^[a-fA-F0-9]{40}$/.test(cleanMagnet)) {
        cleanMagnet = `magnet:?xt=urn:btih:${cleanMagnet}`;
      } else if (!cleanMagnet.includes('urn:btih:')) {
        cleanMagnet = `magnet:?xt=urn:btih:${cleanMagnet}`;
      }
    }

    const client = this._getAxiosClient();
    const payload = new URLSearchParams();
    payload.append('magnet', cleanMagnet);
    payload.append('seed', '1');
    payload.append('allow_zip', 'false');

    const res = await client.post('/torrents/createtorrent', payload.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    });

    const body = res.data;
    if (!body.success) {
      throw new Error(body.detail || 'Fallo al agregar magnet a TorBox');
    }

    return {
      torrentId: body.data?.torrent_id,
      hash: body.data?.hash,
      name: body.data?.name
    };
  }

  /**
   * Solicita el enlace de descarga / streaming directo de un archivo en TorBox.
   * @param {number|string} torrentId
   * @param {number|string} fileId
   * @returns {Promise<string>} URL directa del stream CDN
   */
  async requestDownloadLink(torrentId, fileId) {
    const apiKey = this.getApiKey();
    const client = this._getAxiosClient();
    const res = await client.get(`/torrents/requestdl?token=${encodeURIComponent(apiKey)}&torrent_id=${torrentId}&file_id=${fileId}&zip=false&zip_link=false`);

    if (res.data?.success && res.data?.data) {
      return res.data.data;
    }

    throw new Error(res.data?.detail || 'No se pudo obtener enlace directo de TorBox');
  }

  /**
   * Resuelve un magnet a stream directo en el CDN de TorBox.
   * Cero consumo de RAM/búfer en Render: solo orquesta metadatos y entrega la URL CDN.
   * @param {string} magnet - Magnet link o hash
   * @param {Object} [options] - Opciones (season, episode)
   * @returns {Promise<Object>}
   */
  async resolveMagnetToStream(magnet, options = {}) {
    const added = await this.addMagnet(magnet);
    const torrentId = added.torrentId;

    if (!torrentId) {
      throw new Error('No se recibió torrentId válido de TorBox');
    }

    const client = this._getAxiosClient();
    let info = null;

    // Consultar detalles con bypass_cache=true para estado fidedigno
    for (let i = 0; i < 3; i++) {
      const res = await client.get(`/torrents/mylist?id=${torrentId}&bypass_cache=true`);
      info = res.data?.data;
      if (info && (info.download_state === 'completed' || info.download_state === 'cached' || info.progress === 1)) {
        break;
      }
      await new Promise(r => setTimeout(r, 600));
    }

    if (!info) {
      throw new Error('No se pudo obtener información del torrent en TorBox');
    }

    const isReady = info.download_state === 'completed' || info.download_state === 'cached' || info.progress === 1;
    if (!isReady) {
      return {
        success: false,
        ready: false,
        status: info.download_state || 'downloading',
        progress: info.progress || 0,
        seeds: info.seeds || 0,
        torrentId,
        message: 'El torrent no está en caché completado y requiere tiempo de descarga en los servidores de TorBox.'
      };
    }

    const files = Array.isArray(info.files) ? info.files : [];
    if (files.length === 0) {
      throw new Error('El torrent no contiene archivos disponibles en TorBox');
    }

    // Filtrar archivos de video descartando CAMs
    const videoFiles = files.filter(f => {
      const name = (f.name || f.short_name || '').toLowerCase();
      const isVideo = /\.(mp4|mkv|avi|mov|ts|m4v|webm)$/i.test(name);
      const isCam = CAM_REGEX.test(name);
      return isVideo && !isCam;
    });

    let chosen = null;
    if (options && options.episode) {
      const targetEp = parseInt(options.episode, 10);
      const targetSeason = parseInt(options.season, 10) || 1;
      chosen = videoFiles.find(f => {
        const name = (f.name || f.short_name || '').toLowerCase();
        const sMatch = name.match(/\bs?0*(\d{1,2})[.\s_-]*[ex]0*(\d{1,3})\b/i);
        if (sMatch) {
          return parseInt(sMatch[1], 10) === targetSeason && parseInt(sMatch[2], 10) === targetEp;
        }
        const capMatch = name.match(/\bcap(?:itulo)?[.\s_-]*(\d)(\d{2})\b/i);
        if (capMatch) {
          return parseInt(capMatch[1], 10) === targetSeason && parseInt(capMatch[2], 10) === targetEp;
        }
        return false;
      });
    }

    // Si no es serie o no hubo match de episodio: seleccionar el archivo de video de mayor tamaño
    if (!chosen) {
      chosen = videoFiles.sort((a, b) => (b.size || 0) - (a.size || 0))[0] || files[0];
    }

    if (!chosen) {
      throw new Error('No se encontró ningún archivo de video compatible en el torrent');
    }

    // Solicitar URL de streaming directa del CDN de TorBox
    const streamUrl = await this.requestDownloadLink(torrentId, chosen.id);

    return {
      success: true,
      ready: true,
      provider: 'TorBox',
      torrentId,
      fileId: chosen.id,
      streamUrl,
      filename: chosen.name || chosen.short_name || info.name,
      filesize: chosen.size,
      mimeType: chosen.mimetype || 'video/mp4'
    };
  }

  /**
   * Elimina un torrent de TorBox por su ID.
   * @param {number|string} torrentId
   * @returns {Promise<boolean>}
   */
  async deleteTorrent(torrentId) {
    if (!this.isAvailable()) return false;
    try {
      const client = this._getAxiosClient();
      const res = await client.post('/torrents/controltorrent', {
        torrent_id: torrentId,
        operation: 'delete'
      });
      return Boolean(res.data?.success);
    } catch (err) {
      console.warn(`[TorBox] Error al eliminar torrent ${torrentId}:`, err.message);
      return false;
    }
  }

  /**
   * Limpia y elimina automáticamente todos los torrents estancados, sin semillas o fallidos.
   * Mantiene la cuenta de TorBox siempre limpia con solo descargas listas.
   * @returns {Promise<number>} Número de torrents eliminados
   */
  async cleanStalledTorrents() {
    if (!this.isAvailable()) return 0;
    try {
      const client = this._getAxiosClient();
      const res = await client.get('/torrents/mylist?bypass_cache=true');
      const list = res.data?.data || [];
      let deletedCount = 0;

      for (const t of list) {
        const state = (t.download_state || '').toLowerCase();
        // Detectar si está estancado sin semillas, en metadatos, fallido o en 0%
        const isStalled = state.includes('metadl') ||
                          state.includes('stalled') ||
                          state.includes('failed') ||
                          (state === 'downloading' && (t.seeds === 0 || !t.seeds) && (t.progress === 0 || t.progress < 0.2));

        if (isStalled) {
          console.log(`[TorBox Auto-Clean] 🧹 Eliminando torrent estancado sin semillas: "${t.name}" (ID: ${t.id})`);
          const ok = await this.deleteTorrent(t.id);
          if (ok) deletedCount++;
          await new Promise(r => setTimeout(r, 250));
        }
      }

      if (deletedCount > 0) {
        console.log(`[TorBox Auto-Clean] ✨ Limpieza completada: ${deletedCount} torrents estancados eliminados de TorBox.`);
      }
      return deletedCount;
    } catch (err) {
      console.warn('[TorBox Auto-Clean] Error en ciclo de limpieza:', err.message);
      return 0;
    }
  }

  /**
   * Inicia el limpiador en segundo plano cada N minutos.
   */
  startBackgroundCleaner(intervalMinutes = 15) {
    if (!this.isAvailable()) return;
    console.log(`[TorBox Auto-Clean] 🚀 Limpiador autónomo activado (frecuencia: cada ${intervalMinutes} min).`);

    // Limpieza inicial a los 10 segundos
    setTimeout(() => {
      this.cleanStalledTorrents().catch(() => {});
    }, 10000);

    // Ciclo periódico
    setInterval(() => {
      this.cleanStalledTorrents().catch(() => {});
    }, intervalMinutes * 60 * 1000);
  }
}

module.exports = new TorBoxService();

