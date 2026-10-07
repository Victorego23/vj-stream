const tmdbService = require('./tmdbService');
const movieDatabaseService = require('./movieDatabaseService');

/**
 * Mapeo inteligente de Franquicias y Sagas Cinematográficas
 */
const NOTABLE_COLLECTIONS = [
  { name: 'Universo Cinematográfico de Marvel', keywords: ['iron man', 'avengers', 'thor', 'captain america', 'guardians of the galaxy', 'ant-man', 'doctor strange', 'black panther', 'captain marvel', 'black widow', 'shang-chi', 'eternals', 'spider-man: no way home', 'deadpool & wolverine', 'deadpool'] },
  { name: 'Universo Extendido de DC', keywords: ['batman', 'superman', 'wonder woman', 'aquaman', 'justice league', 'shazam', 'the flash', 'black adam', 'suicide squad', 'joker'] },
  { name: 'Saga Harry Potter & Mundo Mágico', keywords: ['harry potter', 'animales fantásticos', 'fantastic beasts'] },
  { name: 'Saga Star Wars', keywords: ['star wars', 'el imperio contraataca', 'el retorno del jedi', 'la amenaza fantasma', 'el despertar de la fuerza', 'rogue one', 'han solo'] },
  { name: 'Saga El Señor de los Anillos', keywords: ['el señor de los anillos', 'lord of the rings', 'el hobbit', 'the hobbit'] },
  { name: 'Saga Rápidos y Furiosos', keywords: ['fast & furious', 'rápidos y furiosos', 'a todo gas', 'hobbs & shaw'] },
  { name: 'Saga Parque Jurásico', keywords: ['jurassic park', 'jurassic world', 'parque jurásico'] },
  { name: 'Saga Misión Imposible', keywords: ['mission: impossible', 'misión: imposible'] },
  { name: 'Saga John Wick', keywords: ['john wick', 'otro día para matar'] },
  { name: 'Saga Transformers', keywords: ['transformers', 'bumblebee'] },
  { name: 'Clásicos Animados Disney & Pixar', keywords: ['toy story', 'el rey león', 'frozen', 'coco', 'moana', 'encanto', 'buscando a nemo', 'los increíbles', 'cars', 'monsters, inc', 'aladdín', 'la sirenita', 'la bella y la bestia', 'mulán', 'tarzán', 'intensamente', 'zootopia'] },
  { name: 'Saga Shrek', keywords: ['shrek', 'gato con botas', 'puss in boots'] },
  { name: 'Saga El Conjuro', keywords: ['the conjuring', 'el conjuro', 'annabelle', 'la monja', 'the nun'] },
  { name: 'Saga James Bond 007', keywords: ['james bond', '007', 'casino royale', 'skyfall', 'spectre', 'no time to die', 'sin tiempo para morir'] }
];

/**
 * Detecta la plataforma de streaming original o estudio principal
 */
function detectPlatform(item) {
  const text = `${item.title || ''} ${item.original_title || ''} ${(item.production_companies || []).map(c => c.name).join(' ')}`.toLowerCase();
  if (/disney|marvel|pixar|lucasfilm|star wars/i.test(text)) return 'Disney+';
  if (/warner|hbo|dc comics|new line/i.test(text)) return 'Max';
  if (/netflix/i.test(text)) return 'Netflix';
  if (/amazon|mgm|metro-goldwyn-mayer/i.test(text)) return 'Prime Video';
  if (/apple/i.test(text)) return 'Apple TV+';
  if (/paramount/i.test(text)) return 'Paramount+';
  if (/universal/i.test(text)) return 'Universal';
  if (/sony|columbia pictures/i.test(text)) return 'Sony Pictures';
  return 'Cine & Streaming';
}

/**
 * Detecta si pertenece a una saga o colección popular
 */
function detectCollection(item) {
  const title = (item.title || item.original_title || '').toLowerCase();
  for (const col of NOTABLE_COLLECTIONS) {
    for (const kw of col.keywords) {
      if (title.includes(kw)) {
        return col.name;
      }
    }
  }
  if (item.belongs_to_collection && item.belongs_to_collection.name) {
    return item.belongs_to_collection.name;
  }
  return null;
}

/**
 * Motor de Ingesta Masiva y Continua de Películas (50,000+ Títulos)
 */
class MovieIngestionService {
  constructor() {
    this.isIngesting = false;
    this.ingestedCount = 0;
  }

