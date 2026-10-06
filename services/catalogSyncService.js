const fs = require('fs');
const path = require('path');
const tmdbService = require('./tmdbService');
const streamResolverService = require('./streamResolverService');

const DATA_DIR = path.resolve(__dirname, '..', 'data');
const CATALOG_CACHE_FILE = path.resolve(DATA_DIR, 'catalog_cache.json');

/**
 * Servicio Autónomo de Sincronización y Actualización Continua del Catálogo para TOM TV.
 * - Mantiene actualizadas las películas en cartelera, estrenos digitales, series y telenovelas.
 * - Pre-verifica proactivamente la disponibilidad de transmisiones en Español Latino/Castellano en Real-Debrid.
 * - Desbloquea títulos automáticamente en cuanto aparece su versión digital doblada.
 * - Entrega respuestas ultrarrápidas (< 5ms) a Smart TVs y clientes móviles desde caché persistente en disco.
 */
class CatalogSyncService {
  constructor() {
    this.isSyncing = false;
    this.lastSyncAt = null;
    this.syncStats = {
      totalMovies: 0,
      totalSeries: 0,
      verifiedSpanishCount: 0,
      lastDurationMs: 0
    };
    this.cachedCatalog = null;
    this.cachedKids = null;
    this.cachedNovelas = null;
    this.cachedSports = null;

    // Intervalo de sincronización periódica: cada 2 horas
    this.SYNC_INTERVAL_MS = 2 * 60 * 60 * 1000;
    this.timer = null;

    // Cargar caché previo desde disco al instanciar
    this._loadFromDisk();
  }

  /**
   * Carga el catálogo persistido previamente desde disco para arranque en 0ms.
   * @private
   */
  _loadFromDisk() {
    try {
      if (fs.existsSync(CATALOG_CACHE_FILE)) {
        const raw = fs.readFileSync(CATALOG_CACHE_FILE, 'utf-8');
        const parsed = JSON.parse(raw);
        if (parsed && parsed.catalog) {
          this.cachedCatalog = parsed.catalog;
          this.cachedKids = parsed.kids || null;
          this.cachedNovelas = parsed.novelas || null;
          this.cachedSports = parsed.sports || null;
          this.lastSyncAt = parsed.savedAt ? new Date(parsed.savedAt) : new Date();
          this.syncStats = parsed.stats || this.syncStats;
          console.log(`[CatalogSyncService] 📦 Catálogo precargado desde disco (${parsed.savedAt || 'reciente'}).`);
        }
      }
    } catch (err) {
      console.warn('[CatalogSyncService] Advertencia al leer catalog_cache.json:', err.message);
    }
  }

  /**
   * Guarda el estado del catálogo en disco para tolerancia a reinicios.
   * @private
   */
  _saveToDisk() {
    try {
      if (!fs.existsSync(DATA_DIR)) {
        fs.mkdirSync(DATA_DIR, { recursive: true });
      }
      const payload = {
        savedAt: new Date().toISOString(),
        stats: this.syncStats,
        catalog: this.cachedCatalog,
        kids: this.cachedKids,
        novelas: this.cachedNovelas,
        sports: this.cachedSports
      };
      fs.writeFileSync(CATALOG_CACHE_FILE, JSON.stringify(payload, null, 2), 'utf-8');
      console.log(`[CatalogSyncService] 💾 Catálogo actualizado y guardado en disco exitosamente.`);
    } catch (err) {
      console.error('[CatalogSyncService] Error al guardar catalog_cache.json:', err.message);
    }
  }

  /**
   * Inicia el proceso de sincronización automática en segundo plano.
   */
  startBackgroundWorker() {
    console.log(`[CatalogSyncService] 🚀 Motor autónomo de actualización iniciado (Ciclo: cada 2 horas).`);

    // Ejecutar primera sincronización 5 segundos después de que el servidor esté en pie
    setTimeout(() => {
      this.syncCatalog().catch(err => {
        console.warn('[CatalogSyncService] Error en primera sincronización:', err.message);
      });
    }, 5000);

    // Programar ciclo recurrente continuo
    if (this.timer) clearInterval(this.timer);
    this.timer = setInterval(() => {
      console.log(`[CatalogSyncService] ⏰ Iniciando ciclo programado de actualización de catálogo...`);
      this.syncCatalog().catch(err => {
        console.warn('[CatalogSyncService] Error en ciclo programado:', err.message);
      });
    }, this.SYNC_INTERVAL_MS);
  }

