const express = require('express');
const router = express.Router();
const axios = require('axios');
const realDebridService = require('../services/realDebridService');
const torboxService = require('../services/torboxService');
const tmdbService = require('../services/tmdbService');
const streamResolverService = require('../services/streamResolverService');
const channelService = require('../services/channelService');
const accountService = require('../services/accountService');
const catalogSyncService = require('../services/catalogSyncService');
const movieDatabaseService = require('../services/movieDatabaseService');
const movieIngestionService = require('../services/movieIngestionService');
const hmacSecurityMiddleware = require('../middlewares/hmacSecurityMiddleware');

// Blindaje de seguridad: Solo la app oficial VJ STREAM puede acceder a los servicios
router.use(hmacSecurityMiddleware);

/**
 * ====================================================================
 * RUTAS DE CATÁLOGO Y METADATOS (TMDB & CATALOG SYNC SERVICE)
 * ====================================================================
 */

/**
 * @route   GET /api/streaming/catalog
 * @desc    Obtiene el catálogo consolidado sincronizado continuamente en segundo plano (0ms de latencia)
 */
router.get('/catalog', async (req, res, next) => {
  try {
    const catalog = await catalogSyncService.getCatalog();
    return res.json({
      success: true,
      app: 'TOM TV',
      data: catalog
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/catalog/status
 * @desc    Devuelve el estado de la sincronización continua y salud del catálogo
 */
router.get('/catalog/status', (req, res) => {
  return res.json({
    success: true,
    ...catalogSyncService.getStatus()
  });
});

/**
 * @route   POST /api/streaming/catalog/refresh
 * @desc    Fuerza la actualización inmediata del catálogo completo en segundo plano
 */
router.post('/catalog/refresh', async (req, res, next) => {
  try {
    const fresh = await catalogSyncService.syncCatalog(true);
    return res.json({
      success: true,
      message: 'Catálogo sincronizado y actualizado exitosamente.',
      stats: catalogSyncService.getStatus().stats
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/catalog/kids
 * @desc    Obtiene el catálogo especializado para Niños (Películas animadas, dibujos animados y anime infantil)
 */
router.get('/catalog/kids', async (req, res, next) => {
  try {
    const catalog = await catalogSyncService.getKidsCatalog();
    return res.json({
      success: true,
      app: 'TOM TV',
      data: catalog
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/catalog/telenovelas
 * @desc    Obtiene el catálogo especializado de Telenovelas (Latinas, Turcas y K-Dramas)
 */
router.get('/catalog/telenovelas', async (req, res, next) => {
  try {
    const catalog = await catalogSyncService.getTelenovelasCatalog();
    return res.json({
      success: true,
      app: 'TOM TV',
      data: catalog
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/catalog/action-sports
 * @desc    Obtiene el catálogo de Películas de Acción y Deportes para el público general
 */
router.get('/catalog/action-sports', async (req, res, next) => {
  try {
    const catalog = await catalogSyncService.getActionSportsCatalog();
    return res.json({
      success: true,
      app: 'TOM TV',
      data: catalog
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/catalog/infinite
 * @desc    Obtiene nuevas filas y colecciones de películas dinámicas para scroll infinito
 * @query   page {number} - Página actual de scroll infinito (default 1)
 */
router.get('/catalog/infinite', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const categories = await tmdbService.getInfiniteCategories(page);
    return res.json({
      success: true,
      page,
      categories
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/movies/years
 * @desc    Devuelve el catálogo de años disponibles para explorar (2026 hasta 2000)
 */
router.get('/movies/years', (req, res) => {
  const currentYear = new Date().getFullYear();
  const maxYear = Math.max(currentYear, 2026);
  const years = [];
  for (let y = maxYear; y >= 2000; y--) {
    years.push(y);
  }
  return res.json({
    success: true,
    years
  });
});

/**
 * @route   GET /api/streaming/movies/by-year/:year
 * @desc    Obtiene las películas de un año específico (2000 a 2026) con paginación
 * @param   year {number} - Año de estreno (2000-2026)
 * @query   page {number} - Página actual (default 1)
 */
router.get('/movies/by-year/:year', async (req, res, next) => {
  try {
    const year = parseInt(req.params.year, 10);
    const page = parseInt(req.query.page, 10) || 1;

    if (isNaN(year) || year < 1950 || year > 2030) {
      return res.status(400).json({
        success: false,
        error: 'El año proporcionado no es válido (rango admitido: 2000 - 2026).'
      });
    }

    const movies = await tmdbService.getMoviesByYear(year, page);
    return res.json({
      success: true,
      year,
      page,
      movies
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/genres
 * @desc    Devuelve la lista oficial de géneros cinematográficos con íconos
 */
router.get('/genres', (req, res) => {
  const genres = tmdbService.getGenresList();
  return res.json({
    success: true,
    genres
  });
});

/**
 * @route   GET /api/streaming/movies/by-genre/:genreId
 * @desc    Obtiene películas filtradas por género con paginación
 */
router.get('/movies/by-genre/:genreId', async (req, res, next) => {
  try {
    const genreId = parseInt(req.params.genreId, 10);
    const page = parseInt(req.query.page, 10) || 1;

    if (isNaN(genreId)) {
      return res.status(400).json({ success: false, error: 'ID de género no válido.' });
    }

    const movies = await tmdbService.getMoviesByGenre(genreId, page);
    return res.json({
      success: true,
      genreId,
      page,
      movies
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/vod/explorer
 * @desc    Explorador masivo de películas con soporte para filtros por Género, Año, Década, Plataforma, Saga, Búsqueda y Paginación
 */
router.get('/vod/explorer', async (req, res, next) => {
  try {
    const {
      page = 1,
      limit = 30,
      genreId,
      year,
      minYear,
      maxYear,
      platform,
      collectionName,
      sortBy = 'popularity.desc',
      search
    } = req.query;

    // 1. Si MongoDB está conectado y tiene películas, consultar MongoDB
    if (movieDatabaseService.isConnected()) {
      const data = await movieDatabaseService.getMoviesExplorer({
        page,
        limit,
        genreId,
        year,
        minYear,
        maxYear,
        platform,
        collectionName,
        sortBy,
        search
      });

      if (data && data.results && data.results.length > 0) {
        return res.json({
          success: true,
          source: 'mongodb',
          app: 'TOM TV',
          ...data
        });
      }
    }

    // 2. Respaldo de contingencia en tiempo real vía TMDB API si la BD aún está poblándose
    const safePage = Math.max(1, parseInt(page, 10) || 1);
    let tmdbResults = [];
    if (search && search.trim().length > 0) {
      const sRes = await tmdbService.searchMedia(search.trim(), { type: 'movie', page: safePage });
      tmdbResults = sRes?.results || [];
    } else {
      const params = {
        sort_by: sortBy,
        page: safePage,
        'vote_count.gte': 15
      };
      if (genreId) params.with_genres = genreId;
      if (year) params.primary_release_year = year;
      if (minYear) params['primary_release_date.gte'] = `${minYear}-01-01`;
      if (maxYear) params['primary_release_date.lte'] = `${maxYear}-12-31`;

      const dRes = await tmdbService.discoverMovie(params);
      tmdbResults = Array.isArray(dRes) ? dRes : (dRes?.results || []);
    }

    return res.json({
      success: true,
      source: 'tmdb_fallback',
      app: 'TOM TV',
      page: safePage,
      totalPages: 500,
      totalResults: 10000,
      results: tmdbResults
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/vod/collections
 * @desc    Obtiene las sagas y franquicias cinematográficas más populares del cine mundial
 */
router.get('/vod/collections', async (req, res, next) => {
  try {
    let collections = [];
    if (movieDatabaseService.isConnected()) {
      collections = await movieDatabaseService.getCollectionsList();
    }

    // Si aún está poblándose MongoDB, proveer catálogo inicial de respaldo de las sagas principales
    if (!collections || collections.length === 0) {
      collections = [
        { name: 'Universo Cinematográfico de Marvel', count: 34, posterUrl: 'https://image.tmdb.org/t/p/w500/yFSIUVTCvgYr05wtNx25zXn62iN.jpg', rating: 8.2 },
        { name: 'Universo Extendido de DC', count: 16, posterUrl: 'https://image.tmdb.org/t/p/w500/8tABrG6s9zL1j1C8C0q8Gv1a3B2.jpg', rating: 7.6 },
        { name: 'Saga Harry Potter & Mundo Mágico', count: 11, posterUrl: 'https://image.tmdb.org/t/p/w500/wuMc08IPKEatf9rnMNXvIDxqP4W.jpg', rating: 8.3 },
        { name: 'Saga Star Wars', count: 12, posterUrl: 'https://image.tmdb.org/t/p/w500/6FfCtAuVAW8XJjZ7eWeLibRLWTw.jpg', rating: 8.1 },
        { name: 'Saga El Señor de los Anillos', count: 6, posterUrl: 'https://image.tmdb.org/t/p/w500/6oom5QYQ2yQTMJIbnvbkBL9cDK6.jpg', rating: 8.9 },
        { name: 'Saga Rápidos y Furiosos', count: 11, posterUrl: 'https://image.tmdb.org/t/p/w500/fiVW06jE7z9YnO4trhaMEdclSiC.jpg', rating: 7.4 },
        { name: 'Clásicos Animados Disney & Pixar', count: 48, posterUrl: 'https://image.tmdb.org/t/p/w500/vpnVM9B6NMmQpWeZvzLvDESb2QY.jpg', rating: 8.5 },
        { name: 'Saga John Wick', count: 4, posterUrl: 'https://image.tmdb.org/t/p/w500/vZloFAK7NKnMGKEslUsZlooxAcR.jpg', rating: 8.0 },
        { name: 'Saga Misión Imposible', count: 7, posterUrl: 'https://image.tmdb.org/t/p/w500/NNxYkU70HPurnNCSiCjYAmacwm.jpg', rating: 7.9 },
        { name: 'Saga Shrek', count: 6, posterUrl: 'https://image.tmdb.org/t/p/w500/iB64vpL3dIObOtMZg3vUVho9x45.jpg', rating: 8.1 }
      ];
    }

    return res.json({
      success: true,
      app: 'TOM TV',
      total: collections.length,
      collections
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/vod/platforms
 * @desc    Lista de plataformas de streaming con identificadores para filtro
 */
router.get('/vod/platforms', (req, res) => {
  return res.json({
    success: true,
    platforms: [
      { id: 'todas', name: 'Todas las Películas', icon: 'movie' },
      { id: 'netflix', name: 'Netflix', icon: 'netflix', color: '0xFFE50914' },
      { id: 'disney+', name: 'Disney+', icon: 'disney', color: '0xFF113CCF' },
      { id: 'max', name: 'Max (HBO)', icon: 'max', color: '0xFF002BE7' },
      { id: 'prime video', name: 'Prime Video', icon: 'prime', color: '0xFF00A8E1' },
      { id: 'apple tv+', name: 'Apple TV+', icon: 'apple', color: '0xFFFFFFFF' },
      { id: 'paramount+', name: 'Paramount+', icon: 'paramount', color: '0xFF0064FF' }
    ]
  });
});

/**
 * @route   POST /api/streaming/vod/sync
 * @desc    Dispara la sincronización o ingesta masiva de catálogo en segundo plano
 */
router.post('/vod/sync', async (req, res, next) => {
  try {
    const pages = parseInt(req.body.pages, 10) || 20;
    movieIngestionService.runMassiveIngestion(pages).catch(console.error);
    return res.json({
      success: true,
      message: `Ingesta masiva iniciada en segundo plano (${pages} páginas por categoría).`
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/search
 * @desc    Busca películas y series en TMDB con sinopsis y carátulas
 * @query   q {string} - Término de búsqueda
 * @query   type {'multi'|'movie'|'tv'} - Tipo de búsqueda (opcional, default 'multi')
 * @query   page {number} - Número de página (opcional, default 1)
 */
router.get('/search', async (req, res, next) => {
  try {
    const { q, query, type = 'multi', page = 1 } = req.query;
    const searchTerm = q || query;

    if (!searchTerm) {
      return res.status(400).json({
        success: false,
        error: 'El parámetro de consulta "q" o "query" es requerido.'
      });
    }

    const data = await tmdbService.searchMedia(searchTerm, {
      type,
      page: Number(page) || 1
    });

    return res.json({
      success: true,
      data
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/media/:type/:id
 * @desc    Obtiene metadatos detallados, reparto y trailers de una película o serie
 * @param   type {'movie'|'tv'} - Tipo de medio
 * @param   id {string|number} - ID de TMDB
 */
router.get('/media/:type/:id', async (req, res, next) => {
  try {
    const { type, id } = req.params;

    if (!['movie', 'tv'].includes(type)) {
      return res.status(400).json({
        success: false,
        error: 'El parámetro "type" debe ser "movie" o "tv".'
      });
    }

    let details;
    if (type === 'movie') {
      details = await tmdbService.getMovieDetails(id);
    } else {
      details = await tmdbService.getTvShowDetails(id);
    }

    return res.json({
      success: true,
      data: details
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/tv/:id/season/:season_number
 * @desc    Obtiene la lista de episodios de una temporada de una serie
 */
router.get('/tv/:id/season/:season_number', async (req, res, next) => {
  try {
    const { id, season_number } = req.params;
    const episodes = await tmdbService.getTvSeasonEpisodes(id, parseInt(season_number, 10) || 1);
    return res.json({
      success: true,
      episodes
    });
  } catch (error) {
    next(error);
  }
});


/**
 * ====================================================================
 * RUTAS DE DESBRIDADO Y GESTIÓN DE TORRENTS (REAL-DEBRID)
 * ====================================================================
 */

/**
 * @route   POST /api/streaming/magnet/add
 * @desc    Envía un magnet link a Real-Debrid para inicializar el torrent
 * @body    magnet {string} - Magnet URI o infohash
 */
router.post('/magnet/add', async (req, res, next) => {
  try {
    const { magnet } = req.body;

    if (!magnet) {
      return res.status(400).json({
        success: false,
        error: 'El campo "magnet" es obligatorio en el cuerpo de la petición.'
      });
    }

    const result = await realDebridService.addMagnet(magnet);

    return res.status(201).json({
      success: true,
      message: 'Magnet agregado exitosamente.',
      data: result
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   POST /api/streaming/torrent/select
 * @desc    Selecciona los archivos a procesar dentro del torrent
 * @body    torrentId {string} - ID del torrent en Real-Debrid
 * @body    files {string} - IDs de archivos separados por comas o 'all' (default 'all')
 */
router.post('/torrent/select', async (req, res, next) => {
  try {
    const { torrentId, files = 'all' } = req.body;

    if (!torrentId) {
      return res.status(400).json({
        success: false,
        error: 'El campo "torrentId" es obligatorio.'
      });
    }

    await realDebridService.selectFiles(torrentId, files);

    return res.json({
      success: true,
      message: `Archivos ('${files}') seleccionados exitosamente para el torrent ${torrentId}.`
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/torrent/:id
 * @desc    Consulta el estado, progreso y enlaces generados de un torrent
 * @param   id {string} - ID del torrent en Real-Debrid
 */
router.get('/torrent/:id', async (req, res, next) => {
  try {
    const { id } = req.params;

    if (!id) {
      return res.status(400).json({
        success: false,
        error: 'El parámetro de ruta "id" es obligatorio.'
      });
    }

    const info = await realDebridService.getTorrentInfo(id);

    return res.json({
      success: true,
      data: info
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   POST /api/streaming/unrestrict
 * @desc    Desbrida un enlace para obtener la URL directa de streaming
 * @body    link {string} - Enlace generado por Real-Debrid o host soportado
 * @body    password {string} - Contraseña opcional
 */
router.post('/unrestrict', async (req, res, next) => {
  try {
    const { link, password } = req.body;

    if (!link) {
      return res.status(400).json({
        success: false,
        error: 'El campo "link" es obligatorio en el cuerpo de la petición.'
      });
    }

    const unrestricted = await realDebridService.unrestrictLink(link, password);

    return res.json({
      success: true,
      data: unrestricted
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   POST /api/streaming/resolve-stream
 * @desc    Endpoint todo-en-uno de alta conveniencia:
 *          1. Añade el magnet
 *          2. Selecciona archivos
 *          3. Obtiene links
 *          4. Desbrida y retorna los enlaces directos de streaming
 * @body    magnet {string} - Enlace magnet
 * @body    files {string} - IDs o 'all' (opcional, default 'all')
 */
router.post('/resolve-stream', async (req, res, next) => {
  try {
    const { magnet, files = 'all', unrestrictAll = true } = req.body;

    if (!magnet) {
      return res.status(400).json({
        success: false,
        error: 'El campo "magnet" es obligatorio.'
      });
    }

    const result = await realDebridService.resolveMagnetToStream(magnet, {
      files,
      unrestrictAll
    });

    return res.json(result);
  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/streaming/stream
 * @route   GET /api/stream
 * @desc    Streaming orquestado 100% en la infraestructura y CDN de TorBox (Zero-Buffer / Zero-Memory en Render).
 *          Render NO descarga, almacena ni hace proxy de ningún byte multimedia.
 *          El backend orquesta la llamada a la API de TorBox y responde con una Redirección HTTP 302
 *          directa al CDN (o JSON con la URL directa para reproductores avanzados).
 * @query   magnet {string} - Enlace magnet o hash del torrent (Obligatorio)
 * @query   hash {string} - Alias alternativo para el hash del torrent
 * @query   redirect {boolean} - Si responde con Redirección 302 (default true) o JSON
 * @query   format {string} - 'json' para forzar respuesta en formato JSON
 * @query   season {number} - Temporada opcional si es serie
 * @query   episode {number} - Episodio opcional si es serie
 */
router.get(['/stream', '/download'], async (req, res, next) => {
  try {
    if (typeof req.setTimeout === 'function') {
      req.setTimeout(30000); // Evitar cortes de socket prematuros durante resolución
    }
    const { magnet, hash, redirect = 'true', format, season, episode, fileId, file_id } = req.query;
    const targetMagnet = magnet || hash;

    if (!targetMagnet || typeof targetMagnet !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'El parámetro "magnet" o "hash" es obligatorio.'
      });
    }

    if (!torboxService.isAvailable()) {
      return res.status(503).json({
        success: false,
        error: 'El servicio de TorBox no está configurado en el servidor (TORBOX_API_KEY no encontrada).'
      });
    }

    const streamData = await torboxService.resolveMagnetToStream(targetMagnet, {
      season: season ? parseInt(season, 10) : undefined,
      episode: episode ? parseInt(episode, 10) : undefined,
      fileId: fileId || file_id
    });

    if (!streamData.ready || !streamData.streamUrl) {
      return res.status(202).json({
        success: false,
        ready: false,
        status: streamData.status || 'downloading',
        progress: streamData.progress || 0,
        seeds: streamData.seeds || 0,
        message: streamData.message || 'El torrent se está descargando en los servidores de TorBox. Intenta nuevamente en breve.'
      });
    }

    // Cabeceras universales de streaming para HTML5 <video> y Video.js
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Range, Accept, Origin, Content-Type');
    res.setHeader('Cache-Control', 'private, no-cache, no-transform');

    const shouldRedirect = redirect !== 'false' && format !== 'json' && !req.accepts('json');

    if (shouldRedirect) {
      // Redirección HTTP 302 directa hacia el CDN de TorBox
      return res.redirect(302, streamData.streamUrl);
    }

    // Respuesta JSON estructurada si el cliente o reproductor lo solicita explícitamente
    return res.json({
      success: true,
      ready: true,
      streamUrl: streamData.streamUrl,
      filename: streamData.filename,
      filesize: streamData.filesize,
      torrentId: streamData.torrentId,
      fileId: streamData.fileId,
      mimeType: streamData.mimeType || 'video/mp4'
    });
  } catch (error) {
    console.error('[TorBox Stream Router] Error resolviendo stream:', error.message);
    return res.status(error.response?.status || 502).json({
      success: false,
      error: 'Error al orquestar streaming con TorBox: ' + error.message
    });
  }
});

/**
 * @route   POST /api/streaming/auto-resolve
 * @desc    Resolución 100% automática sin pantallas técnicas:
 *          Busca el torrent óptimo, filtra Anti-CAM, prioriza español y desbrida en Real-Debrid.
 * @body    title {string} - Título de la película o serie
 * @body    originalTitle {string} - Título original
 * @body    year {number|string} - Año de estreno
 * @body    mediaType {'movie'|'tv'} - Tipo de medio
 */
router.post('/auto-resolve', async (req, res, next) => {
  try {
    if (typeof req.setTimeout === 'function') {
      req.setTimeout(35000); // 35 segundos para permitir resolución profunda sin cortes de socket
    }
    const {
      title,
      originalTitle,
      year,
      mediaType = 'movie',
      id,
      season = 1,
      episode = 1,
      bypassCache = false,
      excludeUrls = [],
      imdbId,
      preferH264 = false,
      excludeHevc = false,
      fileId,
      file_id
    } = req.body;

    if (!title) {
      return res.status(400).json({
        success: false,
        error: 'El campo "title" es obligatorio para la resolución automática.'
      });
    }

    const streamData = await streamResolverService.resolveBestStream({
      title,
      originalTitle,
      year,
      mediaType,
      id,
      imdbId,
      season: parseInt(season, 10) || 1,
      episode: parseInt(episode, 10) || 1,
      bypassCache: Boolean(bypassCache),
      excludeUrls: Array.isArray(excludeUrls) ? excludeUrls : [],
      preferH264: Boolean(preferH264 || excludeHevc),
      excludeHevc: Boolean(excludeHevc),
      fileId: fileId || file_id
    });

    return res.json({
      success: true,
      app: 'VJ STREAM',
      ...streamData,
      data: streamData
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   POST /api/streaming/clear-cache
 * @desc    Limpia la memoria caché del resolver para forzar nueva búsqueda de fuentes óptimas
 */
router.post('/clear-cache', (req, res) => {
  const { pattern } = req.body || {};
  const cleared = streamResolverService.clearCache(pattern);
  return res.json({
    success: true,
    message: pattern ? `Caché limpiada para patrón: "${pattern}"` : 'Caché completa de streams limpiada con éxito.',
    cleared
  });
});

/**
 * @route   GET /api/streaming/upcoming
 * @route   GET /api/streaming/trailers
 * @desc    Obtiene los próximos estrenos de cine y títulos disponibles solo en tráiler (inglés)
 *          que se integrarán automáticamente al catálogo una vez doblados al español.
 * @query   page {number} - Página actual (default 1)
 */
router.get('/upcoming', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const upcoming = await tmdbService.getUpcomingMovies(page);
    return res.json({
      success: true,
      app: 'VJ STREAM',
      page,
      data: upcoming,
      movies: upcoming
    });
  } catch (error) {
    next(error);
  }
});
router.get('/trailers', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const upcoming = await tmdbService.getUpcomingMovies(page);
    return res.json({
      success: true,
      app: 'VJ STREAM',
      page,
      data: upcoming,
      movies: upcoming
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route   POST /api/streaming/check-spanish-availability
 * @desc    Comprueba si una película que estaba solo en inglés/tráiler ya cuenta con audio en español
 *          para integrarla automáticamente al catálogo completo.
 * @body    id {string|number} - ID de TMDB
 * @body    title {string} - Título
 * @body    originalTitle {string} - Título original
 * @body    year {string|number} - Año
 */
router.post('/check-spanish-availability', async (req, res, next) => {
  try {
    const { title, originalTitle, year, mediaType = 'movie', id } = req.body;
    if (!title && !id) {
      return res.status(400).json({
        success: false,
        error: 'Se requiere "title" o "id" para verificar disponibilidad.'
      });
    }

    const availability = await streamResolverService.checkSpanishAvailability({
      title,
      originalTitle,
      year,
      mediaType,
      id
    });

    return res.json({
      success: true,
      app: 'VJ STREAM',
      ...availability
    });
  } catch (error) {
    next(error);
  }
});

/**
 * ====================================================================
 * SISTEMA DE ACTUALIZACIÓN AUTOMÁTICA IN-APP (OTA)
 * ====================================================================
 */

/**
 * @route   GET /api/streaming/channels
 * @route   GET /api/streaming/live-channels
 * @route   GET /api/channels
 * @desc    Obtiene la lista de canales de TV en vivo organizados por categorías con soporte Failover
 * @query   category {string} - Filtro opcional por categoría
 */
const getChannelsHandler = (req, res) => {
  try {
    const { category } = req.query;
    const channels = channelService.getChannels(category);
    const categories = channelService.getCategories();

    return res.json({
      success: true,
      app: 'VJ STREAM',
      total: channels.length,
      categories: ['Todos', ...categories],
      channels
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      error: 'Error al obtener canales en vivo: ' + err.message
    });
  }
};

router.get('/channels', getChannelsHandler);
router.get('/live-channels', getChannelsHandler);
router.get('/channels/epg', (req, res) => {
  try {
    const { category } = req.query;
    const channels = channelService.getChannels(category, true);
    return res.json({
      success: true,
      app: 'TOM TV EPG',
      total: channels.length,
      channels
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * ====================================================================
 * SINCRONIZACIÓN EN LA NUBE (CONTINUAR VIENDO Y FAVORITOS)
 * ====================================================================
 */

/**
 * @route   GET /api/streaming/user-data/sync
 * @desc    Obtiene el historial de reproducción y favoritos sincronizados en la nube
 * @query   code {string} - Código de cliente o identificador
 */
router.get('/user-data/sync', (req, res) => {
  try {
    const code = req.query.code || req.headers['x-client-code'];
    if (!code) {
      return res.status(400).json({ success: false, error: 'Código de cliente requerido' });
    }
    const data = accountService.getUserSyncData(code);
    return res.json({
      success: true,
      app: 'TOM TV',
      ...data
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/streaming/user-data/progress
 * @desc    Guarda el progreso de reproducción de un elemento en la nube
 * @body    code {string}
 * @body    item {object}
 */
router.post('/user-data/progress', (req, res) => {
  try {
    const code = req.body.code || req.headers['x-client-code'];
    const { item } = req.body;
    if (!code || !item) {
      return res.status(400).json({ success: false, error: 'Código de cliente e item son obligatorios' });
    }
    const history = accountService.savePlaybackProgress(code, item);
    return res.json({
      success: true,
      history
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/streaming/user-data/delete-progress
 * @desc    Elimina un elemento específico del historial de reproducción en la nube
 * @body    code {string}
 * @body    id {string|number}
 * @body    title {string}
 */
router.post('/user-data/delete-progress', (req, res) => {
  try {
    const code = req.body.code || req.headers['x-client-code'];
    const { id, title } = req.body;
    if (!code || (!id && !title)) {
      return res.status(400).json({ success: false, error: 'Código de cliente y id o título son requeridos' });
    }
    const history = accountService.removePlaybackProgress(code, id, title);
    return res.json({
      success: true,
      history
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/streaming/user-data/clear-progress
 * @desc    Elimina todo el historial de reproducción en la nube
 * @body    code {string}
 */
router.post('/user-data/clear-progress', (req, res) => {
  try {
    const code = req.body.code || req.headers['x-client-code'];
    if (!code) {
      return res.status(400).json({ success: false, error: 'Código de cliente es requerido' });
    }
    accountService.clearPlaybackHistory(code);
    return res.json({
      success: true,
      history: []
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/streaming/user-data/favorite
 * @desc    Agrega o quita un favorito en la nube
 * @body    code {string}
 * @body    item {object}
 */
router.post('/user-data/favorite', (req, res) => {
  try {
    const code = req.body.code || req.headers['x-client-code'];
    const { item } = req.body;
    if (!code || !item) {
      return res.status(400).json({ success: false, error: 'Código de cliente e item son obligatorios' });
    }
    const favorites = accountService.toggleFavorite(code, item);
    return res.json({
      success: true,
      favorites
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   GET /api/streaming/playlist.m3u
 * @route   GET /api/streaming/m3u
 * @desc    Genera la lista M3U oficial de TOM TV para Smart TVs (LG webOS con IBO Player, IPTV Smarters, etc.)
 * @query   code | user | username {string} - Código de activación o username del cliente
 */
const getM3uPlaylistHandler = async (req, res) => {
  const { code, user, username, token } = req.query;
  const access = accountService.validateClientAccess(code || user || username || token);

  res.setHeader('Content-Type', 'application/x-mpegurl; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="tomtv.m3u"');

  if (!access.valid) {
    const errorMsg = access.reason || 'Acceso no autorizado';
    return res.send(
      `#EXTM3U name="TOM TV - AVISO"\n` +
      `#EXTINF:-1 tvg-id="aviso" tvg-name="⚠️ ${errorMsg}" group-title="ESTADO CUENTA",⚠️ ${errorMsg}\n` +
      `https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8\n`
    );
  }

  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host');
  const baseUrl = `${proto}://${host}`;

  const channels = channelService.getChannels();
  let m3u = `#EXTM3U name="TOM TV (${access.client.name})"\n`;

  // 1. Canales de televisión en vivo (1,338 canales)
  for (const c of channels) {
    const name = (c.name || 'Canal').replace(/,/g, ' ');
    const logo = c.logoUrl || '';
    const group = c.category || 'General';
    const stream = c.streamUrl || (Array.isArray(c.sources) && c.sources[0]) || '';
    if (stream) {
      m3u += `#EXTINF:-1 tvg-id="${c.id || ''}" tvg-name="${name}" tvg-logo="${logo}" group-title="${group}",${name}\n${stream}\n`;
    }
  }

  // 2. Películas VOD organizadas por categorías de estreno
  try {
    const catalog = await tmdbService.getFullCatalog();
    const categoriesMap = [
      { key: 'nowPlaying', label: 'Películas: Estrenos de Cine' },
      { key: 'trending', label: 'Películas: Tendencias' },
      { key: 'action', label: 'Películas: Acción' },
      { key: 'comedy', label: 'Películas: Comedia' },
      { key: 'horror', label: 'Películas: Terror' },
      { key: 'animation', label: 'Películas: Animación' },
      { key: 'scifi', label: 'Películas: Ciencia Ficción' }
    ];

    const seenMovieIds = new Set();
    const clientCode = encodeURIComponent(access.client.code || access.client.username);

    for (const cat of categoriesMap) {
      const items = catalog[cat.key];
      if (Array.isArray(items)) {
        for (const item of items) {
          if (!item.id || seenMovieIds.has(item.id)) continue;
          seenMovieIds.add(item.id);

          const title = (item.title || 'Película').replace(/,/g, ' ');
          const logo = item.posterLarge || item.posterMedium || '';
          const streamUrl = `${baseUrl}/api/streaming/vod/movie/${item.id}?code=${clientCode}`;

          m3u += `#EXTINF:-1 tvg-id="movie-${item.id}" tvg-name="${title}" tvg-logo="${logo}" group-title="${cat.label}",${title}\n${streamUrl}\n`;
        }
      }
    }
  } catch (err) {
    console.warn('[M3U] Error al cargar películas VOD para M3U:', err.message);
  }

  return res.send(m3u);
};

router.get('/playlist.m3u', getM3uPlaylistHandler);
router.get('/m3u', getM3uPlaylistHandler);
router.get('/get.php', getM3uPlaylistHandler);

/**
 * @route   GET /api/streaming/vod/movie/:id
 * @desc    Resuelve y redirige al stream bajo demanda para IBO Player / Smart TV
 */
router.get('/vod/movie/:id', async (req, res) => {
  const { code, user, username, token } = req.query;
  const access = accountService.validateClientAccess(code || user || username || token);

  if (!access.valid) {
    return res.status(403).send(`Acceso no autorizado: ${access.reason}`);
  }

  try {
    const movieId = req.params.id;
    const details = await tmdbService.getMovieDetails(movieId);
    if (!details || !details.title) {
      return res.status(404).send('Película no encontrada en TMDB');
    }

    const streamData = await streamResolverService.resolveBestStream({
      title: details.title,
      originalTitle: details.originalTitle || details.original_title,
      year: details.releaseYear || (details.releaseDate ? details.releaseDate.split('-')[0] : ''),
      mediaType: 'movie',
      id: movieId
    });

    if (streamData && streamData.streamUrl) {
      return res.redirect(302, streamData.streamUrl);
    }

    return res.status(404).send('No se encontró una transmisión en español disponible.');
  } catch (err) {
    console.error('[VOD Stream Movie] Error:', err.message);
    return res.status(500).send('Error al procesar película: ' + err.message);
  }
});

/**
 * @route   GET /api/streaming/proxy
 * @route   GET /api/streaming/stream-proxy
 * @desc    Streaming relay / proxy de alta disponibilidad con soporte de HTTP Range (RFC 7233).
 *          Canaliza el tráfico a través de la IP fija del servidor eliminando bloqueos multi-IP de Real-Debrid
 *          y permitiendo avance rápido (scrubbing/seek) en ExoPlayer y Smart TV.
 */
router.get(['/proxy', '/stream-proxy'], async (req, res) => {
  const targetUrl = req.query.url;
  if (!targetUrl || typeof targetUrl !== 'string') {
    return res.status(400).send('Parámetro "url" es obligatorio.');
  }

  // Prevenir bucles infinitos
  if (targetUrl.includes('/api/streaming/proxy') || targetUrl.includes('/stream-proxy')) {
    return res.status(400).send('Bucle de proxy detectado.');
  }

  // 1. Si la URL pertenece al CDN de TorBox, redirigir directamente (HTTP 302)
  // ya que TorBox admite streaming multi-IP sin restricciones y no requiere relay por Render.
  if (targetUrl.includes('torbox.app') || targetUrl.includes('torbox')) {
    return res.redirect(302, targetUrl);
  }

  try {
    const upstreamHeaders = {
      'user-agent': req.headers['user-agent'] || 'TOM-TV-Player/3.0'
    };

    if (req.headers.range) {
      upstreamHeaders.range = req.headers.range;
    }

    const upstream = await axios.get(targetUrl, {
      responseType: 'stream',
      headers: upstreamHeaders,
      timeout: 12000,
      validateStatus: status => status >= 200 && status < 400
    });

    res.status(upstream.status);

    const forwardHeaders = [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
      'content-disposition',
      'last-modified',
      'etag'
    ];

    forwardHeaders.forEach(h => {
      if (upstream.headers[h]) {
        res.setHeader(h, upstream.headers[h]);
      }
    });

    // Control estricto de backpressure y desconexión inmediata de socket para liberar RAM
    const cleanUp = () => {
      if (upstream.data && typeof upstream.data.destroy === 'function') {
        upstream.data.destroy();
      }
    };

    req.on('close', cleanUp);
    res.on('close', cleanUp);
    res.on('finish', cleanUp);
    upstream.data.on('error', cleanUp);

    upstream.data.pipe(res);
  } catch (err) {
    console.warn('[Stream Proxy] Error transmitiendo fragmento:', err.message);
    if (!res.headersSent) {
      res.status(err.response?.status || 502).send('Error en streaming relay: ' + err.message);
    }
  }
});

/**
 * Caché del último release publicado en GitHub (el que tiene el APK ya compilado).
 * Se anuncia ESTA versión a las apps, no la de pubspec.yaml: pubspec cambia en cuanto
 * se hace push, pero el APK tarda ~5 min en compilarse. Anunciar pubspec provocaba
 * que la app pidiera actualizar a una versión cuyo archivo aún no existía.
 */
let _publishedReleaseCache = { fetchedAt: 0, data: null };
const CURRENT_OFFICIAL_RELEASE = {
  latestVersion: '4.2.5',
  versionCode: 51,
  downloadUrl: 'https://github.com/Victorego23/vj-stream/releases/download/v4.2.5/TOM-TV-release.apk',
  releaseDate: '2026-10-07'
};

const RELEASE_CACHE_MS = 10 * 60 * 1000;

async function getPublishedRelease() {
  const now = Date.now();
  if (_publishedReleaseCache.data && now - _publishedReleaseCache.fetchedAt < RELEASE_CACHE_MS) {
    return _publishedReleaseCache.data;
  }
  try {
    const res = await axios.get('https://api.github.com/repos/Victorego23/vj-stream/releases/latest', {
      timeout: 5000,
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'tomtv-backend' }
    });
    const rel = res.data || {};
    const asset = (rel.assets || []).find(a => a.name === 'TOM-TV-release.apk' && a.state === 'uploaded');
    const tagMatch = String(rel.tag_name || '').match(/^v?([0-9.]+)$/);
    const buildMatch = String(rel.name || '').match(/Build\s+(\d+)/i);
    if (asset && tagMatch && buildMatch) {
      const data = {
        latestVersion: tagMatch[1],
        versionCode: parseInt(buildMatch[1], 10),
        downloadUrl: asset.browser_download_url,
        releaseDate: (rel.published_at || '').slice(0, 10)
      };
      _publishedReleaseCache = { fetchedAt: now, data };
      return data;
    }
  } catch (err) {
    console.warn('[OTA] No se pudo consultar el último release de GitHub:', err.message);
  }
  // Si GitHub falla, conservar el último dato bueno conocido o el release oficial por defecto
  return _publishedReleaseCache.data || CURRENT_OFFICIAL_RELEASE;
}

/**
 * @route   GET /api/streaming/version
 * @desc    Devuelve los metadatos de la última versión DESCARGABLE y notas de la versión para OTA
 */
router.get('/version', async (req, res) => {
  const published = (await getPublishedRelease()) || CURRENT_OFFICIAL_RELEASE;

  return res.json({
    success: true,
    app: 'TOM TV',
    latestVersion: published.latestVersion,
    versionCode: published.versionCode,
    minSupportedVersion: '1.0.0',
    releaseDate: published.releaseDate,
    releaseNotes: [
      '⚡ Modo Turbo Ultra-Veloz: Arranque instantáneo de películas en 1 segundo con 0% de latencia.',
      '🧹 Limpiador Inteligente 24/7: Conexión TorBox y Debrid optimizada sin bloqueos ni torrents estancados.',
      '🎬 Catálogo Ilimitado (+50,000 Películas) con reproducción directa en Español Latino (🇲🇽) y Castellano.',
      '🛡️ Servidor Blindado contra caídas: Consumo ultra-bajo de recursos y máxima estabilidad.',
      '📡 444 Canales de TV en Vivo 100% Operativos con Auto-Failover 24/7.'
    ],
    downloadUrl: published.downloadUrl,
    forceUpdate: false,
    announcement: accountService.getAnnouncement()
  });
});

/**
 * @route   GET /api/streaming/announcement
 * @desc    Obtiene el aviso o notificación activa para mostrar en TVs y móviles
 */
router.get('/announcement', (req, res) => {
  const announcement = accountService.getAnnouncement();
  return res.json({
    success: true,
    announcement
  });
});

/**
 * @route   GET /api/streaming/download-apk
 * @desc    Descarga directa del APK de TOM TV para actualización OTA
 */
router.get('/download-apk', async (req, res) => {
  if (req.query.source === 'local') {
    const path = require('path');
    const fs = require('fs');
    const tomReleasePath = path.resolve(__dirname, '..', 'TOM-TV-release.apk');
    if (fs.existsSync(tomReleasePath)) {
      const stat = fs.statSync(tomReleasePath);
      res.setHeader('Content-Type', 'application/vnd.android.package-archive');
      res.setHeader('Content-Length', stat.size);
      res.setHeader('Content-Disposition', 'attachment; filename="TOM-TV.apk"');
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      return res.sendFile(tomReleasePath);
    }
  }

  const published = await getPublishedRelease();
  if (published && published.downloadUrl) {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    return res.redirect(published.downloadUrl);
  }

  const githubReleaseUrl = 'https://github.com/Victorego23/vj-stream/releases/latest/download/TOM-TV-release.apk';
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  return res.redirect(githubReleaseUrl);
});

/**
 * @route   GET /api/streaming/payment-info
 * @desc    Obtiene la pasarela y métodos de pago oficiales con enlace directo al WhatsApp del dueño
 */
router.get('/payment-info', (req, res) => {
  const settings = accountService.getSettings();
  const whatsappNumber = settings.whatsappNumber || process.env.WHATSAPP_NUMBER || '+51914598415';
  const cleanWhatsapp = whatsappNumber.replace(/[^0-9]/g, '');
  const plinNumber = settings.plinNumber || process.env.PLIN_NUMBER || '962622904';
  const formattedPlin = '962 622 904';

  return res.json({
    success: true,
    whatsappNumber,
    whatsappClean: cleanWhatsapp,
    ownerName: 'TOM TV Oficial',
    methods: [
      {
        id: 'plin',
        name: 'Plin (Perú)',
        phone: formattedPlin,
        rawPhone: plinNumber,
        currency: 'PEN',
        badge: 'Pago Oficial Perú (Plin)',
        instruction: `Transfiere únicamente por Plin al número ${formattedPlin} y envía la captura a nuestro WhatsApp oficial ${whatsappNumber}.`
      },
      {
        id: 'binance',
        name: 'Binance Pay / USDT',
        currency: 'USDT',
        network: 'TRC20 / BEP20',
        badge: 'Internacional',
        instruction: `Solicita los datos de Binance Pay por nuestro WhatsApp oficial ${whatsappNumber}.`
      }
    ],
    plans: [
      { id: '1m', name: '1 Mes', days: 30, pricePen: '15 PEN', priceUsd: '4 USD', popular: false },
      { id: '3m', name: '3 Meses', days: 90, pricePen: '40 PEN', priceUsd: '11 USD', popular: true },
      { id: '6m', name: '6 Meses', days: 180, pricePen: '75 PEN', priceUsd: '20 USD', popular: false },
      { id: '1y', name: '1 Año Completo VIP', days: 365, pricePen: '140 PEN', priceUsd: '38 USD', popular: false }
    ],
    notes: {
      supportWhatsapp: whatsappNumber,
      paymentPlin: formattedPlin
    },
    whatsappLinkTemplate: `https://wa.me/${cleanWhatsapp}?text=`
  });
});

module.exports = router;