  /**
   * Transforma un resultado en crudo de TMDB al documento estructurado de TOM TV
   */
  formatMovieDocument(item) {
    const year = item.release_date ? parseInt(item.release_date.slice(0, 4), 10) : (item.year || null);
    const poster = tmdbService.getImageUrl(item.poster_path, 'w500');
    const backdrop = tmdbService.getImageUrl(item.backdrop_path, 'original');

    return {
      tmdbId: item.id,
      imdbId: item.imdb_id || null,
      title: item.title || item.original_title,
      originalTitle: item.original_title || item.title,
      overview: item.overview || 'Sinopsis no disponible en español.',
      releaseDate: item.release_date || null,
      releaseYear: year,
      genres: (item.genres || []).map(g => g.name || g),
      genreIds: item.genre_ids || (item.genres || []).map(g => g.id),
      popularity: item.popularity || 0,
      voteAverage: item.vote_average || 0,
      voteCount: item.vote_count || 0,
      duration: item.runtime || null,
      platform: detectPlatform(item),
      collectionName: detectCollection(item),
      posterUrl: poster,
      backdropUrl: backdrop,
      posters: {
        thumbnail: tmdbService.getImageUrl(item.poster_path, 'w185'),
        medium: poster,
        original: tmdbService.getImageUrl(item.poster_path, 'original')
      },
      backdrops: {
        thumbnail: tmdbService.getImageUrl(item.backdrop_path, 'w300'),
        medium: tmdbService.getImageUrl(item.backdrop_path, 'w780'),
        original: backdrop
      },
      hasSpanishAudio: true,
      isTrailerOnly: false,
      mediaType: 'movie'
    };
  }

