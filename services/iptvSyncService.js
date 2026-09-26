const axios = require('axios');
const fs = require('fs');
const path = require('path');

const CHANNELS_FILE = path.join(__dirname, '..', 'data', 'channels.json');

// Listas oficiales de iptv-org/iptv
const IPTV_SOURCES = [
  {
    url: 'https://iptv-org.github.io/iptv/languages/spa.m3u',
    label: 'Canales en Español (Latinoamérica y España)'
  }
];

// Mapeo inteligente de categorías de iptv-org al español para la app
const CATEGORY_MAP = {
  sports: 'Deportes',
  sport: 'Deportes',
  deportes: 'Deportes',
  news: 'Noticias',
  noticias: 'Noticias',
  movies: 'Cine & Series',
  movie: 'Cine & Series',
  series: 'Cine & Series',
  animation: 'Cine & Series',
  classic: 'Cine & Series',
  kids: 'Infantil',
  children: 'Infantil',
  family: 'Infantil',
  infantil: 'Infantil',
  music: 'Música',
  musica: 'Música',
  documentary: 'Cultura',
  culture: 'Cultura',
  science: 'Cultura',
  education: 'Cultura',
  entertainment: 'Entretenimiento',
  entretenimiento: 'Entretenimiento',
  general: 'Entretenimiento',
  comedy: 'Entretenimiento',
  lifestyle: 'Entretenimiento',
  travel: 'Entretenimiento',
  cooking: 'Entretenimiento',
  weather: 'Noticias',
  auto: 'Deportes'
};

class IptvSyncService {
  /**
   * Mapea el grupo o categoría de iptv-org a una categoría limpia en español
   */
  mapCategory(group) {
    if (!group) return 'Entretenimiento';
    const lower = group.trim().toLowerCase();
    for (const [key, value] of Object.entries(CATEGORY_MAP)) {
      if (lower.includes(key)) {
        return value;
      }
    }
    return 'Entretenimiento';
  }

  /**
   * Limpia el nombre del canal eliminando etiquetas de resolución o texto redundante
   */
  sanitizeChannelName(rawName) {
    if (!rawName) return 'Canal TV';
    return rawName
      .replace(/\s*\(\d+p\)/gi, '')
      .replace(/\s*\[\d+p\]/gi, '')
      .replace(/\s*\[Not 24\/7\]/gi, '')
      .replace(/\s*\(Not 24\/7\)/gi, '')
      .replace(/\s*\[Geo-blocked\]/gi, '')
      .replace(/\s*\(Geo-blocked\)/gi, '')
      .replace(/\s*\(Backup\)/gi, '')
      .replace(/\s*\[Backup\]/gi, '')
      .replace(/\s*\(1080p\)/gi, '')
      .replace(/\s*\(720p\)/gi, '')
      .replace(/\s*\(576p\)/gi, '')
      .replace(/\s*\(480p\)/gi, '')
      .trim();
  }

  /**
   * Determina la etiqueta de resolución aproximada
   */
  detectQuality(name, url) {
    const combined = `${name} ${url}`.toLowerCase();
    if (combined.includes('1080') || combined.includes('fhd')) return '1080p HD';
    if (combined.includes('720') || combined.includes('hd')) return '720p HD';
    if (combined.includes('4k') || combined.includes('uhd')) return '4K UHD';
    return '1080p HD';
  }

  /**
   * Descarga y parsea el archivo .m3u de iptv-org agrupando fuentes para Failover
   */
  async fetchAndProcessM3U() {
    console.log('[IptvSyncService] 📥 Descargando listas oficiales de iptv-org/iptv...');
    const channelsMap = new Map();

    for (const source of IPTV_SOURCES) {
      try {
        const response = await axios.get(source.url, {
          timeout: 25000,
          headers: {
            'User-Agent': 'VJ-STREAM-Backend/2.0.0'
          }
        });

        const lines = response.data.split('\n');
        console.log(`[IptvSyncService] Procesando ${lines.length} líneas de ${source.label}...`);

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim();
          if (!line.startsWith('#EXTINF:')) continue;

          // Buscar la URL del stream en las siguientes líneas
          let streamUrl = '';
          for (let j = i + 1; j < lines.length; j++) {
            const nextL = lines[j].trim();
            if (!nextL) continue;
            if (nextL.startsWith('#')) continue; // Ignorar directivas adicionales como #EXTVLCOPT
            if (nextL.startsWith('http://') || nextL.startsWith('https://')) {
              streamUrl = nextL;
              break;
            }
          }

          if (!streamUrl) continue;

          // Extraer metadatos con regex
          const tvgIdMatch = line.match(/tvg-id="([^"]+)"/i);
          const tvgLogoMatch = line.match(/tvg-logo="([^"]+)"/i);
          const groupMatch = line.match(/group-title="([^"]+)"/i);

          const commaIdx = line.lastIndexOf(',');
          const rawName = commaIdx !== -1 ? line.substring(commaIdx + 1).trim() : 'Canal TV';

          const tvgId = tvgIdMatch ? tvgIdMatch[1].trim() : '';
          const tvgLogo = tvgLogoMatch ? tvgLogoMatch[1].trim() : '';
          const rawGroup = groupMatch ? groupMatch[1].trim() : '';