  /**
   * Sincroniza y actualiza todo el catálogo de películas, series, kids y novelas.
   * @param {boolean} [force=false]
   * @returns {Promise<Object>}
   */
  async syncCatalog(force = false) {
    if (this.isSyncing) {
      console.log('[CatalogSyncService] ⏳ Ya hay una sincronización en progreso. Omitiendo.');
      return this.cachedCatalog;
    }

    this.isSyncing = true;
    const startTime = Date.now();
    console.log('[CatalogSyncService] 🔄 Iniciando actualización profunda del catálogo desde TMDB...');

    try {
      // 1. Obtener catálogo completo desduplicado desde TMDB (forzando bypass de caché de TMDB si es force)
      if (force) {
        tmdbService.cache.delete('full_catalog');
      }
      const fullCatalog = await tmdbService.getFullCatalog();

      // 2. Obtener catálogos temáticos en paralelo
      const [kidsRes, novelasRes, sportsRes] = await Promise.allSettled([
        tmdbService.getKidsCatalog(),
        tmdbService.getTelenovelasCatalog(),
        tmdbService.getActionSportsCatalog()
      ]);

      const kidsData = kidsRes.status === 'fulfilled' ? kidsRes.value : this.cachedKids;
      const novelasData = novelasRes.status === 'fulfilled' ? novelasRes.value : this.cachedNovelas;
      const sportsData = sportsRes.status === 'fulfilled' ? sportsRes.value : this.cachedSports;

      // 3. Pre-verificación de disponibilidad en Español en segundo plano para las películas más populares
      // Evaluamos los primeros 8 títulos de Tendencias y Estrenos para marcarlos como 100% listos
      let verifiedCount = 0;
      const topItemsToCheck = [
        ...(fullCatalog.nowPlaying || []).slice(0, 5),
        ...(fullCatalog.trending || []).slice(0, 5)
      ];

      for (const item of topItemsToCheck) {
        try {
          const avail = await streamResolverService.checkSpanishAvailability(item);
          if (avail && avail.available) {
            item.hasSpanishStream = true;
            item.streamQuality = avail.qualityLabel || '1080p FHD';
            verifiedCount++;
          }
        } catch (_) {}
      }

      // Calcular conteos globales
      let moviesCount = 0;
      let seriesCount = 0;

      Object.entries(fullCatalog).forEach(([catKey, list]) => {
        if (Array.isArray(list)) {
          if (catKey === 'series') {
            seriesCount += list.length;
          } else {
            moviesCount += list.length;
          }
        }
      });

      const durationMs = Date.now() - startTime;
      this.cachedCatalog = fullCatalog;
      this.cachedKids = kidsData;
      this.cachedNovelas = novelasData;
      this.cachedSports = sportsData;
      this.lastSyncAt = new Date();
      this.syncStats = {
        totalMovies: moviesCount,
        totalSeries: seriesCount,
        verifiedSpanishCount: verifiedCount,
        lastDurationMs: durationMs
      };

      // Guardar el nuevo snapshot en disco
      this._saveToDisk();

      console.log(`[CatalogSyncService] ✅ Sincronización completada en ${(durationMs / 1000).toFixed(1)}s: ${moviesCount} películas, ${seriesCount} series (${verifiedCount} con stream verificado).`);
      return fullCatalog;
    } catch (error) {
      console.error('[CatalogSyncService] ❌ Error durante sincronización:', error.message);
      throw error;
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Obtiene el catálogo consolidado listo para entregar a las aplicaciones cliente.
   * Si no está en memoria, intenta cargarlo de disco o generar uno fresco.
   * @returns {Promise<Object>}
   */
  async getCatalog() {
    if (this.cachedCatalog) {
      return this.cachedCatalog;
    }
    // Si aún no está en memoria, invocar sincronización inmediata
    return await this.syncCatalog();
  }

  /**
   * Obtiene el catálogo especializado para niños
   */
  async getKidsCatalog() {
    if (this.cachedKids) return this.cachedKids;
    return await tmdbService.getKidsCatalog();
  }

  /**
   * Obtiene el catálogo especializado de telenovelas y k-dramas
   */
  async getTelenovelasCatalog() {
    if (this.cachedNovelas) return this.cachedNovelas;
    return await tmdbService.getTelenovelasCatalog();
  }

  /**
   * Obtiene el catálogo especializado de acción y deportes
   */
  async getActionSportsCatalog() {
    if (this.cachedSports) return this.cachedSports;
    return await tmdbService.getActionSportsCatalog();
  }

  /**
   * Devuelve el estado actual de la sincronización y salud del catálogo.
   */
  getStatus() {
    const nextSyncMin = this.lastSyncAt
      ? Math.max(0, Math.round((this.lastSyncAt.getTime() + this.SYNC_INTERVAL_MS - Date.now()) / (1000 * 60)))
      : 0;

    return {
      status: this.isSyncing ? 'syncing' : 'ready',
      lastSyncAt: this.lastSyncAt ? this.lastSyncAt.toISOString() : null,
      nextSyncInMinutes: nextSyncMin,
      stats: this.syncStats
    };
  }
}

module.exports = new CatalogSyncService();