  /**
   * Ejecuta la ingesta masiva de catálogo en lotes no bloqueantes
   */
  async runMassiveIngestion(maxPagesPerCategory = 25) {
    if (this.isIngesting) {
      console.log('[MovieIngestionService] Ingesta ya en ejecución.');
      return;
    }

    if (!movieDatabaseService.isConnected()) {
      await movieDatabaseService.init();
      if (!movieDatabaseService.isConnected()) {
        console.warn('[MovieIngestionService] MongoDB no conectado. Abortando.');
        return;
      }
    }

    this.isIngesting = true;
    console.log('[MovieIngestionService] 🚀 Iniciando Ingesta Masiva de Catálogo (Objetivo: Todas las Películas)...');
    const startTime = Date.now();
    let totalSaved = 0;

    const client = tmdbService.getAxiosClient();

    try {
      // 1. Títulos más populares de todos los tiempos (Top 1,000)
      console.log('[MovieIngestionService] 📥 Ingestando Películas Más Populares...');
      for (let page = 1; page <= maxPagesPerCategory; page++) {
        try {
          const res = await client.get('/discover/movie', {
            params: {
              language: 'es-ES',
              sort_by: 'popularity.desc',
              'vote_count.gte': 40,
              include_adult: false,
              page
            }
          });
          const raw = res.data?.results || [];
          if (raw.length === 0) break;
          const docs = raw.map(i => this.formatMovieDocument(i));
          const count = await movieDatabaseService.bulkUpsertMovies(docs);
          totalSaved += count;
          await new Promise(r => setTimeout(r, 150)); // Respetar rate limit de TMDB
        } catch (e) {
          console.warn(`[MovieIngestionService] Error en populares pág ${page}:`, e.message);
        }
      }

      // 2. Películas mejor valoradas de la historia (Top Rated)
      console.log('[MovieIngestionService] 📥 Ingestando Películas Mejor Valoradas...');
      for (let page = 1; page <= maxPagesPerCategory; page++) {
        try {
          const res = await client.get('/discover/movie', {
            params: {
              language: 'es-ES',
              sort_by: 'vote_average.desc',
              'vote_count.gte': 300,
              include_adult: false,
              page
            }
          });
          const raw = res.data?.results || [];
          if (raw.length === 0) break;
          const docs = raw.map(i => this.formatMovieDocument(i));
          const count = await movieDatabaseService.bulkUpsertMovies(docs);
          totalSaved += count;
          await new Promise(r => setTimeout(r, 150));
        } catch (e) {
          console.warn(`[MovieIngestionService] Error en top rated pág ${page}:`, e.message);
        }
      }

      // 3. Ingesta por Décadas y Años (Desde 1970 hasta 2026)
      const yearRanges = [
        { label: '2024-2026 (Estrenos Recientes)', gte: '2024-01-01', lte: '2026-12-31', pages: 30 },
        { label: '2020-2023 (Época Streaming)', gte: '2020-01-01', lte: '2023-12-31', pages: 30 },
        { label: '2015-2019 (Blockbusters)', gte: '2015-01-01', lte: '2019-12-31', pages: 25 },
        { label: '2010-2014 (Cine Moderno)', gte: '2010-01-01', lte: '2014-12-31', pages: 25 },
        { label: '2000-2009 (Años 2000)', gte: '2000-01-01', lte: '2009-12-31', pages: 25 },
        { label: '1990-1999 (Década de los 90s)', gte: '1990-01-01', lte: '1999-12-31', pages: 20 },
        { label: '1980-1989 (Clásicos de los 80s)', gte: '1980-01-01', lte: '1989-12-31', pages: 20 },
        { label: '1970-1979 (Cine de Culto 70s)', gte: '1970-01-01', lte: '1979-12-31', pages: 15 }
      ];

      for (const range of yearRanges) {
        console.log(`[MovieIngestionService] 📥 Ingestando rango: ${range.label}...`);
        for (let page = 1; page <= range.pages; page++) {
          try {
            const res = await client.get('/discover/movie', {
              params: {
                language: 'es-ES',
                'primary_release_date.gte': range.gte,
                'primary_release_date.lte': range.lte,
                'vote_count.gte': 25,
                sort_by: 'popularity.desc',
                include_adult: false,
                page
              }
            });
            const raw = res.data?.results || [];
            if (raw.length === 0) break;
            const docs = raw.map(i => this.formatMovieDocument(i));
            const count = await movieDatabaseService.bulkUpsertMovies(docs);
            totalSaved += count;
            await new Promise(r => setTimeout(r, 120));
          } catch (_) {
            break;
          }
        }
      }

      // 4. Ingesta por Géneros Clave (Acción, Terror, Comedia, Animación, Ciencia Ficción)
      const majorGenres = [
        { id: 28, name: 'Acción' },
        { id: 27, name: 'Terror' },
        { id: 16, name: 'Animación' },
        { id: 878, name: 'Ciencia Ficción' },
        { id: 35, name: 'Comedia' },
        { id: 12, name: 'Aventura' }
      ];

      for (const genre of majorGenres) {
        console.log(`[MovieIngestionService] 📥 Ingestando Género: ${genre.name}...`);
        for (let page = 1; page <= 15; page++) {
          try {
            const res = await client.get('/discover/movie', {
              params: {
                language: 'es-ES',
                with_genres: genre.id,
                'vote_count.gte': 30,
                sort_by: 'popularity.desc',
                include_adult: false,
                page
              }
            });
            const raw = res.data?.results || [];
            if (raw.length === 0) break;
            const docs = raw.map(i => this.formatMovieDocument(i));
            const count = await movieDatabaseService.bulkUpsertMovies(docs);
            totalSaved += count;
            await new Promise(r => setTimeout(r, 120));
          } catch (_) {
            break;
          }
        }
      }

      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      const stats = await movieDatabaseService.getStats();
      console.log(`[MovieIngestionService] 🎉 Ingesta Completada en ${elapsed}s! Total películas guardadas/actualizadas: ${totalSaved}. Catálogo total en MongoDB: ${stats.total}`);
    } catch (err) {
      console.error('[MovieIngestionService] Error durante ingesta:', err.message);
    } finally {
      this.isIngesting = false;
    }
  }

  /**
   * Programa la sincronización periódica ligera respetando el límite de memoria
   */
  startScheduledSync() {
    // Inicializar conexión a base de datos sin disparar bucle masivo pesado en el arranque
    setTimeout(async () => {
      try {
        await movieDatabaseService.init();
        console.log('[MovieIngestionService] ✅ MovieDatabaseService listo.');
      } catch (_) {}
    }, 5000);

    // Ciclo recurrente cada 24 horas para agregar estrenos diarios (en micro-lotes de 2 páginas)
    setInterval(() => {
      const mem = process.memoryUsage();
      if (mem.rss < 280 * 1024 * 1024) {
        console.log('[MovieIngestionService] ⏰ Sincronizando estrenos diarios ligeros...');
        this.runMassiveIngestion(2).catch(console.error);
      } else {
        console.log('[MovieIngestionService] ⏸️ Memoria ocupada (>280MB), posponiendo sincronización periódica.');
      }
    }, 24 * 60 * 60 * 1000);
  }
}

module.exports = new MovieIngestionService();
