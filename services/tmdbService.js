const axios = require('axios');

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
        results: (data.results || []).map(item => this.formatMediaItem(item))
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
  async getMovieDetails(movieId, language = 'es-ES') {
    try {
      if (!movieId) throw new Error('El parámetro "movieId" es obligatorio.');

      const client = this.getAxiosClient();
      const lang = 'es-ES'; // Estrictamente español para VJ STREAM

      const response = await client.get(`/movie/${movieId}`, {
        params: {
          language: lang,
          include_image_language: 'es,null',
          append_to_response: 'credits,videos,recommendations'
        }
      });

      const data = response.data;
      const formatted = this.formatMediaItem({ ...data, media_type: 'movie' });

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
        trailer: (data.videos?.results || []).find(v => v.site === 'YouTube' && v.type === 'Trailer')?.key
          ? `https://www.youtube.com/watch?v=${(data.videos?.results || []).find(v => v.site === 'YouTube' && v.type === 'Trailer').key}`
          : null
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
          append_to_response: 'credits,videos,recommendations'
        }
      });

      const data = response.data;
      const formatted = this.formatMediaItem({ ...data, media_type: 'tv' });

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
        trailer: (data.videos?.results || []).find(v => v.site === 'YouTube' && v.type === 'Trailer')?.key
          ? `https://www.youtube.com/watch?v=${(data.videos?.results || []).find(v => v.site === 'YouTube' && v.type === 'Trailer').key}`
          : null
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
   * Generador dinámico para Cartelera Infinita sin fin.
   * Por cada página solicitada, devuelve 3 filas temáticas completas.
   * @param {number} page
   */
  async getInfiniteCategories(page = 1) {
    const categories = [];

    const genrePacks = [
      { title: '🕵️ Thriller, Intriga y Suspenso', genreId: 53 },
      { title: '😂 Comedias y Risas Aseguradas', genreId: 35 },
      { title: '👻 Terror, Horror y Sobrenatural', genreId: 27 },
      { title: '🎨 Animación y Éxitos Familiares', genreId: 16 },
      { title: '🗺️ Aventuras Épicas y Fantásticas', genreId: 12 },
      { title: '🎭 Obras Maestras del Drama', genreId: 18 },
      { title: '🕶️ Crimen, Policías y Mafia', genreId: 80 },
      { title: '⭐ Películas Aclamadas por la Crítica', custom: 'top_rated' },
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
        if (pack.custom === 'top_rated') {
          items = await this.getTopRatedMovies(tmdbPage);
        } else {
          items = await this.getMoviesByGenre(pack.genreId, tmdbPage);
        }
        if (items && items.length > 0) {
          categories.push({
            title: `${pack.title} ${tmdbPage > 1 ? `(Colección ${tmdbPage})` : ''}`.trim(),
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
   * Retorna las 5 categorías principales del catálogo consolidado en paralelo.
   */
  async getFullCatalog() {
    try {
      const [trending, nowPlaying, action, scifi, series] = await Promise.all([
        this.getTrendingWeekly(),
        this.getNowPlayingMovies(),
        this.getMoviesByGenre(28),  // Acción
        this.getMoviesByGenre(878), // Ciencia Ficción
        this.getPopularTvShows()     // Series
      ]);

      return {
        trending,
        nowPlaying,
        action,
        scifi,
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
