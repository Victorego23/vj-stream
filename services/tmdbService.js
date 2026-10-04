const axios = require('axios');

/**
 * Títulos especiales configurados en modo tráiler exclusivo
 * hasta que cuenten con su estreno y disponibilidad oficial en español.
 */
const FORCED_TRAILER_TITLES = [
  {
    id: 1204680,
    title: 'Coyote vs. Acme',
    originalTitle: 'Coyote vs. Acme',
    aliases: ['coyote vs acme', 'coyote vs. acme', 'coyote contra acme', 'coyote acme'],
    trailerKey: 'WQRoa6l4bwI',
    trailer: 'https://www.youtube.com/watch?v=WQRoa6l4bwI',
    statusBadge: 'Solo Tráiler - Próximamente en Español'
  },
  {
    id: 1368337,
    title: 'La Odisea',
    originalTitle: 'The Odyssey',
    aliases: ['la odisea', 'the odyssey', 'odisea'],
    trailerKey: '8un_UztYsw0',
    trailer: 'https://www.youtube.com/watch?v=8un_UztYsw0',
    statusBadge: 'Solo Tráiler - Próximamente en Español'
  },
  {
    id: 969681,
    title: 'Spider-Man: Brand New Day',
    originalTitle: 'Spider-Man: Brand New Day',
    aliases: [
      'spider-man: brand new day',
      'spider-man brand new day',
      'spider man brand new day',
      'spider man un nuevo dia',
      'spiderman brand new day',
      'brand new day',
      'spider-man 4'
    ],
    trailerKey: 'pqLSLoDkZWE',
    trailer: 'https://www.youtube.com/watch?v=pqLSLoDkZWE',
    statusBadge: 'Solo Tráiler - Próximamente en Español'
  }
];

/**
 * Servicio para interactuar con la API REST v3 de TMDB (The Movie Database).
 * Documentación oficial: https://developer.themoviedb.org/reference/intro/getting-started
 */
class TmdbService {
  constructor() {
    this.baseURL = 'https://api.themoviedb.org/3';
    this.imageBaseUrl = 'https://image.tmdb.org/t/p';
  }

  /**
   * Determina si un elemento corresponde a una de las películas fijadas en modo tráiler.
   * @param {Object} item
   * @returns {Object|null}
   */
  getForcedTrailerConfig(item) {
    if (!item) return null;
    const itemId = Number(item.id);
    const title = (item.title || item.name || '').toLowerCase().trim();
    const origTitle = (item.originalTitle || item.original_title || '').toLowerCase().trim();

    for (const conf of FORCED_TRAILER_TITLES) {
      if (itemId && itemId === conf.id) return conf;
      for (const alias of conf.aliases) {
        if (title.includes(alias) || origTitle.includes(alias)) {
          return conf;
        }
      }
    }
    return null;
  }

  /**
   * Obtiene una instancia configurada de Axios con las credenciales de TMDB.
   * Soporta tanto API Key v3 como Access Token v4 (Bearer).
   * @private
   */
  getAxiosClient() {
    const apiKey = process.env.TMDB_API_KEY;

    if (!apiKey) {
      throw new Error('TMDB_API_KEY no está configurada en las variables de entorno.');
    }

    const isBearerToken = apiKey.length > 50; // Los tokens v4 son JWT largos

    const config = {
      baseURL: this.baseURL,
      headers: {
        'Content-Type': 'application/json'
      },
      timeout: 10000
    };

    if (isBearerToken) {
      config.headers.Authorization = `Bearer ${apiKey}`;
    } else {
      config.params = {
        api_key: apiKey
      };
    }

    return axios.create(config);
  }

  /**
   * Genera las URLs absolutas para póster y backdrop a partir de las rutas relativas de TMDB.
   * @param {string|null} path - Ruta relativa de la imagen proporcionada por TMDB.
   * @param {string} [size='w500'] - Tamaño deseado (ej. 'w500', 'original', 'w1280').
   * @returns {string|null} URL completa o null si no hay imagen.
   */
  buildImageUrl(path, size = 'w500') {
    if (!path) return null;
    return `${this.imageBaseUrl}/${size}${path}`;
  }

