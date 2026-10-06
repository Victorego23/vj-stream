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
   * Genera dinámicamente la información EPG (programa actual y siguiente)
   * calculada según la hora del día y la temática del canal.
   */
  getChannelEpg(channel) {
    const now = new Date();
    const currentHour = now.getHours();
    const currentMinute = now.getMinutes();
    const currentTotalMinutes = currentHour * 60 + currentMinute;

    const cat = (channel.category || '').toLowerCase();
    const name = (channel.name || '').toLowerCase();

    let schedules = [];

    if (name.includes('telemundo') || name.includes('novela')) {
      schedules = [
        { start: '00:00', end: '03:00', title: 'El Señor de los Cielos - Maratón Nocturna' },
        { start: '03:00', end: '06:00', title: 'Telenovela: Pasión de Gavilanes' },
        { start: '06:00', end: '09:00', title: 'Doctor Milagro - Episodios Matutinos' },
        { start: '09:00', end: '12:00', title: 'La Reina del Sur - Temporada Completa' },
        { start: '12:00', end: '15:00', title: 'El Señor de los Cielos - Temporada 9' },
        { start: '15:00', end: '18:00', title: 'Café con Aroma de Mujer' },
        { start: '18:00', end: '21:00', title: 'Tierra Amarga (Telenovela Estelar)' },
        { start: '21:00', end: '24:00', title: 'El Señor de los Cielos - Emisión Central' }
      ];
    } else if (cat.includes('deporte') || name.includes('espn') || name.includes('liga') || name.includes('fox')) {
      schedules = [
        { start: '00:00', end: '06:00', title: 'Lo Mejor de la Jornada Deportiva' },
        { start: '06:00', end: '10:00', title: 'SportsCenter Matutino (Noticias y Goles)' },
        { start: '10:00', end: '13:00', title: 'Fútbol en Vivo / Debate en el Estudio' },
        { start: '13:00', end: '16:00', title: 'Transmisión de Liga Internacional en Directo' },
        { start: '16:00', end: '19:00', title: 'Fútbol en Vivo: Partido de la Fecha' },
        { start: '19:00', end: '21:30', title: 'Post-Partido, Análisis y Estadísticas' },
        { start: '21:30', end: '24:00', title: 'SportsCenter Noche / Equipo F' }
      ];
    } else if (cat.includes('infantil') || name.includes('disney') || name.includes('cartoon') || name.includes('nick')) {
      schedules = [
        { start: '00:00', end: '06:00', title: 'Maratón de Clásicos Animados' },
        { start: '06:00', end: '09:00', title: 'Despierta con Dibujos Animados' },
        { start: '09:00', end: '12:00', title: 'Series Animadas Infantiles y Aventuras' },
        { start: '12:00', end: '15:00', title: 'Película Animada Familiar' },
        { start: '15:00', end: '18:00', title: 'Nuevos Episodios: Bloque Divertido' },
        { start: '18:00', end: '21:00', title: 'Cine Mágico Infantil' },
        { start: '21:00', end: '24:00', title: 'Aventuras Nocturnas Animadas' }
      ];
    } else if (cat.includes('cine') || cat.includes('serie') || name.includes('hbo') || name.includes('tnt') || name.includes('warner') || name.includes('star')) {
      schedules = [
        { start: '00:00', end: '03:00', title: 'Cine de Medianoche: Suspenso y Acción' },
        { start: '03:00', end: '06:00', title: 'Cine Clásico / Repetición Especial' },
        { start: '06:00', end: '09:00', title: 'Comedia de la Mañana' },
        { start: '09:00', end: '12:00', title: 'Maratón de Series Populares' },
        { start: '12:00', end: '15:00', title: 'Cine Familiar de la Tarde' },
        { start: '15:00', end: '18:00', title: 'Película Taquillera de Acción' },
        { start: '18:00', end: '21:00', title: 'Estreno del Mes: Bloque Élite' },
        { start: '21:00', end: '24:00', title: 'Cine Estelar: Gran Película de la Noche' }
      ];
    } else {
      schedules = [
        { start: '00:00', end: '06:00', title: 'Programación Especial de Madrugada' },
        { start: '06:00', end: '12:00', title: 'Magazine Matinal en Vivo' },
        { start: '12:00', end: '18:00', title: 'Tarde de Entretenimiento' },
        { start: '18:00', end: '24:00', title: 'Horario Estelar: Emisión Principal' }
      ];
    }

    const toMinutes = (timeStr) => {
      const [h, m] = timeStr.split(':').map(Number);
      return h * 60 + m;
    };

    let current = null;
    let next = null;

    for (let i = 0; i < schedules.length; i++) {
      const s = schedules[i];
      const startMin = toMinutes(s.start);
      const endMin = toMinutes(s.end);
      if (currentTotalMinutes >= startMin && currentTotalMinutes < endMin) {
        current = s;
        next = schedules[(i + 1) % schedules.length];
        break;
      }
    }

    if (!current) {
      current = schedules[0];
      next = schedules[1] || schedules[0];
    }

    const startMin = toMinutes(current.start);
    const endMin = toMinutes(current.end);
    const duration = endMin - startMin;
    const elapsed = Math.max(0, currentTotalMinutes - startMin);
    const progress = duration > 0 ? Math.min(1.0, elapsed / duration) : 0.5;

    return {
      currentProgram: current.title,
      programTime: `${current.start} - ${current.end}`,
      programProgress: Math.round(progress * 100) / 100,
      nextProgram: next ? `${next.title} (${next.start})` : null
    };
  }

  /**
   * Obtiene la lista de canales activos para los clientes de la app
   * Opcionalmente filtrados por categoría e integrados con EPG en vivo
   */
  getChannels(category = null, withEpg = true) {
    let list = this._channels.filter(c => c.isActive !== false);
    if (category && category !== 'Todos') {
      list = list.filter(c => c.category && c.category.toLowerCase() === category.toLowerCase());
    }
    // Ordenar por 'order' ascendente
    const sorted = list.sort((a, b) => (a.order || 999) - (b.order || 999));
    if (!withEpg) return sorted;

    return sorted.map(c => ({
      ...c,
      ...this.getChannelEpg(c)
    }));
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
    const cats = Array.from(set);
    const orderPriority = {
      'Deportes': 1,
      'Cine & Series': 2,
      'Infantil': 3,
      'Telenovelas': 4,
      'Entretenimiento': 5,
      'Noticias': 6,
      'Música': 7,
      'Cultura': 8
    };
    cats.sort((a, b) => {
      const pA = orderPriority[a] || 99;
      const pB = orderPriority[b] || 99;
      if (pA !== pB) return pA - pB;
      return a.localeCompare(b);
    });
    return cats;
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
