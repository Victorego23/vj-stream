const { MongoClient } = require('mongodb');
const path = require('path');
const fs = require('fs');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://egocheagav_db_user:Tomtv2026@cluster0.b3rdzbc.mongodb.net/tomtv?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'tomtv';
const COLLECTION_NAME = 'movies_catalog';

/**
 * Servicio Centralizado de Base de Datos para el Catálogo Masivo de Películas (50,000+ Títulos)
 * Almacenado en MongoDB Atlas con índices de alto rendimiento y caché en memoria.
 */
class MovieDatabaseService {
  constructor() {
    this._client = null;
    this._db = null;
    this._collection = null;
    this._isConnected = false;
    this._isInitializing = false;
    this._memoryCache = new Map();
    this.CACHE_TTL_MS = 10 * 60 * 1000; // 10 min de caché en RAM para consultas frecuentes
  }

  /**
   * Inicializa la conexión y crea los índices necesarios para búsquedas ultrarrápidas (< 5ms)
   */
  async init() {
    if (this._isConnected || this._isInitializing) return;
    this._isInitializing = true;

    try {
      this._client = new MongoClient(MONGODB_URI, {
        serverSelectionTimeoutMS: 8000,
        connectTimeoutMS: 12000,
        maxPoolSize: 20
      });

      await this._client.connect();
      this._db = this._client.db(DB_NAME);
      this._collection = this._db.collection(COLLECTION_NAME);
      this._isConnected = true;
      this._isInitializing = false;

      console.log('🍃 [MovieDatabaseService] Conexión establecida con MongoDB Atlas para movies_catalog.');

      // Crear índices estratégicos de alto rendimiento en segundo plano
      await this._ensureIndexes();
    } catch (err) {
      this._isInitializing = false;
      this._isConnected = false;
      console.warn('⚠️ [MovieDatabaseService] No se pudo conectar a MongoDB Atlas (modo de contingencia):', err.message);
    }
  }

  /**
   * Crea los índices necesarios para filtros instantáneos y búsqueda de texto completo
   * @private
   */
  async _ensureIndexes() {
    if (!this._collection) return;
    try {
      // 1. Índice único por TMDB ID
      await this._collection.createIndex({ tmdbId: 1 }, { unique: true });

      // 2. Índice por IMDb ID
      await this._collection.createIndex({ imdbId: 1 }, { sparse: true });

      // 3. Índice de texto para búsqueda instantánea en español e inglés
      await this._collection.createIndex(
        { title: 'text', originalTitle: 'text', collectionName: 'text', overview: 'text' },
        { default_language: 'spanish', weights: { title: 10, originalTitle: 8, collectionName: 6, overview: 2 } }
      );

      // 4. Índices compuestos para filtros rápidos combinados
      await this._collection.createIndex({ releaseYear: -1, popularity: -1 });
      await this._collection.createIndex({ genres: 1, popularity: -1 });
      await this._collection.createIndex({ platform: 1, popularity: -1 });
      await this._collection.createIndex({ collectionName: 1 });
      await this._collection.createIndex({ popularity: -1 });
      await this._collection.createIndex({ voteAverage: -1, voteCount: -1 });

      console.log('🍃 [MovieDatabaseService] Índices creados y validados correctamente.');
    } catch (err) {
      console.warn('[MovieDatabaseService] Advertencia al crear índices:', err.message);
    }
  }

  /**
   * Verifica si la base de datos está conectada
   */
  isConnected() {
    return this._isConnected && this._collection !== null;
  }

  /**
   * Inserta o actualiza una película en el catálogo
   * @param {Object} movie
   */
  async upsertMovie(movie) {
    if (!this.isConnected() || !movie || !movie.tmdbId) return null;
    try {
      const filter = { tmdbId: movie.tmdbId };
      const update = {
        $set: {
          ...movie,
          updatedAt: new Date()
        },
        $setOnInsert: {
          createdAt: new Date()
        }
      };
      return await this._collection.updateOne(filter, update, { upsert: true });
    } catch (err) {
      console.error(`[MovieDatabaseService] Error al guardar película ${movie.tmdbId}:`, err.message);
      return null;
    }
  }

  /**
   * Inserta o actualiza un lote masivo de películas a alta velocidad
   * @param {Array<Object>} movies
   */
  async bulkUpsertMovies(movies) {
    if (!this.isConnected() || !Array.isArray(movies) || movies.length === 0) return 0;
    try {
      const operations = movies.map(movie => ({
        updateOne: {
          filter: { tmdbId: movie.tmdbId },
          update: {
            $set: {
              ...movie,
              updatedAt: new Date()
            },
            $setOnInsert: {
              createdAt: new Date()
            }
          },
          upsert: true
        }
      }));

      const res = await this._collection.bulkWrite(operations, { ordered: false });
      return (res.upsertedCount || 0) + (res.modifiedCount || 0);
    } catch (err) {
      console.error('[MovieDatabaseService] Error en bulkUpsertMovies:', err.message);
      return 0;
    }
  }