  /**
   * Formatea un elemento devuelto por TMDB para entregar un contrato de datos limpio y amigable.
   * @private
   */
  formatMediaItem(item) {
    const isMovie = item.media_type === 'movie' || Boolean(item.title);
    const isTv = item.media_type === 'tv' || Boolean(item.name);

    return {
      id: item.id,
      mediaType: item.media_type || (isMovie ? 'movie' : isTv ? 'tv' : 'unknown'),
      title: item.title || item.name || item.original_title || item.original_name,
      originalTitle: item.original_title || item.original_name,
      originalLanguage: item.original_language || null,
      synopsis: item.overview || 'Sin descripción disponible.',
      releaseDate: item.release_date || item.first_air_date || null,
      rating: item.vote_average || 0,
      voteCount: item.vote_count || 0,
      popularity: item.popularity || 0,
      posters: {
        thumbnail: this.buildImageUrl(item.poster_path, 'w342'),
        medium: this.buildImageUrl(item.poster_path, 'w500'),
        original: this.buildImageUrl(item.poster_path, 'original')
      },
      backdrops: {
        medium: this.buildImageUrl(item.backdrop_path, 'w780'),
        large: this.buildImageUrl(item.backdrop_path, 'w1280'),
        original: this.buildImageUrl(item.backdrop_path, 'original')
      }
    };
  }

  /**
   * Busca películas, series o ambos (multi).
   * @param {string} query - Término de búsqueda.
   * @param {Object} [options]
   * @param {'movie'|'tv'|'multi'} [options.type='multi'] - Tipo de búsqueda.
   * @param {number} [options.page=1] - Página de resultados.
   * @param {string} [options.language] - Código de idioma (ej. 'es-ES').
   * @returns {Promise<{page: number, totalPages: number, totalResults: number, results: Array}>}
   */
  async searchMedia(query, options = {}) {
    try {
      if (!query || query.trim() === '') {
        throw new Error('El parámetro de búsqueda "query" es obligatorio.');
      }

      const {
        type = 'multi',
        page = 1,
        language = 'es-ES'
      } = options;

      const client = this.getAxiosClient();
      let endpoint = '/search/multi';

      if (type === 'movie') endpoint = '/search/movie';
      if (type === 'tv') endpoint = '/search/tv';

      const response = await client.get(endpoint, {
        params: {
          query: query.trim(),
          page,
          language: 'es-ES', // Forzado estricto en español para VJ STREAM
          include_adult: false
        }
      });

      const { data } = response;

      return {
        page: data.page,
        totalPages: data.total_pages,
        totalResults: data.total_results,
        results: (data.results || []).map(item => {
          const formatted = this.formatMediaItem(item);
          const forcedConf = this.getForcedTrailerConfig(item) || this.getForcedTrailerConfig(formatted);
          if (forcedConf) {
            return {
              ...formatted,
              isTrailerOnly: true,
              hasSpanishAudio: false,
              trailer: forcedConf.trailer,
              trailerKey: forcedConf.trailerKey,
              statusBadge: forcedConf.statusBadge
            };
          }
          return formatted;
        })
      };
    } catch (error) {
      this.handleError('searchMedia', error);
    }
  }

  /**
   * Obtiene los detalles completos de una película por su ID forzando español (es-ES).
   * @param {string|number} movieId - ID de la película en TMDB.
   * @param {string} [language='es-ES'] - Código de idioma (estrictamente es-ES).
   * @returns {Promise<Object>}
   */
  /**
   * Extrae el mejor trailer disponible dando prioridad a trailers oficiales en español.
   * @private
   */
  _extractTrailer(videos) {
    const results = videos?.results || [];
    if (!results || results.length === 0) return { trailer: null, trailerKey: null };

    // 1. Priorizar trailers explícitamente en español
    const spanishTrailer = results.find(v => 
      v.site === 'YouTube' && 
      v.type === 'Trailer' && 
      /español|castellano|latino|tráiler oficial|trailer oficial/i.test(v.name || '')
    );
    if (spanishTrailer?.key) {
      return {
        trailer: `https://www.youtube.com/watch?v=${spanishTrailer.key}`,
        trailerKey: spanishTrailer.key
      };
    }

    // 2. Cualquier trailer oficial de YouTube
    const trailer = results.find(v => v.site === 'YouTube' && v.type === 'Trailer');
    if (trailer?.key) {
      return {
        trailer: `https://www.youtube.com/watch?v=${trailer.key}`,
        trailerKey: trailer.key
      };
    }

    // 3. Teaser o Clip de YouTube
    const teaser = results.find(v => v.site === 'YouTube' && (v.type === 'Teaser' || v.type === 'Clip'));
    if (teaser?.key) {
      return {
        trailer: `https://www.youtube.com/watch?v=${teaser.key}`,
        trailerKey: teaser.key
      };
    }

    return { trailer: null, trailerKey: null };
  }

