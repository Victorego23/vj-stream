const express = require('express');
const router = express.Router();
const axios = require('axios');
const realDebridService = require('../services/realDebridService');
const tmdbService = require('../services/tmdbService');
const streamResolverService = require('../services/streamResolverService');
const channelService = require('../services/channelService');
const accountService = require('../services/accountService');
const catalogSyncService = require('../services/catalogSyncService');
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
    const { title, originalTitle, year, mediaType = 'movie', id, season = 1, episode = 1, bypassCache = false, excludeUrls = [] } = req.body;

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
      episode: parseInt(episode, 10) || 1,
      bypassCache: Boolean(bypassCache),
      excludeUrls: Array.isArray(excludeUrls) ? excludeUrls : []
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

    upstream.data.pipe(res);

    req.on('close', () => {
      if (upstream.data && typeof upstream.data.destroy === 'function') {
        upstream.data.destroy();
      }
    });
  } catch (err) {
    console.warn('[Stream Proxy] Error transmitiendo fragmento:', err.message);
    if (!res.headersSent) {
      res.status(err.response?.status || 502).send('Error en streaming relay: ' + err.message);
    }
  }
});

/**
 * @route   GET /api/streaming/version
 * @desc    Devuelve los metadatos de la última versión y notas de la versión para OTA
 */
router.get('/version', (req, res) => {
  const path = require('path');
  const fs = require('fs');

  let latestVersion = '3.6.0';
  let versionCode = 35;

  try {
    const pubspecPath = path.resolve(__dirname, '..', 'pubspec.yaml');
    if (fs.existsSync(pubspecPath)) {
      const content = fs.readFileSync(pubspecPath, 'utf8');
      const match = content.match(/version:\s*([0-9.]+)\+(\d+)/);
      if (match) {
        latestVersion = match[1];
        versionCode = parseInt(match[2], 10);
      }
    }
  } catch (_) {}

  return res.json({
    success: true,
    app: 'TOM TV',
    latestVersion,
    versionCode,
    minSupportedVersion: '1.0.0',
    releaseDate: '2026-10-05',
    releaseNotes: [
      '🔥 Nuevo Diseño Maestro Xuper TV / Magis TV: Launcher principal con reloj digital en vivo, fecha en tiempo real y Bloques Gigantes neón (TV En Vivo, Películas, Series, Deportes).',
      '📺 Guía de TV en Vivo Profesional en 3 Columnas: Panel de Categorías verticales, Lista de Canales con numeración (#01, #02...) y Mini-Reproductor HLS en tiempo real con ficha EPG completa.',
      '⚡ Zapping Lateral OSD con Control Remoto: Abre el menú de canales deslizando a la izquierda o con flechas sin cortar la reproducción, navega con Arriba/Abajo y sintoniza con Enter/OK.',
      '✨ Integración Total de Canales Peruanos: Todos los canales nacionales integrados ordenadamente en la parrilla unificada de TV.',
      '🚀 Rendimiento Ultrarrápido: Debounce inteligente de 400ms para hardware de Smart TV, decodificación optimizada y compatibilidad 100% táctil y control remoto.'
    ],
    downloadUrl: `https://github.com/Victorego23/vj-stream/releases/download/v${latestVersion}/TOM-TV-release.apk`,
    fallbackDownloadUrl: '/api/streaming/download-apk',
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
router.get('/download-apk', (req, res) => {
  const path = require('path');
  const fs = require('fs');

  const tomReleasePath = path.resolve(__dirname, '..', 'TOM-TV-release.apk');
  const releasePath = path.resolve(__dirname, '..', 'VJ-STREAM-release.apk');
  const apkPath = path.resolve(__dirname, '..', 'VJ-STREAM-debug.apk');
  const fallbackPath = path.resolve(__dirname, '..', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');

  const fileToSend = fs.existsSync(tomReleasePath)
    ? tomReleasePath
    : (fs.existsSync(releasePath) ? releasePath : (fs.existsSync(apkPath) ? apkPath : fallbackPath));

  if (fs.existsSync(fileToSend)) {
    const stat = fs.statSync(fileToSend);
    res.setHeader('Content-Type', 'application/vnd.android.package-archive');
    res.setHeader('Content-Length', stat.size);
    res.setHeader('Content-Disposition', 'attachment; filename="TOM-TV.apk"');
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    return res.sendFile(fileToSend);
  }

  const githubReleaseUrl = 'https://github.com/Victorego23/vj-stream/releases/latest/download/TOM-TV-release.apk';
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

