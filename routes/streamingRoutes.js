const express = require('express');
const router = express.Router();
const realDebridService = require('../services/realDebridService');
const tmdbService = require('../services/tmdbService');
const streamResolverService = require('../services/streamResolverService');
const hmacSecurityMiddleware = require('../middlewares/hmacSecurityMiddleware');

// Blindaje de seguridad: Solo la app oficial VJ STREAM puede acceder a los servicios
router.use(hmacSecurityMiddleware);

/**
 * ====================================================================
 * RUTAS DE CATÁLOGO Y METADATOS (TMDB)
 * ====================================================================
 */

/**
 * @route   GET /api/streaming/catalog
 * @desc    Obtiene el catálogo consolidado de 5 categorías en paralelo en español
 */
router.get('/catalog', async (req, res, next) => {
  try {
    const catalog = await tmdbService.getFullCatalog();
    return res.json({
      success: true,
      app: 'VJ STREAM',
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
    const { title, originalTitle, year, mediaType = 'movie', id, season = 1, episode = 1 } = req.body;

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
      season: parseInt(season, 10) || 1,
      episode: parseInt(episode, 10) || 1
    });

    return res.json({
      success: true,
      app: 'VJ STREAM',
      data: streamData
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
 * @route   GET /api/streaming/version
 * @desc    Devuelve los metadatos de la última versión y notas de la versión para OTA
 */
router.get('/version', (req, res) => {
  return res.json({
    success: true,
    app: 'VJ STREAM',
    latestVersion: '2.3.0',
    versionCode: 6,
    minSupportedVersion: '1.0.0',
    releaseDate: '2026-09-24',
    releaseNotes: [
      '🛡️ Filtro Anti-CAM Estricto: Bloqueo garantizado de grabaciones de cine',
      '⏱️ Continuar Viendo: Barra de progreso y reanudación automática',
      '🍿 Series Completas: Selector de temporadas y lista de episodios',
      '⭐ Mi Lista: Guarda tus películas y series favoritas',
      '🎬 Tráiler Oficial: Botón de vista previa directa en el reproductor',
      '🏷️ Pestañas Rápidas: Filtros instantáneos (Películas, Series, Mi Lista)'
    ],
    downloadUrl: '/api/streaming/download-apk',
    forceUpdate: false
  });
});

/**
 * @route   GET /api/streaming/download-apk
 * @desc    Descarga directa del APK de VJ STREAM para actualización OTA
 */
router.get('/download-apk', (req, res) => {
  const path = require('path');
  const fs = require('fs');

  const releasePath = path.resolve(__dirname, '..', 'VJ-STREAM-release.apk');
  const apkPath = path.resolve(__dirname, '..', 'VJ-STREAM-debug.apk');
  const fallbackPath = path.resolve(__dirname, '..', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');

  const fileToSend = fs.existsSync(releasePath) ? releasePath : (fs.existsSync(apkPath) ? apkPath : fallbackPath);

  if (!fs.existsSync(fileToSend)) {
    return res.status(404).json({
      success: false,
      error: 'El archivo APK de VJ STREAM no está disponible para descarga en este momento.'
    });
  }

  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', 'attachment; filename="VJ-STREAM.apk"');
  return res.download(fileToSend, 'VJ-STREAM.apk');
});

module.exports = router;

