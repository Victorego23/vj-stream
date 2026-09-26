const fs = require('fs');
const path = require('path');

const CHANNELS_FILE = path.join(__dirname, '..', 'data', 'channels.json');

class ChannelService {
  constructor() {
    this._channels = [];
    this._load();
  }

  _load() {
    try {
      if (fs.existsSync(CHANNELS_FILE)) {
        const raw = fs.readFileSync(CHANNELS_FILE, 'utf-8');
        const parsed = JSON.parse(raw);
        // Normalizar estructura de fuentes para Failover
        this._channels = (Array.isArray(parsed) ? parsed : []).map((c, idx) => {
          const sources = Array.isArray(c.sources) && c.sources.length > 0
            ? c.sources.filter(s => typeof s === 'string' && s.trim().length > 0)
            : (c.streamUrl ? [c.streamUrl.trim()] : []);

          return {
            ...c,
            streamUrl: sources[0] || c.streamUrl || '',
            sources,
            order: typeof c.order === 'number' ? c.order : idx + 1
          };
        });
      } else {
        this._channels = [];
        this._save();
      }
    } catch (err) {
      console.error('[ChannelService] Error al leer channels.json:', err.message);
      this._channels = [];
    }
  }

  reload() {
    this._load();
    return this._channels.length;
  }

  _save() {
    try {
      const dir = path.dirname(CHANNELS_FILE);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(CHANNELS_FILE, JSON.stringify(this._channels, null, 2), 'utf-8');
    } catch (err) {
      console.error('[ChannelService] Error al guardar channels.json:', err.message);
    }
  }

  /**
   * Obtiene la lista de canales activos para los clientes de la app
   * Opcionalmente filtrados por categoría
   */
  getChannels(category = null) {
    let list = this._channels.filter(c => c.isActive !== false);
    if (category && category !== 'Todos') {
      list = list.filter(c => c.category && c.category.toLowerCase() === category.toLowerCase());
    }
    // Ordenar por 'order' ascendente
    return list.sort((a, b) => (a.order || 999) - (b.order || 999));
  }

  /**
   * Obtiene todos los canales (incluidos inactivos) para el panel de administración
   */
  getAllForAdmin() {
    return [...this._channels].sort((a, b) => (a.order || 999) - (b.order || 999));
  }

  /**
   * Obtiene la lista de categorías únicas disponibles
   */
  getCategories() {
    const set = new Set();
    this._channels.forEach(c => {
      if (c.category) set.add(c.category);
    });
    return Array.from(set);
  }

  /**
   * Añade un nuevo canal de TV en vivo con soporte para múltiples fuentes (Failover)
   */
  addChannel({ name, category, logoUrl, streamUrl, sources = [], quality = '1080p HD', isActive = true }) {
    if (!name || (!streamUrl && (!Array.isArray(sources) || sources.length === 0))) {
      throw new Error('Nombre y al menos una URL de transmisión son obligatorios');
    }

    const cleanSources = Array.isArray(sources) && sources.length > 0
      ? sources.map(s => s.trim()).filter(Boolean)
      : [streamUrl.trim()];

    const id = 'ch_' + Date.now().toString(36) + '_' + Math.random().toString(36).substr(2, 4);
    const newChannel = {
      id,
      name: name.trim(),
      category: category ? category.trim() : 'Entretenimiento',
      logoUrl: logoUrl ? logoUrl.trim() : '',
      streamUrl: cleanSources[0],
      sources: cleanSources,
      quality: quality ? quality.trim() : '1080p HD',
      isActive: isActive !== false,
      order: this._channels.length + 1
    };

    this._channels.push(newChannel);
    this._save();
    return newChannel;
  }

  /**
   * Actualiza un canal existente
   */
  updateChannel(id, updates) {
    const idx = this._channels.findIndex(c => c.id === id);
    if (idx === -1) return null;

    let updatedSources = this._channels[idx].sources || [];
    if (Array.isArray(updates.sources)) {
      updatedSources = updates.sources.map(s => s.trim()).filter(Boolean);
    } else if (updates.streamUrl && !updates.sources) {
      if (!updatedSources.includes(updates.streamUrl.trim())) {
        updatedSources = [updates.streamUrl.trim(), ...updatedSources];
      }
    }

    this._channels[idx] = {
      ...this._channels[idx],
      ...updates,
      sources: updatedSources.length > 0 ? updatedSources : [updates.streamUrl || this._channels[idx].streamUrl],
      streamUrl: updatedSources[0] || updates.streamUrl || this._channels[idx].streamUrl,
      id // Garantizar inmutabilidad de id
    };

    this._save();
    return this._channels[idx];
  }

  /**
   * Alterna estado activo/inactivo de un canal
   */
  toggleChannel(id) {
    const ch = this._channels.find(c => c.id === id);
    if (!ch) return null;
    ch.isActive = !ch.isActive;
    this._save();
    return ch;
  }

  /**
   * Elimina un canal
   */
  deleteChannel(id) {
    const initialLen = this._channels.length;
    this._channels = this._channels.filter(c => c.id !== id);
    if (this._channels.length !== initialLen) {
      this._save();
      return true;
    }
    return false;
  }

  /**
   * Ejecuta la sincronización con iptv-org y recarga los canales en memoria
   */
  async syncFromIptvOrg() {
    const iptvSyncService = require('./iptvSyncService');
    const result = await iptvSyncService.syncAndSave();
    this._load();
    return result;
  }
}

module.exports = new ChannelService();