  /**
   * Obtiene los detalles completos de una película por su ID forzando español (es-ES).
   * @param {string|number} movieId - ID de la película en TMDB.
   * @param {string} [language='es-ES'] - Código de idioma (estrictamente es-ES).
   * @returns {Promise<Object>}
   */
  async getMovieDetails(movieId, language = 'es-ES') {
    try {
      if (!movieId) throw new Error('El parámetro "movieId" es obligatorio.');

      const client = this.getAxiosClient();
      const lang = 'es-ES'; // Estrictamente español para VJ STREAM

      const response = await client.get(`/movie/${movieId}`, {
        params: {
          language: lang,
          include_image_language: 'es,null',
          include_video_language: 'es,es-ES,es-MX,en,null',
          append_to_response: 'credits,videos,recommendations'
        }
      });

      const data = response.data;
      const formatted = this.formatMediaItem({ ...data, media_type: 'movie' });
      const { trailer, trailerKey } = this._extractTrailer(data.videos);

      const forcedConf = this.getForcedTrailerConfig(data) || this.getForcedTrailerConfig(formatted) || this.getForcedTrailerConfig({ id: movieId });

      return {
        ...formatted,
        genres: data.genres || [],
        runtime: data.runtime || null, // en minutos
        tagline: data.tagline || '',
        status: data.status || '',
        cast: (data.credits?.cast || []).slice(0, 10).map(actor => ({
          name: actor.name,
          character: actor.character,
          profileImage: this.buildImageUrl(actor.profile_path, 'w185')
        })),
        trailer: forcedConf?.trailer || trailer,
        trailerKey: forcedConf?.trailerKey || trailerKey,
        isTrailerOnly: Boolean(forcedConf),
        hasSpanishAudio: forcedConf ? false : true,
        statusBadge: forcedConf ? forcedConf.statusBadge : null
      };
    } catch (error) {
      this.handleError(`getMovieDetails (id: ${movieId})`, error);
    }
  }

  /**
   * Obtiene los detalles completos de una serie por su ID.
   * @param {string|number} tvId - ID de la serie en TMDB.
   * @param {string} [language] - Código de idioma.
   * @returns {Promise<Object>}
   */
  async getTvShowDetails(tvId, language = 'es-ES') {
    try {
      if (!tvId) throw new Error('El parámetro "tvId" es obligatorio.');

      const client = this.getAxiosClient();
      const lang = 'es-ES'; // Estrictamente español para VJ STREAM

      const response = await client.get(`/tv/${tvId}`, {
        params: {
          language: lang,
          include_image_language: 'es,null',
          include_video_language: 'es,es-ES,es-MX,en,null',
          append_to_response: 'credits,videos,recommendations'
        }
      });

      const data = response.data;
      const formatted = this.formatMediaItem({ ...data, media_type: 'tv' });
      const { trailer, trailerKey } = this._extractTrailer(data.videos);

      return {
        ...formatted,
        genres: data.genres || [],
        numberOfSeasons: data.number_of_seasons,
        numberOfEpisodes: data.number_of_episodes,
        status: data.status || '',
        seasons: (data.seasons || []).map(s => ({
          id: s.id,
          name: s.name,
          seasonNumber: s.season_number,
          episodeCount: s.episode_count,
          poster: this.buildImageUrl(s.poster_path, 'w342')
        })),
        cast: (data.credits?.cast || []).slice(0, 10).map(actor => ({
          name: actor.name,
          character: actor.character,
          profileImage: this.buildImageUrl(actor.profile_path, 'w185')
        })),
        trailer,
        trailerKey
      };
    } catch (error) {
      this.handleError(`getTvShowDetails (id: ${tvId})`, error);
    }
  }