  /**
   * Explorador avanzado de películas con soporte para filtros combinados, orden y paginación
   * @param {Object} options
   */
  async getMoviesExplorer({
    page = 1,
    limit = 30,
    genreId = null,
    year = null,
    minYear = null,
    maxYear = null,
    platform = null,
    collectionName = null,
    sortBy = 'popularity.desc', // 'popularity.desc', 'releaseDate.desc', 'rating.desc', 'title.asc'
    search = null
  }) {
    if (!this.isConnected()) {
      return { page: 1, totalPages: 1, totalResults: 0, results: [] };
    }

    const safePage = Math.max(1, parseInt(page, 10) || 1);
    const safeLimit = Math.min(100, Math.max(1, parseInt(limit, 10) || 30));
    const skip = (safePage - 1) * safeLimit;

    // Cache key para resultados idénticos en memoria (10 min)
    const cacheKey = JSON.stringify({ page: safePage, limit: safeLimit, genreId, year, minYear, maxYear, platform, collectionName, sortBy, search });
    const cached = this._memoryCache.get(cacheKey);
    if (cached && (Date.now() - cached.timestamp < this.CACHE_TTL_MS)) {
      return cached.data;
    }

    try {
      const query = {};

      // 1. Filtro por Búsqueda de Texto
      if (search && search.trim().length > 0) {
        query.$text = { $search: search.trim() };
      }

      // 2. Filtro por Género
      if (genreId) {
        const gid = parseInt(genreId, 10);
        if (!isNaN(gid)) {
          query.genreIds = gid;
        }
      }

      // 3. Filtro por Año o Rango de Años
      if (year) {
        const y = parseInt(year, 10);
        if (!isNaN(y)) query.releaseYear = y;
      } else if (minYear || maxYear) {
        query.releaseYear = {};
        if (minYear) query.releaseYear.$gte = parseInt(minYear, 10);
        if (maxYear) query.releaseYear.$lte = parseInt(maxYear, 10);
      }

      // 4. Filtro por Plataforma (Netflix, Disney+, Max, etc.)
      if (platform && platform.toLowerCase() !== 'todas') {
        query.platform = new RegExp(platform.trim(), 'i');
      }

      // 5. Filtro por Saga / Colección
      if (collectionName) {
        query.collectionName = new RegExp(collectionName.trim(), 'i');
      }

      // 6. Ordenamiento
      let sort = { popularity: -1 };
      if (sortBy === 'releaseDate.desc') sort = { releaseDate: -1 };
      else if (sortBy === 'rating.desc') sort = { voteAverage: -1, voteCount: -1 };
      else if (sortBy === 'title.asc') sort = { title: 1 };
      else if (search) sort = { score: { $meta: 'textScore' }, popularity: -1 };

      const projection = search ? { score: { $meta: 'textScore' } } : {};

      const [totalResults, items] = await Promise.all([
        this._collection.countDocuments(query),
        this._collection
          .find(query, { projection })
          .sort(sort)
          .skip(skip)
          .limit(safeLimit)
          .toArray()
      ]);

      const totalPages = Math.ceil(totalResults / safeLimit) || 1;

      const formattedResults = items.map(doc => ({
        id: doc.tmdbId,
        tmdbId: doc.tmdbId,
        imdbId: doc.imdbId,
        title: doc.title,
        originalTitle: doc.originalTitle,
        overview: doc.overview,
        releaseYear: doc.releaseYear,
        releaseDate: doc.releaseDate,
        genres: doc.genres || [],
        genreIds: doc.genreIds || [],
        voteAverage: doc.voteAverage,
        voteCount: doc.voteCount,
        popularity: doc.popularity,
        duration: doc.duration,
        platform: doc.platform,
        collectionName: doc.collectionName,
        posters: doc.posters || {
          thumbnail: doc.posterUrl,
          medium: doc.posterUrl,
          original: doc.posterUrl
        },
        backdrops: doc.backdrops || {
          thumbnail: doc.backdropUrl,
          medium: doc.backdropUrl,
          original: doc.backdropUrl
        },
        hasSpanishAudio: doc.hasSpanishAudio !== false,
        mediaType: 'movie'
      }));

      const response = {
        page: safePage,
        totalPages,
        totalResults,
        results: formattedResults
      };

      this._memoryCache.set(cacheKey, { timestamp: Date.now(), data: response });
      return response;
    } catch (err) {
      console.error('[MovieDatabaseService] Error en getMoviesExplorer:', err.message);
      return { page: safePage, totalPages: 1, totalResults: 0, results: [] };
    }
  }

  /**
   * Obtiene la lista de Sagas y Universos Cinematográficos disponibles con conteo de títulos
   */
  async getCollectionsList() {
    if (!this.isConnected()) return [];
    try {
      const collections = await this._collection.aggregate([
        { $match: { collectionName: { $exists: true, $ne: null, $ne: '' } } },
        {
          $group: {
            _id: '$collectionName',
            name: { $first: '$collectionName' },
            count: { $sum: 1 },
            posterUrl: { $first: '$posterUrl' },
            backdropUrl: { $first: '$backdropUrl' },
            avgRating: { $avg: '$voteAverage' }
          }
        },
        { $match: { count: { $gte: 2 } } },
        { $sort: { count: -1, avgRating: -1 } },
        { $limit: 40 }
      ]).toArray();

      return collections.map(c => ({
        name: c.name,
        count: c.count,
        posterUrl: c.posterUrl,
        backdropUrl: c.backdropUrl,
        rating: Math.round((c.avgRating || 7) * 10) / 10
      }));
    } catch (err) {
      console.warn('[MovieDatabaseService] Error en getCollectionsList:', err.message);
      return [];
    }
  }

  /**
   * Retorna estadísticas del catálogo indexado
   */
  async getStats() {
    if (!this.isConnected()) return { total: 0, connected: false };
    try {
      const total = await this._collection.countDocuments();
      return {
        total,
        connected: true
      };
    } catch (_) {
      return { total: 0, connected: false };
    }
  }
}

module.exports = new MovieDatabaseService();
