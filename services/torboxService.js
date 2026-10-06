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
    return (process.env.TORBOX_API_KEY || '').trim() || null;
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
        'Content-Type': 'application/json'
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
   * Añade un enlace magnet a la cuenta de TorBox.
   * @param {string} magnet
   * @returns {Promise<Object>}
   */
  async addMagnet(magnet) {
    const client = this._getAxiosClient();
    const payload = new URLSearchParams();
    payload.append('magnet', magnet);
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
    const res = await client.get(`/torrents/requestdl?token=${encodeURIComponent(apiKey)}&torrent_id=${torrentId}&file_id=${fileId}&zip_link=false`);

    if (res.data?.success && res.data?.data) {
      return res.data.data;
    }

    throw new Error(res.data?.detail || 'No se pudo obtener enlace directo de TorBox');
  }

  /**
   * Resuelve un magnet a stream directo en TorBox.
   * @param {string} magnet
   * @returns {Promise<Object>}
   */
  async resolveMagnetToStream(magnet) {
    const added = await this.addMagnet(magnet);
    const torrentId = added.torrentId;

    if (!torrentId) {
      throw new Error('No se recibió torrentId válido de TorBox');
    }

    // Esperar hasta 3 intentos breves si está en proceso de verificación
    const client = this._getAxiosClient();
    let info = null;
    for (let i = 0; i < 3; i++) {
      const res = await client.get(`/torrents/mylist?id=${torrentId}`);
      info = res.data?.data;
      if (info && (info.download_state === 'completed' || info.progress === 1)) {
        break;
      }
      await new Promise(r => setTimeout(r, 800));
    }

    if (!info || !info.files || info.files.length === 0) {
      throw new Error('El torrent no tiene archivos disponibles en TorBox');
    }

    // Filtrar archivos de video descartando CAMs
    const videoFiles = info.files.filter(f => {
      const name = f.name || f.short_name || '';
      const isVideo = /\.(mp4|mkv|avi|mov|ts|m4v)$/i.test(name);
      const isCam = CAM_REGEX.test(name);
      return isVideo && !isCam;
    });

    const chosen = videoFiles.sort((a, b) => (b.size || 0) - (a.size || 0))[0] || info.files[0];
    const streamUrl = await this.requestDownloadLink(torrentId, chosen.id);

    return {
      success: true,
      provider: 'TorBox',
      streamUrl,
      filename: chosen.name || info.name,
      filesize: chosen.size
    };
  }
}

module.exports = new TorBoxService();
