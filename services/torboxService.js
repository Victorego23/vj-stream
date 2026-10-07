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
    this._authError = false;
  }

  /**
   * Obtiene la clave de API activa de TorBox desde las variables de entorno.
   * @returns {string|null}
   */
  getApiKey() {
    const key = (process.env.TORBOX_API_KEY || '').trim();
    if (!key || key === '4a49eb84-49f8-4acf-b93b-b6754c53093d' || key === 'dc49cb4d-f89d-403e-8826-c490edff6fa7') {
      return '11a9b153-866d-444a-b4a3-c4edd5ca1d11';
    }
    return key;
  }

  /**
   * Indica si TorBox está configurado y listo para ser utilizado como Base 1.
   * Si la suscripción de TorBox venció o la clave devuelve 403, se desactiva
   * automáticamente para transferir todo el tráfico a Real-Debrid Base 2.
   * @returns {boolean}
   */
  isAvailable() {
    return Boolean(this.getApiKey()) && !this._authError;
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
      timeout: 20000 // Timeout ampliado a 20 segundos con tolerancia a picos de red
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
   * Identifica el archivo exacto correspondiente a un episodio dentro de un torrent multi-archivo (Batch).
   * Soporta anime, series occidentales, packs de temporadas completas y diferentes convenciones de nombres.
   * @param {Array} videoFiles - Lista de archivos de video disponibles
   * @param {number} targetSeason - Temporada buscada (default 1)
   * @param {number} targetEp - Episodio buscado (default 1)
   * @returns {Object|null} Archivo seleccionado
   */
  _matchEpisodeInBatch(videoFiles, targetSeason = 1, targetEp = 1) {
    if (!Array.isArray(videoFiles) || videoFiles.length === 0) return null;
    if (videoFiles.length === 1) return videoFiles[0];

    const s = parseInt(targetSeason, 10) || 1;
    const e = parseInt(targetEp, 10) || 1;
    const pad2 = String(e).padStart(2, '0');
    const pad3 = String(e).padStart(3, '0');

    // Descartar archivos ubicados en carpetas de OTRA temporada si es pack multi-temporada
    const validSeasonFiles = videoFiles.filter(f => {
      const name = (f.name || f.short_name || '').toLowerCase();
      const seasonFolderMatch = name.match(/(?:season|temporada|temp|s)\s*0*(\d{1,2})/i);
      if (seasonFolderMatch) {
        const folderSeason = parseInt(seasonFolderMatch[1], 10);
        if (folderSeason !== s) return false;
      }
      return true;
    });

    const candidates = validSeasonFiles.length > 0 ? validSeasonFiles : videoFiles;

    // NIVEL 1: Notación estándar SxxExx o 1x01 o SxEx
    for (const f of candidates) {
      const name = (f.name || f.short_name || '').toLowerCase();
      const seMatch = name.match(/\bs?0*(\d{1,2})[.\s_-]*[ex]0*(\d{1,3})\b/i);
      if (seMatch) {
        const matchSeason = parseInt(seMatch[1], 10);
        const matchEp = parseInt(seMatch[2], 10);
        if (matchSeason === s && matchEp === e) {
          return f;
        }
      }
    }

    // NIVEL 2: Prefijos y palabras clave de episodio (Anime / Animación / Pokémon / Telenovelas)
    // Ej: "Pokemon - 01", "Pokemon Ep 01", "Pokemon Cap 01", "Pokemon - 001", "Pokemon [01]"
    const epKeywordPatterns = [
      new RegExp(`(?:ep|episode|episodio|cap|capitulo|capítulo)[.\\s_-]*0*${e}\\b`, 'i'),
      new RegExp(`[\\[\\(\\s_-]0*${e}[\\]\\)\\s_.-]`, 'i'),
      new RegExp(`^[\\s_-]*0*${e}[.\\s_-]`, 'i'),
      new RegExp(`[/\\\\][\\s_-]*0*${e}[.\\s_-]`, 'i'),
      new RegExp(`[-_\\s]0*${e}\\.[a-z0-9]+$`, 'i'),
      new RegExp(`\\b(?:${pad2}|${pad3})\\b`, 'i')
    ];

    for (const pattern of epKeywordPatterns) {
      const matched = candidates.find(f => {
        const name = (f.name || f.short_name || '').toLowerCase();
        // Limpiar resolución (1080p, 720p), año y codecs para evitar falsos positivos
        const clean = name.replace(/1080p?|720p?|480p?|x264|x265|h264|h265|19\d{2}|20\d{2}/gi, ' ');
        return pattern.test(clean);
      });
      if (matched) return matched;
    }

    // NIVEL 3: Orden natural por índice de episodio si los archivos están numerados correlativamente
    const sorted = [...candidates].sort((a, b) => (a.name || '').localeCompare(b.name || ''));
    if (e >= 1 && e <= sorted.length) {
      return sorted[e - 1];
    }

    return candidates[0];
  }

  /**
   * Resuelve un magnet a stream directo en el CDN de TorBox.
   * Cero consumo de RAM/búfer en Render: solo orquesta metadatos y entrega la URL CDN.
   * En torrents batch de múltiples archivos (como series y anime), filtra y obtiene el file_id exacto.
   * @param {string} magnet - Magnet link o hash
   * @param {Object} [options] - Opciones (season, episode, fileId, file_id)
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

    // Consultar detalles con bypass_cache=true para estado fidedigno (hasta 5 intentos con tolerancia)
    for (let i = 0; i < 5; i++) {
      try {
        const res = await client.get(`/torrents/mylist?id=${torrentId}&bypass_cache=true`);
        info = res.data?.data;
        if (info && (info.download_state === 'completed' || info.download_state === 'cached' || info.progress === 1)) {
          break;
        }
      } catch (pollErr) {
        console.warn(`[TorBox] Intento ${i + 1} de consulta mylist falló:`, pollErr.message);
      }
      await new Promise(r => setTimeout(r, 800));
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

    // Filtrar archivos de video descartando grabaciones de cine (CAM)
    const videoFiles = files.filter(f => {
      const name = (f.name || f.short_name || '').toLowerCase();
      const isVideo = /\.(mp4|mkv|avi|mov|ts|m4v|webm)$/i.test(name);
      const isCam = CAM_REGEX.test(name);
      return isVideo && !isCam;
    });

    let chosen = null;
    const explicitFileId = options.fileId ?? options.file_id;

    // 1. Si se especificó un file_id exacto en las opciones, usarlo directamente
    if (explicitFileId != null) {
      chosen = files.find(f => String(f.id) === String(explicitFileId));
    }

    // 2. Si es serie / episodio y no vino file_id explícito: buscar el archivo exacto del episodio
    if (!chosen && options && options.episode) {
      const targetEp = parseInt(options.episode, 10);
      const targetSeason = parseInt(options.season, 10) || 1;
      chosen = this._matchEpisodeInBatch(videoFiles, targetSeason, targetEp);
      if (chosen) {
        console.log(`[TorBox Batch Parser] 🎯 Episodio seleccionado: "${chosen.name || chosen.short_name}" (file_id: ${chosen.id}) para S${targetSeason}E${targetEp}`);
      }
    }

    // 3. Si no es serie o no hubo match de episodio: seleccionar el archivo de video de mayor tamaño
    if (!chosen) {
      chosen = videoFiles.sort((a, b) => (b.size || 0) - (a.size || 0))[0] || files[0];
    }

    if (!chosen) {
      throw new Error('No se encontró ningún archivo de video compatible en el torrent');
    }

    // 4. Solicitar URL de streaming directa del CDN de TorBox para el file_id exacto
    const targetFileId = chosen.id;
    const streamUrl = await this.requestDownloadLink(torrentId, targetFileId);

    return {
      success: true,
      ready: true,
      provider: 'TorBox',
      torrentId,
      fileId: targetFileId,
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
      if (err.response?.status === 403 || err.response?.status === 401) {
        this._authError = true;
        console.warn(`[TorBox Auto-Clean] ⚠️ La clave de TorBox devolvió código ${err.response.status} (Suscripción inactiva o clave no autorizada). Pausando TorBox y conmutando automáticamente todo el streaming a Real-Debrid.`);
        return 0;
      }
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