  /**
   * Obtiene los episodios detallados de una temporada específica de una serie en español.
   * @param {string|number} tvId 
   * @param {number} seasonNumber 
   */
  async getTvSeasonEpisodes(tvId, seasonNumber = 1) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get(`/tv/${tvId}/season/${seasonNumber}`, {
        params: { language: 'es-ES' }
      });
      const data = response.data;
      return (data.episodes || []).map(ep => ({
        id: ep.id,
        episodeNumber: ep.episode_number,
        seasonNumber: ep.season_number,
        name: ep.name || `Episodio ${ep.episode_number}`,
        overview: ep.overview || 'Sin descripción disponible.',
        runtime: ep.runtime || 45,
        stillUrl: this.buildImageUrl(ep.still_path, 'w500'),
        voteAverage: ep.vote_average || 0
      }));
    } catch (error) {
      console.warn(`[TmdbService] Error en getTvSeasonEpisodes (${tvId} S${seasonNumber}):`, error.message);
      return [];
    }
  }

  /**
   * Obtiene las tendencias de la semana en español.
   */
  async getTrendingWeekly() {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/trending/all/week', {
        params: { language: 'es-ES' }
      });
      return (response.data.results || []).map(item => this.formatMediaItem(item));
    } catch (error) {
      console.warn('[TmdbService] Error en getTrendingWeekly:', error.message);
      return [];
    }
  }

  /**
   * Obtiene los estrenos actuales de cine en español.
   */
  async getNowPlayingMovies() {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/movie/now_playing', {
        params: { language: 'es-ES', page: 1 }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'movie' }));
    } catch (error) {
      console.warn('[TmdbService] Error en getNowPlayingMovies:', error.message);
      return [];
    }
  }

  /**
   * Obtiene próximos estrenos de cine y películas aún no disponibles en digital / español.
   * Se marcan como modo tráiler (isTrailerOnly: true) para reproducir su avance oficial en video.
   * @param {number} [page=1]
   */
  async getUpcomingMovies(page = 1) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/movie/upcoming', {
        params: {
          language: 'es-ES',
          page: page || 1
        }
      });

      const rawItems = response.data?.results || [];
      // Resolver concurrentemente trailers para las películas principales
      const items = await Promise.all(
        rawItems.slice(0, 20).map(async (item) => {
          const formatted = this.formatMediaItem({ ...item, media_type: 'movie' });
          const forcedConf = this.getForcedTrailerConfig(item) || this.getForcedTrailerConfig(formatted);

          let trailer = forcedConf?.trailer || null;
          let trailerKey = forcedConf?.trailerKey || null;

          if (!trailerKey) {
            try {
              const vidRes = await client.get(`/movie/${item.id}/videos`, {
                params: {
                  language: 'es-ES',
                  include_video_language: 'es,es-ES,es-MX,en,null'
                },
                timeout: 4000
              });
              const extracted = this._extractTrailer(vidRes.data);
              trailer = extracted.trailer;
              trailerKey = extracted.trailerKey;
            } catch (_) {}
          }

          return {
            ...formatted,
            isTrailerOnly: true,
            hasSpanishAudio: false,
            trailer,
            trailerKey,
            statusBadge: forcedConf?.statusBadge || 'Próximamente en Español'
          };
        })
      );

      // Si es la página 1, asegurar que las 3 películas fijadas por el usuario
      // (Coyote vs. Acme, La Odisea, Spider-Man: Brand New Day) encabecen la lista
      if (Number(page) === 1) {
        const pinnedItems = [];
        const otherItems = [];

        for (const it of items) {
          if (this.getForcedTrailerConfig(it)) {
            pinnedItems.push(it);
          } else {
            otherItems.push(it);
          }
        }

        // Si alguna de las 3 fijadas no vino en el listado nativo de /upcoming, la cargamos directamente
        for (const conf of FORCED_TRAILER_TITLES) {
          const exists = pinnedItems.some(it => it.id === conf.id || this.getForcedTrailerConfig(it)?.id === conf.id);
          if (!exists) {
            try {
              const details = await this.getMovieDetails(conf.id);
              if (details) {
                pinnedItems.push({
                  ...details,
                  isTrailerOnly: true,
                  hasSpanishAudio: false,
                  trailer: conf.trailer,
                  trailerKey: conf.trailerKey,
                  statusBadge: conf.statusBadge
                });
              }
            } catch (err) {
              console.warn(`[TmdbService] Error cargando película fijada ${conf.title}:`, err.message);
            }
          }
        }

        // Ordenar pinnedItems para garantizar el orden de FORCED_TRAILER_TITLES
        pinnedItems.sort((a, b) => {
          const idxA = FORCED_TRAILER_TITLES.findIndex(c => c.id === a.id || this.getForcedTrailerConfig(a)?.id === c.id);
          const idxB = FORCED_TRAILER_TITLES.findIndex(c => c.id === b.id || this.getForcedTrailerConfig(b)?.id === c.id);
          return (idxA >= 0 ? idxA : 99) - (idxB >= 0 ? idxB : 99);
        });

        return [...pinnedItems, ...otherItems];
      }

      return items;
    } catch (error) {
      console.warn('[TmdbService] Error en getUpcomingMovies:', error.message);
      return [];
    }
  }

  /**
   * Obtiene películas por ID de género (ej. Acción = 28, Ciencia Ficción = 878) con soporte de paginación.
   */
  async getMoviesByGenre(genreId, page = 1) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/discover/movie', {
        params: {
          language: 'es-ES',
          with_genres: genreId,
          sort_by: 'popularity.desc',
          include_adult: false,
          page: page || 1
        }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'movie' }));
    } catch (error) {
      console.warn(`[TmdbService] Error en getMoviesByGenre (${genreId}):`, error.message);
      return [];
    }
  }

  /**
   * Obtiene películas mejor valoradas históricas (Top Rated).
   */
  async getTopRatedMovies(page = 1) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/movie/top_rated', {
        params: {
          language: 'es-ES',
          page: page || 1
        }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'movie' }));
    } catch (error) {
      console.warn('[TmdbService] Error en getTopRatedMovies:', error.message);
      return [];
    }
  }

  /**
   * Obtiene películas por año de estreno específico (2000 a 2026) con paginación y ordenadas por popularidad.
   * Auto-actualizado en tiempo real desde la base de datos de TMDB.
   * @param {number|string} year - Año de estreno (ej: 2026, 2024, 2005)
   * @param {number} [page=1] - Página de resultados
   */
  async getMoviesByYear(year, page = 1) {
    try {
      const client = this.getAxiosClient();
      const numYear = parseInt(year, 10) || 2026;
      const response = await client.get('/discover/movie', {
        params: {
          language: 'es-ES',
          primary_release_year: numYear,
          sort_by: 'popularity.desc',
          include_adult: false,
          'vote_count.gte': numYear >= 2025 ? 5 : 20,
          page: page || 1
        }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'movie' }));
    } catch (error) {
      console.warn(`[TmdbService] Error en getMoviesByYear (${year}):`, error.message);
      return [];
    }
  }

  /**
   * Obtiene películas dentro de un rango de años (ej: 2000 a 2009, 2010 a 2019) ordenadas por aclamación y popularidad.
   */
  async getMoviesByYearRange(startYear, endYear, page = 1) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/discover/movie', {
        params: {
          language: 'es-ES',
          'primary_release_date.gte': `${startYear}-01-01`,
          'primary_release_date.lte': `${endYear}-12-31`,
          sort_by: 'popularity.desc',
          include_adult: false,
          'vote_count.gte': 50,
          page: page || 1
        }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'movie' }));
    } catch (error) {
      console.warn(`[TmdbService] Error en getMoviesByYearRange (${startYear}-${endYear}):`, error.message);
      return [];
    }
  }

  /**
   * Generador dinámico para Cartelera Infinita sin fin.
   * Por cada página solicitada, devuelve 3 filas temáticas completas.
   * Integra años desde el 2000 al 2026 con actualización continua y automática.
   * @param {number} page
   */
  async getInfiniteCategories(page = 1) {
    const categories = [];

    const genrePacks = [
      { title: '🍿 Estrenos y Cartelera 2026 (Auto-actualizado)', year: 2026 },
      { title: '🔥 Grandes Éxitos del Cine 2025', year: 2025 },
      { title: '⭐ Las Mejores Películas del 2024', year: 2024 },
      { title: '🏆 Lo Más Visto del 2023', year: 2023 },
      { title: '🕵️ Thriller, Intriga y Suspenso', genreId: 53 },
      { title: '😂 Comedias y Risas Aseguradas', genreId: 35 },
      { title: '🎞️ Películas Destacadas del 2022', year: 2022 },
      { title: '🎞️ Éxitos del 2021', year: 2021 },
      { title: '👻 Terror, Horror y Sobrenatural', genreId: 27 },
      { title: '🎨 Animación y Éxitos Familiares', genreId: 16 },
      { title: '🎞️ Cine del 2020', year: 2020 },
      { title: '🗺️ Aventuras Épicas y Fantásticas', genreId: 12 },
      { title: '💎 Grandes Éxitos 2015 - 2019', yearRange: [2015, 2019] },
      { title: '🎭 Obras Maestras del Drama', genreId: 18 },
      { title: '🕶️ Crimen, Policías y Mafia', genreId: 80 },
      { title: '👑 Clásicos Modernos 2010 - 2014', yearRange: [2010, 2014] },
      { title: '⭐ Películas Aclamadas por la Crítica', custom: 'top_rated' },
      { title: '📽️ Cine de Culto e Inolvidables 2000 - 2009', yearRange: [2000, 2009] },
      { title: '🔮 Misterio, Enigmas y Secretos', genreId: 9648 },
      { title: '⚔️ Cine Bélico e Historia Militar', genreId: 10752 },
      { title: '🧙 Fantasía, Hechizos y Leyendas', genreId: 14 },
      { title: '💖 Romance y Grandes Emociones', genreId: 10749 }
    ];

    const count = 3;
    const startIndex = ((page - 1) * count) % genrePacks.length;
    const selectedPacks = [];
    for (let i = 0; i < count; i++) {
      selectedPacks.push(genrePacks[(startIndex + i) % genrePacks.length]);
    }

    const tmdbPage = Math.floor(((page - 1) * count) / genrePacks.length) + 1;

    for (const pack of selectedPacks) {
      try {
        let items = [];
        if (pack.year) {
          items = await this.getMoviesByYear(pack.year, tmdbPage);
        } else if (pack.yearRange) {
          items = await this.getMoviesByYearRange(pack.yearRange[0], pack.yearRange[1], tmdbPage);
        } else if (pack.custom === 'top_rated') {
          items = await this.getTopRatedMovies(tmdbPage);
        } else if (pack.genreId) {
          items = await this.getMoviesByGenre(pack.genreId, tmdbPage);
        }

        if (items && items.length > 0) {
          categories.push({
            title: `${pack.title} ${tmdbPage > 1 ? `(Página ${tmdbPage})` : ''}`.trim(),
            items
          });
        }
      } catch (_) {}
    }

    return categories;
  }

  /**
   * Obtiene las series de televisión más populares en español.
   */
  async getPopularTvShows() {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/tv/popular', {
        params: { language: 'es-ES', page: 1 }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'tv' }));
    } catch (error) {
      console.warn('[TmdbService] Error en getPopularTvShows:', error.message);
      return [];
    }
  }

  /**
   * Lista oficial de géneros cinematográficos con íconos representativos para VJ STREAM.
   */
  getGenresList() {
    return [
      { id: 28, name: 'Acción', icon: '💥' },
      { id: 35, name: 'Comedia', icon: '😂' },
      { id: 27, name: 'Terror', icon: '😱' },
      { id: 878, name: 'Ciencia Ficción', icon: '🚀' },
      { id: 16, name: 'Animación', icon: '🎨' },
      { id: 53, name: 'Suspenso', icon: '🕵️' },
      { id: 12, name: 'Aventura', icon: '🗺️' },
      { id: 14, name: 'Fantasía', icon: '🧙' },
      { id: 10749, name: 'Romance', icon: '💖' },
      { id: 18, name: 'Drama', icon: '🎭' },
      { id: 80, name: 'Crimen', icon: '🕶️' }
    ];
  }

  /**
   * Descubre series con parámetros personalizados de TMDB.
   */
  async discoverTv(params = {}) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/discover/tv', {
        params: {
          language: 'es-ES',
          sort_by: 'popularity.desc',
          include_adult: false,
          page: 1,
          ...params
        }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'tv' }));
    } catch (error) {
      console.warn('[TmdbService] Error en discoverTv:', error.message);
      return [];
    }
  }

  /**
   * Descubre películas con parámetros personalizados de TMDB.
   */
  async discoverMovie(params = {}) {
    try {
      const client = this.getAxiosClient();
      const response = await client.get('/discover/movie', {
        params: {
          language: 'es-ES',
          sort_by: 'popularity.desc',
          include_adult: false,
          page: 1,
          ...params
        }
      });
      return (response.data.results || []).map(item => this.formatMediaItem({ ...item, media_type: 'movie' }));
    } catch (error) {
      console.warn('[TmdbService] Error en discoverMovie:', error.message);
      return [];
    }
  }

  /**
   * Catálogo especializado para Niños y Familia (Dibujos animados, caricaturas, películas y anime infantil)
   */
  async getKidsCatalog() {
    try {
      const [moviesRaw, cartoonsRaw, animeRaw, classicsRaw] = await Promise.all([
        // 1. Películas animadas y familiares (Disney, Pixar, Dreamworks, Illumination)
        this.discoverMovie({
          with_genres: '16,10751',
          'vote_count.gte': 40
        }),
        // 2. Dibujos animados y series de caricaturas populares
        this.discoverTv({
          with_genres: '16',
          'vote_count.gte': 20
        }),
        // 3. Anime familiar y aventuras
        this.discoverTv({
          with_genres: '16',
          with_original_language: 'ja',
          'vote_count.gte': 25
        }),
        // 4. Clásicos inolvidables de la animación infantil (1990 - 2015)
        this.discoverMovie({
          with_genres: '16',
          'primary_release_date.gte': '1990-01-01',
          'primary_release_date.lte': '2015-12-31',
          'vote_count.gte': 80
        })
      ]);

      const seen = new Set();
      const dedupe = (items) => (items || []).filter(item => {
        if (!item || !item.id || seen.has(item.id)) return false;
        seen.add(item.id);
        return true;
      });

      return {
        movies: dedupe(moviesRaw),
        cartoons: dedupe(cartoonsRaw),
        anime: dedupe(animeRaw),
        classics: dedupe(classicsRaw)
      };
    } catch (error) {
      console.warn('[TmdbService] Error en getKidsCatalog:', error.message);
      return { movies: [], cartoons: [], anime: [], classics: [] };
    }
  }

  /**
   * Catálogo especializado de Telenovelas (Mexicanas, Colombianas, Turcas, K-Dramas y Dramas Románticos)
   */
  async getTelenovelasCatalog() {
    try {
      // IDs de grandes telenovelas históricas y queridas por la audiencia
      const iconicShowIds = [16286, 11250, 80240, 124124, 12926, 18059, 65555, 104877, 87623];

      const [iconicShows, latamRaw, turkishRaw, kdramaRaw] = await Promise.all([
        Promise.all(iconicShowIds.map(async id => {
          try {
            return await this.getTvShowDetails(id);
          } catch (_) { return null; }
        })).then(list => list.filter(Boolean)),
        // 1. Telenovelas latinoamericanas en emisión / populares
        this.discoverTv({
          with_original_language: 'es',
          with_genres: '10766',
          'vote_count.gte': 5
        }),
        // 2. Grandes novelas turcas dobladas al español
        this.discoverTv({
          with_original_language: 'tr',
          'vote_count.gte': 10
        }),
        // 3. Dramas coreanos y romance aclamados
        this.discoverTv({
          with_original_language: 'ko',
          with_genres: '18',
          'vote_count.gte': 30
        })
      ]);

      const seen = new Set();
      const dedupe = (items) => (items || []).filter(item => {
        if (!item || !item.id || seen.has(item.id)) return false;
        seen.add(item.id);
        return true;
      });

      const combinedLatam = dedupe([
        ...iconicShows.filter(s => s.originalLanguage === 'es' || ['16286','11250','80240','124124','12926','18059'].includes(String(s.id))),
        ...latamRaw
      ]);
      const combinedTurkish = dedupe([
        ...iconicShows.filter(s => s.originalLanguage === 'tr' || ['65555','104877','87623'].includes(String(s.id))),
        ...turkishRaw
      ]);

      return {
        latamNovelas: combinedLatam,
        turkishNovelas: combinedTurkish,
        kdramas: dedupe(kdramaRaw)
      };
    } catch (error) {
      console.warn('[TmdbService] Error en getTelenovelasCatalog:', error.message);
      return { latamNovelas: [], turkishNovelas: [], kdramas: [] };
    }
  }

  /**
   * Catálogo especializado de Cine de Acción, Adrenalina y Deportes
   */
  async getActionSportsCatalog() {
    try {
      const [actionRaw, thrillersRaw, sportsRaw] = await Promise.all([
        // 1. Películas de pura acción y adrenalina
        this.discoverMovie({
          with_genres: '28',
          'vote_count.gte': 80
        }),
        // 2. Crimen, suspenso y mafia
        this.discoverMovie({
          with_genres: '80,53',
          'vote_count.gte': 60
        }),
        // 3. Películas de deportes / fútbol / artes marciales
        this.discoverMovie({
          with_genres: '28,18',
          with_keywords: '6075|207884|9840',
          'vote_count.gte': 20
        })
      ]);

      const seen = new Set();
      const dedupe = (items) => (items || []).filter(item => {
        if (!item || !item.id || seen.has(item.id)) return false;
        seen.add(item.id);
        return true;
      });

      return {
        actionMovies: dedupe(actionRaw),
        thrillers: dedupe(thrillersRaw),
        sportsMovies: dedupe(sportsRaw.length > 0 ? sportsRaw : actionRaw.slice(10))
      };
    } catch (error) {
      console.warn('[TmdbService] Error en getActionSportsCatalog:', error.message);
      return { actionMovies: [], thrillers: [], sportsMovies: [] };
    }
  }

  /**
   * Retorna el catálogo ampliado y consolidado con DESDUPLICACIÓN ESTRICTA.
   * Garantiza que ninguna película se repita en más de una categoría.
   */
  async getFullCatalog() {
    try {
      const [
        nowPlayingRaw,
        upcomingRaw,
        trendingRaw,
        actionRaw,
        comedyRaw,
        horrorRaw,
        animationRaw,
        scifiRaw,
        adventureRaw,
        classicsRaw,
        seriesRaw
      ] = await Promise.all([
        this.getNowPlayingMovies(),
        this.getUpcomingMovies(1),
        this.getTrendingWeekly(),
        this.getMoviesByGenre(28, 1),   // Acción
        this.getMoviesByGenre(35, 1),   // Comedia
        this.getMoviesByGenre(27, 1),   // Terror
        this.getMoviesByGenre(16, 1),   // Animación
        this.getMoviesByGenre(878, 1),  // Ciencia Ficción
        this.getMoviesByGenre(12, 1),   // Aventura
        this.getMoviesByYearRange(2000, 2015, 1), // Clásicos modernos
        this.getPopularTvShows()        // Series
      ]);

      // Control estricto de desduplicación cruzada: ningún ID se repite en todo el catálogo
      const seenIds = new Set();
      const dedupe = (items) => {
        if (!Array.isArray(items)) return [];
        return items.filter(item => {
          if (!item || !item.id) return false;
          if (seenIds.has(item.id)) return false;
          seenIds.add(item.id);
          return true;
        });
      };

      const nowPlaying = dedupe(nowPlayingRaw);
      const upcoming = dedupe(upcomingRaw);
      const trending = dedupe(trendingRaw);
      const action = dedupe(actionRaw);
      const comedy = dedupe(comedyRaw);
      const horror = dedupe(horrorRaw);
      const animation = dedupe(animationRaw);
      const scifi = dedupe(scifiRaw);
      const adventure = dedupe(adventureRaw);
      const classics = dedupe(classicsRaw);
      const series = dedupe(seriesRaw);

      return {
        nowPlaying,
        upcoming,
        trending,
        action,
        comedy,
        horror,
        animation,
        scifi,
        adventure,
        classics,
        series
      };
    } catch (error) {
      this.handleError('getFullCatalog', error);
    }
  }

  /**
   * Manejador centralizado y normalizador de errores para peticiones a TMDB.
   * @private
   */
  handleError(action, error) {
    let statusCode = 500;
    let message = `Error desconocido en TmdbService.${action}`;

    if (error.response) {
      statusCode = error.response.status;
      const errorData = error.response.data;
      const apiMessage = errorData?.status_message || errorData?.message || JSON.stringify(errorData);
      message = `TMDB API Error (${statusCode}) en ${action}: ${apiMessage}`;
    } else if (error.request) {
      message = `No hubo respuesta del servidor de TMDB en ${action}.`;
    } else {
      message = error.message || message;
    }

    const customError = new Error(message);
    customError.statusCode = statusCode;
    customError.originalError = error;
    throw customError;
  }
}

module.exports = new TmdbService();
