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
        this._channels = JSON.parse(raw);
      } else {
        this._channels = [];
        this._save();
      }
    } catch (err) {
      console.error('[ChannelService] Error al leer channels.json:', err.message);
      this._channels = [];
    }
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
   * Añade un nuevo canal de TV en vivo
   */
  addChannel({ name, category, logoUrl, streamUrl, quality = '1080p HD', isActive = true }) {
    if (!name || !streamUrl) {
      throw new Error('Nombre y URL de transmisión son obligatorios');
    }

    const id = 'ch_' + Date.now().toString(36) + '_' + Math.random().toString(36).substr(2, 4);
    const newChannel = {
      id,
      name: name.trim(),
      category: category ? category.trim() : 'Entretenimiento',
      logoUrl: logoUrl ? logoUrl.trim() : '',
      streamUrl: streamUrl.trim(),
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

    this._channels[idx] = {
      ...this._channels[idx],
      ...updates,
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
}

module.exports = new ChannelService();