          // Filtrar canales no deseados (adultos, compras religiosas repetitivas)
          const lowerGroup = rawGroup.toLowerCase();
          if (lowerGroup.includes('xxx') || lowerGroup.includes('adult') || lowerGroup.includes('porn')) {
            continue;
          }

          const cleanName = this.sanitizeChannelName(rawName);
          const category = this.mapCategory(rawGroup);
          const quality = this.detectQuality(rawName, streamUrl);

          // Clave única para agrupar streams del mismo canal para Failover
          // Si tiene tvg-id: e.g. "Telefe.ar@SD" -> base "telefe.ar"
          const baseKey = tvgId
            ? tvgId.split('@')[0].toLowerCase()
            : cleanName.toLowerCase().replace(/[^a-z0-9]/g, '');

          if (!baseKey) continue;

          if (!channelsMap.has(baseKey)) {
            channelsMap.set(baseKey, {
              id: 'ch_' + baseKey.replace(/[^a-z0-9_-]/g, '_'),
              name: cleanName,
              category,
              logoUrl: tvgLogo,
              streamUrl: streamUrl,
              sources: [streamUrl],
              quality,
              isActive: true
            });
          } else {
            const existing = channelsMap.get(baseKey);
            // Si la URL no está registrada, agregarla como fuente de respaldo (Failover)
            if (!existing.sources.includes(streamUrl)) {
              existing.sources.push(streamUrl);
            }
            // Si no tenía logo y este sí tiene, actualizar
            if (!existing.logoUrl && tvgLogo) {
              existing.logoUrl = tvgLogo;
            }
          }
        }
      } catch (err) {
        console.error(`[IptvSyncService] Error descargando ${source.url}:`, err.message);
      }
    }

    console.log(`[IptvSyncService] Canales únicos procesados con fuentes combinadas: ${channelsMap.size}`);
    return Array.from(channelsMap.values());
  }

  /**
   * Sincroniza y fusiona canales conservando canales curados/personalizados de channels.json
   */
  async syncAndSave() {
    // 1. Cargar canales existentes para conservar canales VIP/curados
    let existingChannels = [];
    try {
      if (fs.existsSync(CHANNELS_FILE)) {
        const raw = fs.readFileSync(CHANNELS_FILE, 'utf-8');
        existingChannels = JSON.parse(raw);
      }
    } catch (e) {
      console.warn('[IptvSyncService] No se pudo leer channels.json previo, se creará nuevo:', e.message);
    }

    // Normalizar fuentes en canales existentes
    const curatedChannels = existingChannels.map((c, idx) => {
      const sources = Array.isArray(c.sources) && c.sources.length > 0
        ? c.sources
        : (c.streamUrl ? [c.streamUrl] : []);

      return {
        ...c,
        streamUrl: sources[0] || c.streamUrl || '',
        sources,
        order: c.order || idx + 1
      };
    });

    // 2. Descargar y procesar iptv-org
    const iptvChannels = await this.fetchAndProcessM3U();

    // 3. Crear mapa de URLs existentes para evitar duplicaciones exactas
    const existingUrlSet = new Set();
    curatedChannels.forEach(c => {
      (c.sources || []).forEach(url => existingUrlSet.add(url));
      if (c.streamUrl) existingUrlSet.add(c.streamUrl);
    });

    // 4. Agregar canales de iptv-org que no estén duplicados
    let nextOrder = curatedChannels.length + 1;
    const mergedList = [...curatedChannels];

    for (const ch of iptvChannels) {
      // Filtrar fuentes que ya existan en curatedChannels
      const cleanSources = ch.sources.filter(s => !existingUrlSet.has(s));
      if (cleanSources.length === 0) continue;

      // Verificar si coincide por nombre con alguno existente para enriquecer fuentes
      const matchingExisting = mergedList.find(
        m => m.name.toLowerCase().trim() === ch.name.toLowerCase().trim()
      );

      if (matchingExisting) {
        cleanSources.forEach(s => {
          if (!matchingExisting.sources.includes(s)) {
            matchingExisting.sources.push(s);
          }
        });
        if (!matchingExisting.logoUrl && ch.logoUrl) {
          matchingExisting.logoUrl = ch.logoUrl;
        }
      } else {
        mergedList.push({
          id: ch.id,
          name: ch.name,
          category: ch.category,
          logoUrl: ch.logoUrl,
          streamUrl: cleanSources[0],
          sources: cleanSources,
          quality: ch.quality,
          isActive: true,
          order: nextOrder++
        });
      }
    }

    // 5. Guardar en data/channels.json
    const dir = path.dirname(CHANNELS_FILE);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    fs.writeFileSync(CHANNELS_FILE, JSON.stringify(mergedList, null, 2), 'utf-8');
    console.log(`[IptvSyncService] ✅ Guardados ${mergedList.length} canales en ${CHANNELS_FILE}`);

    return {
      success: true,
      total: mergedList.length,
      curatedCount: curatedChannels.length,
      iptvCount: mergedList.length - curatedChannels.length
    };
  }
}

module.exports = new IptvSyncService();
