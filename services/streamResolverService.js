const axios = require('axios');
const realDebridService = require('./realDebridService');
const torboxService = require('./torboxService');
const tmdbService = require('./tmdbService');

/**
 * Servicio inteligente de resolución ultra-rápida de transmisiones para VJ STREAM.
 * Integra:
 * 1. Prioridad absoluta e infalible para Español Latino (Cinecalidad, 🇲🇽) y Castellano (🇪🇸).
 * 2. Detección instantánea de torrents ya cacheados en Real-Debrid ([RD+]) en < 500ms.
 * 3. Caché en memoria para respuestas inmediatas (~1ms).
 * 4. Filtro estricto Anti-CAM (cero grabaciones de cine).
 * 5. Priorización de contenedores MP4 con resolución 1080p para arranque instantáneo sin buffering.
 */
class StreamResolverService {
  constructor() {
    this.timeout = 7000;
    // Caché en memoria: key -> { timestamp, data } (6 horas para máxima velocidad y 0% de uso de CPU en reproducciones repetidas)
    this.cache = new Map();
    this.CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6 horas
  }

  /**
   * Genera una clave única para la caché en memoria.
   * @private
   */
  _getCacheKey(mediaInfo) {
    const { mediaType = 'movie', id, imdbId, season = 1, episode = 1 } = mediaInfo;
    const identifier = imdbId || id || mediaInfo.title;
    return `${mediaType}:${identifier}:${season}:${episode}`;
  }

  /**
   * Limpia un término de búsqueda para maximizar coincidencias.
   * @private
   */
  sanitizeTitle(title) {
    if (!title) return '';
    return title
      .replace(/[:!?.,'"]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Normaliza texto eliminando acentos, caracteres especiales y espacios redundantes.
   * @param {string} text
   * @returns {string}
   */
  normalizeText(text) {
    if (!text) return '';
    return text
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Extrae palabras clave significativas de un título excluyendo stopwords y conectores.
   * @param {string} title
   * @returns {string[]}
   */
  extractTitleKeywords(title) {
    if (!title) return [];
    const STOP_WORDS = new Set([
      'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas',
      'de', 'del', 'al', 'y', 'e', 'o', 'u', 'en', 'a', 'con', 'sin', 'por', 'para',
      'su', 'sus', 'mi', 'mis', 'tu', 'tus', 'se', 'lo', 'le', 'les', 'me', 'te',
      'yo', 'tu', 'el', 'ella', 'nosotros', 'ellos', 'soy', 'eres', 'es', 'somos', 'son',
      'the', 'a', 'an', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from', 'as', 'is', 'are', 'was', 'were'
    ]);

    const normalized = this.normalizeText(title);
    const words = normalized.split(' ').filter(w => w.length > 0);
    const meaningful = words.filter(w => !STOP_WORDS.has(w) && w.length >= 2);
    return meaningful.length > 0 ? meaningful : words.filter(w => w.length >= 2);
  }

  /**
   * Valida si un stream o archivo coincide con el título solicitado (evita falsos positivos como
   * "El Genio de los Deseos" o "El señor de la casa" cuando el usuario pidió "El Señor de los Cielos").
   * @param {string} candidateText - Nombre de archivo o título del torrent
   * @param {Object} mediaInfo - { title, originalTitle, year, mediaType, season, episode }
   * @returns {{ isMatch: boolean, matchCount: number, ratio: number, matchedKeywords: string[] }}
   */
  /**
   * Extrae el número de secuela o parte de un título (ej: "2", "3", "II", "Parte 2").
   * @param {string} text
   * @returns {string|null}
   */
  extractSequelNumber(text) {
    if (!text) return null;
    const norm = this.normalizeText(text);
    const roman = { i: '1', ii: '2', iii: '3', iv: '4', v: '5', vi: '6', vii: '7', viii: '8', ix: '9', x: '10' };
    
    // Partes o volúmenes explícitos: "part 2", "parte 3", "vol 1"
    const partMatch = norm.match(/\b(?:part|parte|vol|volumen|capitulo)\s*([0-9ivx]+)\b/i);
    if (partMatch) {
      const val = partMatch[1].toLowerCase();
      return roman[val] || val;
    }
    // Números arábigos o romanos aislados: 2 al 10 o ii al x
    const numMatch = norm.match(/\b([2-9]|10|ii|iii|iv|v|vi|vii|viii|ix|x)\b/i);
    if (numMatch) {
      const val = numMatch[1].toLowerCase();
      return roman[val] || val;
    }
    return null;
  }

  /**
   * Extrae años de 4 dígitos relevantes de un texto (1930 a 2030, excluyendo 1080p).
   * @param {string} text
   * @returns {number[]}
   */
  extractYears(text) {
    if (!text) return [];
    const norm = this.normalizeText(text);
    const matches = norm.match(/\b(19[3-9]\d|20[0-3]\d)\b/g);
    if (!matches) return [];
    return matches.map(Number).filter(y => y !== 1080);
  }

  /**
   * Extrae temporada y episodio de un texto para series de televisión.
   * @param {string} text
   * @returns {{ season: number|null, episode: number|null }}
   */
  extractTvSeasonEpisode(text) {
    if (!text) return { season: null, episode: null };
    const lower = text.toLowerCase();
    const m1 = lower.match(/\bs?(\d{1,2})[.\s_-]*[ex](\d{1,3})\b/);
    if (m1) return { season: parseInt(m1[1], 10), episode: parseInt(m1[2], 10) };
    const mCap = lower.match(/\bcap(?:itulo)?[.\s_-]*(\d)(\d{2})\b/);
    if (mCap) return { season: parseInt(mCap[1], 10), episode: parseInt(mCap[2], 10) };
    const m3 = lower.match(/\b(?:ep|episodio|cap|capitulo)[.\s_-]*(\d{1,3})\b/);
    if (m3) return { season: null, episode: parseInt(m3[1], 10) };
    return { season: null, episode: null };
  }

  /**
   * Valida si un stream o archivo coincide con el título solicitado.
   * Aplica 4 barreras estrictas:
   * 1. Barrera de Secuela: Terrifier 3 jamás acepta Terrifier 1 o 2.
   * 2. Barrera de Año: Road House (2024) jamás acepta Road House (1989).
   * 3. Barrera de Episodio: Capítulo 4 jamás acepta Capítulo 1.
   * 4. Barrera de Palabras Clave: Requiere coincidencia de términos distintivos.
   * @param {string} candidateText - Nombre de archivo o título del torrent
   * @param {Object} mediaInfo - { title, originalTitle, year, mediaType, season, episode }
   * @returns {{ isMatch: boolean, matchCount: number, ratio: number, matchedKeywords: string[], reason?: string }}
   */
  validateTitleMatch(candidateText, mediaInfo) {
    if (!candidateText || !mediaInfo) return { isMatch: true, matchCount: 0, ratio: 1, matchedKeywords: [] };
    const { title, originalTitle } = mediaInfo;
    if (!title && !originalTitle) return { isMatch: true, matchCount: 0, ratio: 1, matchedKeywords: [] };

    // --- BARRERA 1: CONTROL ESTRICTO DE SECUELA Y NÚMERO DE FRANQUICIA ---
    const reqSequel = this.extractSequelNumber(title) || this.extractSequelNumber(originalTitle);
    const candSequel = this.extractSequelNumber(candidateText);
    if (reqSequel && candSequel && reqSequel !== candSequel) {
      // Ejemplo: Pidió Terrifier 3 y el archivo es Terrifier 2 -> RECHAZAR
      return { isMatch: false, reason: 'sequel_mismatch', matchCount: 0, ratio: 0, matchedKeywords: [] };
    }
    if (reqSequel && !candSequel) {
      // Ejemplo: Pidió Terrifier 3 y el archivo es Terrifier 1 (sin número) -> RECHAZAR
      return { isMatch: false, reason: 'missing_sequel_number', matchCount: 0, ratio: 0, matchedKeywords: [] };
    }
    if (!reqSequel && candSequel) {
      // Ejemplo: Pidió Gladiator (2000) y el archivo es Gladiator II -> RECHAZAR
      return { isMatch: false, reason: 'unwanted_sequel', matchCount: 0, ratio: 0, matchedKeywords: [] };
    }

    // --- BARRERA 2: CONTROL ESTRICTO DE AÑO (Evita remakes o películas homónimas) ---
    if (mediaInfo.year) {
      const targetYear = parseInt(mediaInfo.year, 10);
      if (!isNaN(targetYear) && targetYear > 1940) {
        const candYears = this.extractYears(candidateText);
        if (candYears.length > 0) {
          const hasCloseYear = candYears.some(y => Math.abs(y - targetYear) <= 1);
          if (!hasCloseYear) {
            // Ejemplo: Pidió Road House (2024) y el archivo tiene 1989 -> RECHAZAR
            return { isMatch: false, reason: 'year_mismatch', matchCount: 0, ratio: 0, matchedKeywords: [] };
          }
        }
      }
    }

    // --- BARRERA 3: CONTROL ESTRICTO DE EPISODIO Y TEMPORADA PARA SERIES ---
    if (mediaInfo.mediaType === 'tv' && mediaInfo.episode) {
      const targetEp = parseInt(mediaInfo.episode, 10);
      const targetSeason = parseInt(mediaInfo.season, 10) || 1;
      const { season: candSeason, episode: candEp } = this.extractTvSeasonEpisode(candidateText);
      if (candEp !== null && candEp !== targetEp) {
        // Archivo indica un capítulo diferente -> RECHAZAR
        return { isMatch: false, reason: 'tv_episode_mismatch', matchCount: 0, ratio: 0, matchedKeywords: [] };
      }
      if (candSeason !== null && candSeason !== targetSeason) {
        // Archivo indica otra temporada -> RECHAZAR
        return { isMatch: false, reason: 'tv_season_mismatch', matchCount: 0, ratio: 0, matchedKeywords: [] };
      }
    }

    // --- BARRERA 4: COINCIDENCIA SEMÁNTICA DE PALABRAS CLAVE DISTINTIVAS ---
    const GENERIC_TITLE_WORDS = new Set([
      'senor', 'senora', 'don', 'dona', 'doctor', 'dra', 'casa', 'vida', 'mundo',
      'hombre', 'mujer', 'historia', 'tierra', 'amor', 'nuevo', 'nueva', 'gran', 'grande',
      'primer', 'primera', 'san', 'santa', 'rey', 'reina'
    ]);

    const normCandidate = this.normalizeText(candidateText);
    const candidateTokens = normCandidate.split(' ').filter(Boolean);

    const kwTitle = this.extractTitleKeywords(title);
    const kwOrig = this.extractTitleKeywords(originalTitle);

    const matchesKw = (kw) => {
      if (kw.length <= 3) {
        const regex = new RegExp(`(^|\\s)${kw}(\\s|$)`, 'i');
        return regex.test(normCandidate);
      }
      if (normCandidate.includes(kw)) return true;
      return candidateTokens.some(tok => {
        if (tok.length >= 4 && kw.length >= 4) {
          if (tok.startsWith(kw.slice(0, 3)) || kw.startsWith(tok.slice(0, 3))) {
            if (Math.abs(tok.length - kw.length) <= 1) return true;
          }
        }
        return false;
      });
    };

    const titleMatches = kwTitle.filter(matchesKw);
    const origMatches = kwOrig.filter(matchesKw);

    const maxMatches = Math.max(titleMatches.length, origMatches.length);
    const totalKw = titleMatches.length >= origMatches.length ? kwTitle.length : kwOrig.length;
    const ratio = totalKw > 0 ? (maxMatches / totalKw) : 0;
    const matchedKeywords = Array.from(new Set([...titleMatches, ...origMatches]));

    const distinctiveTitleKw = kwTitle.filter(k => !GENERIC_TITLE_WORDS.has(k));
    const distinctiveOrigKw = kwOrig.filter(k => !GENERIC_TITLE_WORDS.has(k));
    const matchedDistinctive = matchedKeywords.filter(k => !GENERIC_TITLE_WORDS.has(k));

    let isMatch = false;
    if (distinctiveTitleKw.length > 0 || distinctiveOrigKw.length > 0) {
      const hasDistinctiveMatch = matchedDistinctive.length > 0;
      if (hasDistinctiveMatch) {
        if (totalKw >= 2 && maxMatches < 2 && (distinctiveTitleKw.length >= 2 || distinctiveOrigKw.length >= 2)) {
          isMatch = ratio >= 0.5;
        } else {
          isMatch = true;
        }
      } else {
        isMatch = false;
      }
    } else {
      isMatch = totalKw > 1 ? (maxMatches >= 2 || ratio >= 0.6) : (maxMatches >= 1);
    }

    return {
      isMatch,
      matchCount: maxMatches,
      ratio,
      matchedKeywords
    };
  }

  /**
   * Pondera y clasifica un stream según idioma, calidad, fidelidad al título y compatibilidad.
   * Garantiza que el Español Latino y Castellano superen a cualquier versión en inglés u otro idioma,
   * y descarta inmediatamente streams cuyo contenido no coincida con la película o serie solicitada.
   * @private
   */
  scoreStream(stream, mediaInfo = null) {
    const rawTitle = stream.title || '';
    const name = (stream.name || '').toLowerCase();
    const titleLines = rawTitle.split('\n');
    const firstLine = (titleLines[0] || '').toLowerCase();
    const metaLine = (titleLines[1] || '').toLowerCase();
    const langLine = (titleLines[2] || '').toLowerCase();
    const filename = (stream.behaviorHints?.filename || '').toLowerCase();
    const fullText = `${rawTitle.toLowerCase()} ${name} ${filename}`;

    // 0. VALIDACIÓN ESTRICTA DE TÍTULO (Anti-Mismatch / Anti-Falsos Positivos)
    // Impide que una serie no relacionada (ej: "El Genio de los Deseos") se reproduzca
    // cuando el usuario pidió "El Señor de los Cielos", protegiendo todo el catálogo.
    let titleMatch = { isMatch: true, matchCount: 0, ratio: 1, matchedKeywords: [] };
    if (mediaInfo && (mediaInfo.title || mediaInfo.originalTitle)) {
      const candidateToVerify = `${firstLine} ${filename}`;
      titleMatch = this.validateTitleMatch(candidateToVerify, mediaInfo);
      if (!titleMatch.isMatch) {
        return {
          stream,
          score: -999999,
          audioLanguage: 'Título Incorrecto (Mismatch)',
          isSpanishAudio: false,
          isTitleMismatch: true
        };
      }
    }

    // 1. FILTRO ANTI-CAM ESTRICTO: Descartar de inmediato grabaciones de cine
    if (realDebridService.isCamOrLowQuality(fullText)) {
      return { stream, score: -999999, audioLanguage: 'CAM', isSpanishAudio: false };
    }

    // 2. DETECCIÓN DE PROVEEDORES 100% EN ESPAÑOL
    const isCinecalidad = fullText.includes('cinecalidad');
    const isMejorTorrent = fullText.includes('mejortorrent');
    const isWolfmax4k = fullText.includes('wolfmax4k');

    // 3. DETECCIÓN EN NOMBRE DEL ARCHIVO / TÍTULO DEL TORRENT (Línea 1 y nombre de archivo)
    const hasLatinoExplicit = /latino|audio[\s._-]*latino|doblaje[\s._-]*latino|dual[\s._-]*lat|lat[\s._-]*cinecalidad|latam|latinoamerica|mexico|mexicano|\b(lat)\b/i.test(firstLine) ||
      /latino|audio[\s._-]*latino|doblaje[\s._-]*latino|dual[\s._-]*lat|lat[\s._-]*cinecalidad|latam|latinoamerica|mexico|mexicano|\b(lat)\b/i.test(filename) ||
      /\b(eng[\s._-]*lat|lat[\s._-]*eng|spa[\s._-]*lat|lat[\s._-]*spa)\b/i.test(fullText);

    const hasCastellanoExplicit = /castellano|doblaje[\s._-]*castellano|audio[\s._-]*castellano|\b(cast)\b/i.test(firstLine) ||
      /castellano|doblaje[\s._-]*castellano|audio[\s._-]*castellano|\b(cast)\b/i.test(filename) ||
      /español[\s._-]*castellano/i.test(fullText);

    const hasSpanishExplicit = /español|spanish|\b(esp|spa)\b/i.test(firstLine) ||
      /español|spanish|\b(esp|spa)\b/i.test(filename);

    // 4. DETECCIÓN EN LÍNEA DE IDIOMAS DE TORRENTIO (Línea 3)
    const isTorrentioLatino = langLine.includes('🇲🇽') ||
      /latino|mexic|latam/i.test(langLine) ||
      ((langLine.includes('dual audio') || langLine.includes('multi audio')) && langLine.includes('🇲🇽'));

    const isTorrentioCastellano = langLine.includes('🇪🇸') || /castellano/i.test(langLine);

    const isDualOrMultiSpanish = (/dual|multi/i.test(firstLine) || /dual|multi/i.test(filename) || langLine.includes('dual') || langLine.includes('multi')) &&
      (langLine.includes('🇲🇽') || langLine.includes('🇪🇸') || /lat|spa|esp|cast|spanish|español/i.test(fullText));

    // 5. DETECCIÓN DE CANALES DE AUDIO (Estéreo 2.0 vs 5.1 Surround)
    const isStereo = /aac(?!\s*5\.1)|2\.0|stereo|est[eé]reo|2ch|mp3|dd2\.0|ddp2\.0|\b(2\.0)\b/i.test(fullText);
    const isSurround = /5\.1|7\.1|ac3(?!\s*2\.0)|eac3(?!\s*2\.0)|dts|atmos|truehd/i.test(fullText);
    const audioChannels = isStereo ? 'Estéreo 2.0' : (isSurround ? '5.1 Surround' : 'Estéreo 2.0');

    // 6. FILTRO DE FALSOS POSITIVOS DE SUBTÍTULOS (Tigole, QxR, PSA, YTS con 5+ banderas que solo son subtítulos)
    const isSubtitleSpam = (langLine.split('/').length > 4);

    let score = 0;
    let audioLanguage = 'Audio Original';
    let isSpanishAudio = false;

    if (isCinecalidad || hasLatinoExplicit || isTorrentioLatino) {
      isSpanishAudio = true;
      audioLanguage = isStereo ? 'Español Latino Estéreo' : 'Español Latino';
      score += 6500;
      if (isCinecalidad) score += 1500; // Cinecalidad es la máxima pureza en Español Latino
      if (/eng[-_.]*lat|eng[-_.]*spa/i.test(firstLine)) {
        score -= 100;
      }
    } else if (isMejorTorrent || isWolfmax4k || hasCastellanoExplicit || isTorrentioCastellano) {
      isSpanishAudio = true;
      audioLanguage = isStereo ? 'Castellano Estéreo' : 'Castellano';
      score += 4800;
    } else if (isDualOrMultiSpanish || (hasSpanishExplicit && !isSubtitleSpam && !firstLine.includes('sub') && !filename.includes('sub'))) {
      isSpanishAudio = true;
      audioLanguage = isStereo ? 'Español Estéreo' : 'Español';
      score += 3800;
    } else {
      // Stream en idioma original / inglés (conservado únicamente como último recurso si no existe doblaje)
      isSpanishAudio = false;
      audioLanguage = isStereo ? 'Audio Original Estéreo' : 'Audio Original';
      score += 100;
    }

    // Ventaja para pistas Estéreo 2.0: Diálogos nítidos y sin problemas de voces bajas en Smart TV sin soundbar
    if (isStereo) {
      score += 150;
    }

    // Compatibilidad de audio en Smart TV (ExoPlayer)
    if (/\b(aac|ac3|eac3|ddp|dd\+|dd5\.1|dolby\s*digital)\b/i.test(fullText)) {
      score += 180;
    }
    // Penalizar pistas TrueHD, Atmos o DTS-HD que causan pantalla congelada o muda en Smart TVs básicas
    if (/\b(truehd|atmos|dts-hd|dts:x|dts-x|pcm|flac)\b/i.test(fullText)) {
      score -= 350;
    }

    // Control de tamaño de archivo para evitar buffering continuo en conexiones residenciales
    const sizeMatch = fullText.match(/(\d+(?:\.\d+)?)\s*(gb|gigabytes)/i);
    if (sizeMatch) {
      const sizeGb = parseFloat(sizeMatch[1]);
      if (sizeGb > 25) {
        score -= 400; // Demasiado pesado para streaming fluido en TV
      } else if (sizeGb >= 1.5 && sizeGb <= 12) {
        score += 200; // Peso balanceado óptimo
      }
    }

    // Calidad de video
    if (/1080p|1080i|fhd/i.test(fullText)) {
      score += 200;
    } else if (/4k|2160p|uhd/i.test(fullText)) {
      score += 130;
    } else if (/720p|hd/i.test(fullText)) {
      score += 50;
    }

    // Formato de contenedor (MP4 arranca veloz y con soporte directo)
    if (fullText.includes('.mp4') || filename.endsWith('.mp4')) {
      score += 140;
    }

    // Bonificación por fidelidad de título
    if (titleMatch.ratio >= 1.0) {
      score += 400;
    } else if (titleMatch.ratio >= 0.5) {
      score += 200;
    }

    // Bonificación si coincide el año en el nombre del archivo
    if (mediaInfo?.year && fullText.includes(String(mediaInfo.year))) {
      score += 100;
    }

    // Bonificación para series si el archivo contiene la numeración de episodio solicitada
    if (mediaInfo?.mediaType === 'tv' && mediaInfo?.season && mediaInfo?.episode) {
      const s = String(mediaInfo.season).padStart(2, '0');
      const e = String(mediaInfo.episode).padStart(2, '0');
      const epPatterns = [
        new RegExp(`s${s}e${e}`, 'i'),
        new RegExp(`${mediaInfo.season}x${e}`, 'i'),
        new RegExp(`cap[.\\s_-]*${e}`, 'i'),
        new RegExp(`ep[.\\s_-]*${e}`, 'i')
      ];
      if (epPatterns.some(p => p.test(fullText))) {
        score += 150;
      }
    }

    let qualityLabel = '1080p FHD';
    if (/4k|2160p|uhd/i.test(fullText)) qualityLabel = '4K UHD';
    else if (/720p/i.test(fullText)) qualityLabel = '720p HD';

    return {
      stream,
      score,
      audioLanguage,
      isSpanishAudio,
      audioChannels,
      qualityLabel,
      filename: stream.behaviorHints?.filename || stream.title?.split('\n')[0] || 'VJ-STREAM'
    };
  }

  /**
   * Detecta si una URL corresponde a un video estático de error o advertencia de Torrentio / Real-Debrid
   * (como la advertencia naranja de 'File was removed from debrid service due to copyright infringement').
   * @param {string} url
   * @returns {boolean}
   */
  isErrorVideoUrl(url) {
    if (!url || typeof url !== 'string') return true;
    const lower = url.toLowerCase();
    return (
      lower.includes('torrentio.strem.fun/videos') ||
      lower.includes('/videos/failed_') ||
      lower.includes('failed_unexpected') ||
      lower.includes('infringing') ||
      lower.includes('file_removed') ||
      lower.includes('copyright_infringement') ||
      lower.includes('dmca') ||
      lower.includes('error.mp4')
    );
  }

  /**
   * Verifica de forma proactiva si la URL de streaming es válida, accesible y reproduce un video real.
   * Descarta de inmediato pantallas de error de derechos de autor (HTTP 451, 403, páginas HTML o clips diminutos).
   * @param {string} url
   * @returns {Promise<boolean>}
   */
  async isStreamPlayable(url) {
    if (!url || typeof url !== 'string') return false;
    if (this.isErrorVideoUrl(url)) return false;

    try {
      const headRes = await axios.head(url, {
        timeout: 3800,
        maxRedirects: 2,
        validateStatus: status => status >= 200 && status < 400
      });

      const contentType = (headRes.headers['content-type'] || '').toLowerCase();
      const contentLength = parseInt(headRes.headers['content-length'], 10);

      // Si responde con HTML en lugar de video, es una página de error o bloqueo
      if (contentType.includes('text/html')) {
        return false;
      }

      // Los videos de advertencia de error/copyright pesan menos de 2 MB (ej: ~136 KB).
      // Un stream multimedia real de película o serie supera holgadamente los 5 MB.
      if (!isNaN(contentLength) && contentLength < 5 * 1024 * 1024) {
        console.warn(`[VJ STREAM Auto-Resolver] 🚫 Stream descartado: tamaño sospechoso (${contentLength} bytes, posible clip de advertencia de error).`);
        return false;
      }

      return true;
    } catch (e) {
      if (e.response && (e.response.status === 403 || e.response.status === 451 || e.response.status === 404)) {
        return false;
      }
      // Si el servidor CDN no admite HEAD (405 Method Not Allowed), probar con un GET de rango mínimo (1 KB)
      if (e.response && e.response.status === 405) {
        try {
          const rangeRes = await axios.get(url, {
            headers: { 'Range': 'bytes=0-1024' },
            timeout: 3500,
            validateStatus: status => status === 200 || status === 206
          });
          const ct = (rangeRes.headers['content-type'] || '').toLowerCase();
          return !ct.includes('text/html');
        } catch (_) {
          return false;
        }
      }
      // Si falla por timeout pero apunta a un CDN genuino de Real-Debrid (.cloud o .com) y no es video de error
      return (url.toLowerCase().includes('real-debrid') && !this.isErrorVideoUrl(url));
    }
  }

  /**
   * Resuelve el enlace directo al CDN de Real-Debrid siguiendo la redirección HTTP 302
   * y descarta enlaces que redirijan a videos de advertencia por copyright.
   * @private
   */
  async _resolveDirectCdnUrl(resolveUrl) {
    if (!resolveUrl) return null;
    let currentUrl = resolveUrl;
    try {
      for (let hop = 0; hop < 5; hop++) {
        let location = null;
        try {
          const response = await axios.get(currentUrl, {
            maxRedirects: 0,
            validateStatus: status => status >= 200 && status < 400,
            timeout: 4800
          });
          location = response.headers?.location;
        } catch (e) {
          if (e.response && e.response.headers && e.response.headers.location) {
            location = e.response.headers.location;
          } else {
            break;
          }
        }

        if (!location) {
          break;
        }

        if (this.isErrorVideoUrl(location)) {
          console.warn(`[VJ STREAM Auto-Resolver] 🚫 Redirección detectada a advertencia de error de debrid: ${location}`);
          return null;
        }

        currentUrl = location;
      }
      return currentUrl;
    } catch (_) {
      return currentUrl;
    }
  }

  /**
   * Búsqueda instantánea en catálogo con proveedores Debrid conectados.
   * Soporta Base 1 (TorBox) y Base 2 (Real-Debrid).
   * @param {string} imdbId
   * @param {string} mediaType
   * @param {number} season
   * @param {number} episode
   * @param {Object} mediaInfo
   * @param {string} provider - 'torbox' o 'realdebrid'
   * @private
   */
  async _searchInstantCachedStreams(imdbId, mediaType = 'movie', season = 1, episode = 1, mediaInfo = null, provider = 'realdebrid') {
    let apiKey = null;
    let providerParam = 'realdebrid';

    if (provider === 'torbox') {
      apiKey = torboxService.getApiKey();
      providerParam = 'torbox';
    } else {
      apiKey = realDebridService.getApiKey() || process.env.REALDEBRID_API_KEY;
      providerParam = 'realdebrid';
    }

    if (!apiKey || !imdbId) return { latino: [], castellano: [], original: [] };

    try {
      const target = mediaType === 'tv' ? `${imdbId}:${season}:${episode}` : imdbId;
      const endpoint = mediaType === 'tv' ? 'series' : 'movie';

      // Scraper Optimizado de Alto Rendimiento (Ultra-ligero para evitar picos de CPU en Render):
      const scraperEndpoints = [
        // 1. Proveedores dedicados de Español Latino (Cinecalidad) y Castellano (MejorTorrent, Wolfmax4k)
        `https://torrentio.strem.fun/providers=cinecalidad,mejortorrent,wolfmax4k|sort=qualitysize|qualityfilter=scr,cam|${providerParam}=${apiKey}/stream/${endpoint}/${target}.json`,
        // 2. Filtro nativo de Torrentio con pistas de audio en Español y Latino
        `https://torrentio.strem.fun/sort=qualitysize|qualityfilter=scr,cam|language=spanish,latino|${providerParam}=${apiKey}/stream/${endpoint}/${target}.json`
      ];

      const responses = await Promise.allSettled(
        scraperEndpoints.map(u => axios.get(u, { timeout: 3500 }).catch(() => null))
      );

      const streamMap = new Map();
      for (const r of responses) {
        if (r.status === 'fulfilled' && Array.isArray(r.value?.data?.streams)) {
          for (const s of r.value.data.streams) {
            const key = s.url || s.behaviorHints?.filename || s.title;
            if (key && !streamMap.has(key)) {
              streamMap.set(key, s);
            }
          }
        }
      }

      if (streamMap.size === 0) return { latino: [], castellano: [], original: [] };

      const scored = Array.from(streamMap.values())
        .map(s => this.scoreStream(s, mediaInfo))
        .filter(x => x.score > 0);

      const latino = scored
        .filter(x => x.isSpanishAudio && (x.audioLanguage.includes('Latino') || x.audioLanguage.includes('Dual')))
        .sort((a, b) => b.score - a.score);

      const castellano = scored
        .filter(x => x.isSpanishAudio && (x.audioLanguage.includes('Castellano') || x.audioLanguage.includes('Español')))
        .sort((a, b) => b.score - a.score);

      const original = scored
        .filter(x => !x.isSpanishAudio)
        .sort((a, b) => b.score - a.score);

      console.log(`[TOM TV Multi-Scraper] 🎯 [${provider.toUpperCase()}] Fuentes válidas para ${mediaInfo?.title || imdbId} (${imdbId}): ${latino.length} Latino, ${castellano.length} Castellano, ${original.length} Original`);
      return { latino, castellano, original };
    } catch (err) {
      console.warn(`[TOM TV Multi-Scraper] Error en búsqueda combinada (${provider}):`, err.message);
      return { latino: [], castellano: [], original: [] };
    }
  }

  /**
   * Evalúa y verifica la reproducibilidad de candidatos cacheados para un proveedor.
   * @private
   */
  async _evaluateCandidateStreams(instant, excludeUrls, providerName = 'Real-Debrid', allowOriginal = false) {
    const verifyCandidate = async (candidate) => {
      if (!candidate || !candidate.stream || !candidate.stream.url) return null;
      if (excludeUrls.includes(candidate.stream.url)) return null;

      const directCdnUrl = await this._resolveDirectCdnUrl(candidate.stream.url);
      if (!directCdnUrl || excludeUrls.includes(directCdnUrl)) return null;

      const playable = await this.isStreamPlayable(directCdnUrl);
      if (!playable) return null;

      return {
        streamUrl: directCdnUrl,
        qualityLabel: candidate.qualityLabel,
        audioLanguage: candidate.audioLanguage,
        isSpanishAudio: candidate.isSpanishAudio,
        audioChannels: candidate.audioChannels || 'Estéreo 2.0',
        filename: candidate.filename,
        provider: providerName
      };
    };

    const availableStreams = [];
    let primaryStream = null;

    // 1. Probar y resolver el mejor Latino (máximo top 2 para respuesta instantánea sin sobrecargar CPU)
    for (const cand of (instant.latino || []).slice(0, 2)) {
      const verified = await verifyCandidate(cand);
      if (verified) {
        if (!primaryStream) {
          primaryStream = verified;
          availableStreams.push({
            id: 'latino',
            label: `Español Latino (${verified.audioChannels || 'Estéreo 2.0'} 🇲🇽)`,
            language: 'Español Latino Estéreo',
            audioChannels: verified.audioChannels || 'Estéreo 2.0',
            streamUrl: verified.streamUrl,
            qualityLabel: verified.qualityLabel,
            filename: verified.filename,
            provider: providerName,
            isBackup: false
          });
          break; // Primer latino verificado es el óptimo
        }
      }
    }

    // 2. Probar y resolver el mejor Castellano (máximo top 2)
    if (!primaryStream) {
      for (const cand of (instant.castellano || []).slice(0, 2)) {
        const verified = await verifyCandidate(cand);
        if (verified) {
          primaryStream = verified;
          availableStreams.push({
            id: 'castellano',
            label: `Castellano (${verified.audioChannels || 'Estéreo 2.0'} 🇪🇸)`,
            language: 'Castellano Estéreo',
            audioChannels: verified.audioChannels || 'Estéreo 2.0',
            streamUrl: verified.streamUrl,
            qualityLabel: verified.qualityLabel,
            filename: verified.filename,
            provider: providerName,
            isBackup: false
          });
          break;
        }
      }
    }

    // 3. Probar y resolver versión en Audio Original con Subtítulos en Español ÚNICAMENTE si allowOriginal es true y no se halló doblaje
    if (allowOriginal && !primaryStream && (instant.original || []).length > 0) {
      for (const cand of instant.original.slice(0, 8)) {
        const verified = await verifyCandidate(cand);
        if (verified) {
          primaryStream = {
            ...verified,
            audioLanguage: 'Original (Subtitulado al Español)',
            isSpanishAudio: false,
            isSubtitled: true
          };
          availableStreams.push({
            id: 'original_sub',
            label: `Audio Original (${verified.qualityLabel || 'HD'} Subtítulos 🇲🇽)`,
            language: 'Original Subtitulado',
            audioChannels: verified.audioChannels || 'Estéreo 2.0',
            streamUrl: verified.streamUrl,
            qualityLabel: verified.qualityLabel,
            filename: verified.filename,
            provider: providerName,
            isBackup: false
          });
          break;
        }
      }
    }

    return { primaryStream, availableStreams };
  }

  /**
   * Obtiene subtítulos limpios y sincronizados en español (Latino y Castellano) para la película o episodio.
   * @param {string} imdbId
   * @param {string} mediaType
   * @param {number} season
   * @param {number} episode
   * @returns {Promise<Array<{id: string, lang: string, label: string, url: string, fileName: string}>>}
   */
  async fetchSubtitles(imdbId, mediaType = 'movie', season = 1, episode = 1) {
    if (!imdbId) return [];
    try {
      const url = mediaType === 'tv'
        ? `https://opensubtitles-v3.strem.io/subtitles/series/${imdbId}:${season}:${episode}.json`
        : `https://opensubtitles-v3.strem.io/subtitles/movie/${imdbId}.json`;
      const res = await axios.get(url, { timeout: 3500 });
      const rawSubs = res.data?.subtitles || [];
      const spanishSubs = rawSubs.filter(s => {
        const lang = (s.lang || '').toLowerCase();
        return lang === 'spa' || lang === 'es' || lang === 'spl';
      });

      return spanishSubs.slice(0, 6).map((s, idx) => ({
        id: s.id || `sub_${idx + 1}`,
        lang: s.lang || 'es',
        label: s.lang === 'spl' || (s.subtitleFileName || '').toLowerCase().includes('lat')
          ? 'Español Latino (🇲🇽)'
          : 'Español / Castellano (🇪🇸)',
        url: s.url,
        fileName: s.subtitleFileName || `Subtítulo ${idx + 1}`
      }));
    } catch (_) {
      return [];
    }
  }

  /**
   * Respaldo: Busca magnets en APIs públicas de alta fidelidad (YTS) para películas.
   * @private
   */
  async searchPublicTrackers(query, year) {
    if (!query) return [];
    try {
      const q = encodeURIComponent(query.trim());
      const res = await axios.get(`https://yts.mx/api/v2/list_movies.json?query_term=${q}&limit=6`, { timeout: 3800 });
      const movies = res.data?.data?.movies || [];
      const magnets = [];
      const trs = [
        'udp://open.demonii.com:1337/announce',
        'udp://tracker.openbittorrent.com:80',
        'udp://tracker.opentrackr.org:1337/announce',
        'udp://tracker.torrent.eu.org:451/announce'
      ].map(tr => `&tr=${encodeURIComponent(tr)}`).join('');

      for (const m of movies) {
        if (year && m.year && Math.abs(m.year - parseInt(year, 10)) > 1) continue;
        const candidateText = `${m.title} ${m.year || ''}`;
        const matchCheck = this.validateTitleMatch(candidateText, { title: query, originalTitle: query, year });
        if (!matchCheck.isMatch) continue;

        const torrents = m.torrents || [];
        for (const t of torrents) {
          if (t.hash) {
            magnets.push({
              magnet: `magnet:?xt=urn:btih:${t.hash}&dn=${encodeURIComponent(m.title_long || m.title)}${trs}`,
              name: `${m.title} (${m.year}) [${t.quality}] [YTS]`,
              isOriginal: true
            });
          }
        }
      }
      return magnets;
    } catch (_) {
      return [];
    }
  }

  /**
   * Resuelve automáticamente el mejor stream priorizando Español (Latino / Castellano) y alta velocidad.
   * Genera además una lista de fuentes alternativas organizadas por idioma (Latino, Castellano, Original, Servidor 2)
   * para el engranaje de configuración dentro del reproductor.
   * @param {Object} mediaInfo
   */
  async resolveBestStream(mediaInfo) {
    const { title, originalTitle, year, mediaType = 'movie', id, season = 1, episode = 1, bypassCache = false, excludeUrls = [] } = mediaInfo;
    const cacheKey = this._getCacheKey(mediaInfo);

    // 0. VERIFICAR CACHÉ EN MEMORIA (Tiempo de respuesta: ~1ms)
    if (!bypassCache) {
      const cached = this.cache.get(cacheKey);
      if (cached && (Date.now() - cached.timestamp < this.CACHE_TTL_MS)) {
        // Verificar que la URL en caché no esté en las excluidas ni sea un video de error
        const isExcluded = excludeUrls.length > 0 && excludeUrls.includes(cached.data?.streamUrl);
        const isErrorVideo = this.isErrorVideoUrl(cached.data?.streamUrl);

        // Si el enlace tiene más de 12 minutos en caché, verificar que aún no haya caducado en Real-Debrid
        let isStillAlive = true;
        if (!isExcluded && !isErrorVideo && (Date.now() - cached.timestamp > 12 * 60 * 1000)) {
          isStillAlive = await this.isStreamPlayable(cached.data?.streamUrl);
        }

        if (!isExcluded && !isErrorVideo && isStillAlive) {
          console.log(`[VJ STREAM Auto-Resolver] ⚡ Transmisión servida desde CACHÉ ULTRA-RÁPIDO para: "${title}"`);
          return cached.data;
        } else {
          console.log(`[VJ STREAM Auto-Resolver] 🔄 Entrada en caché descartada (expirada o no reproducible). Re-resolviendo...`);
          this.cache.delete(cacheKey);
        }
      }
    } else {
      this.cache.delete(cacheKey);
    }

    // Verificar si es una de las películas fijadas en modo tráiler exclusivo
    const forcedConf = tmdbService.getForcedTrailerConfig(mediaInfo);
    if (forcedConf) {
      console.log(`[VJ STREAM Auto-Resolver] 🎬 "${forcedConf.title}" está en modo tráiler oficial exclusivo hasta estreno.`);
      return {
        success: false,
        isTrailerOnly: true,
        trailerKey: forcedConf.trailerKey,
        trailer: forcedConf.trailer,
        message: `"${forcedConf.title}" está en modo tráiler oficial exclusivo hasta su estreno y disponibilidad oficial en español.`
      };
    }

    console.log(`[VJ STREAM Auto-Resolver] 🔍 Buscando transmisión automática en ESPAÑOL para: "${title}" (ID: ${id || 'N/A'}${mediaType === 'tv' ? ` S${season}E${episode}` : ''})`);

    // 1. Obtener IMDb ID a través de TMDB si no viene en el payload
    let imdbId = mediaInfo.imdbId;
    if (!imdbId && id) {
      try {
        const client = tmdbService.getAxiosClient();
        const extRes = await client.get(`/${mediaType === 'tv' ? 'tv' : 'movie'}/${id}/external_ids`);
        imdbId = extRes.data?.imdb_id;
      } catch (_) {}
    }

    // Si aún no tenemos imdbId (ej. id no vino en payload), buscar en TMDB por título y año
    if (!imdbId && title) {
      try {
        const searchRes = await tmdbService.searchMedia(title, { type: mediaType === 'tv' ? 'tv' : 'movie' });
        const results = searchRes?.results || [];
        const match = results.find(r => {
          if (!year) return true;
          const y = r.releaseDate?.slice(0, 4) || '';
          return y === String(year);
        }) || results[0];

        if (match?.id) {
          const client = tmdbService.getAxiosClient();
          const extRes = await client.get(`/${mediaType === 'tv' ? 'tv' : 'movie'}/${match.id}/external_ids`);
          imdbId = extRes.data?.imdb_id;
          if (!mediaInfo.id) mediaInfo.id = match.id;
        }
      } catch (_) {}
    }

    // 2. PASO 1: BÚSQUEDA EXCLUSIVA DE AUDIO EN ESPAÑOL (Latino y Castellano) EN CACHÉ DEBRID
    let bestSpanishStream = null;
    let allAvailableStreams = [];
    let bestProviderName = null;
    let fallbackOriginalStream = null; // Guardado temporalmente solo por si no existe versión en español
    let fallbackOriginalAvailable = [];
    let fallbackOriginalProvider = null;

    if (imdbId) {
      const debridProviders = [];
      if (torboxService.isAvailable()) {
        debridProviders.push({ id: 'torbox', name: 'TorBox (Base 1 - Multi-IP)' });
      }
      debridProviders.push({ id: 'realdebrid', name: 'Real-Debrid (Base 2 - Respaldo Caché)' });

      // Primero buscamos fuentes en Español en todos los proveedores configurados
      for (const prov of debridProviders) {
        console.log(`[TOM TV Auto-Resolver] 🔍 [${prov.name}] Buscando fuentes en ESPAÑOL para "${title}"...`);
        const instant = await this._searchInstantCachedStreams(imdbId, mediaType, season, episode, mediaInfo, prov.id);
        const totalSpanish = (instant.latino?.length || 0) + (instant.castellano?.length || 0);

        if (totalSpanish > 0) {
          console.log(`[TOM TV Auto-Resolver] 📋 Evaluando fuentes en Español [${prov.name}]: ${instant.latino.length} Latino, ${instant.castellano.length} Castellano...`);
          // allowOriginal = false: NO aceptar streams en inglés en esta etapa
          const { primaryStream, availableStreams } = await this._evaluateCandidateStreams(instant, excludeUrls, prov.name, false);

          if (primaryStream && primaryStream.isSpanishAudio) {
            console.log(`[TOM TV Auto-Resolver] 🎯 Fuente en Español verificada vía [${prov.name}]: [${primaryStream.audioLanguage}] "${primaryStream.filename}"`);
            // Si es Español Latino (la máxima prioridad para los clientes), ¡seleccionarlo de inmediato!
            if (primaryStream.audioLanguage.includes('Latino')) {
              bestSpanishStream = primaryStream;
              allAvailableStreams = availableStreams;
              bestProviderName = prov.name;
              break;
            } else if (!bestSpanishStream) {
              // Si es Castellano, guardarlo temporalmente y continuar buscando si el otro proveedor tiene Latino
              bestSpanishStream = primaryStream;
              allAvailableStreams = availableStreams;
              bestProviderName = prov.name;
            }
          }
        }

        // Si este proveedor tiene fuentes originales, guardar la mejor como último recurso por si el título no tiene doblaje
        if (!fallbackOriginalStream && (instant.original || []).length > 0) {
          const evalOrig = await this._evaluateCandidateStreams(instant, excludeUrls, prov.name, true);
          if (evalOrig.primaryStream) {
            fallbackOriginalStream = evalOrig.primaryStream;
            fallbackOriginalAvailable = evalOrig.availableStreams;
            fallbackOriginalProvider = prov.name;
          }
        }
      }
    }

    // Si ya encontramos Español Latino directamente en la caché instantánea, retornar de inmediato
    if (bestSpanishStream && bestSpanishStream.audioLanguage.includes('Latino')) {
      const subtitles = await this.fetchSubtitles(imdbId, mediaType, season, episode);
      const result = {
        success: true,
        streamUrl: bestSpanishStream.streamUrl,
        qualityLabel: bestSpanishStream.qualityLabel,
        audioLanguage: bestSpanishStream.audioLanguage,
        isSpanishAudio: true,
        filename: bestSpanishStream.filename,
        title: title,
        provider: bestProviderName,
        availableStreams: allAvailableStreams,
        subtitles: subtitles
      };
      this.cache.set(cacheKey, { timestamp: Date.now(), data: result });
      return result;
    }

    // 3. PASO 2: RESPALDO CON MAGNETS Y SCRAPERS NATIVOS (Especializado en Cinecalidad y fuentes en Español)
    console.log(`[VJ STREAM Auto-Resolver] 🔄 Consultando respaldo Cinecalidad y scrapers en español para "${title}"...`);
    let fallbackMagnets = [];

    if (imdbId) {
      try {
        const target = mediaType === 'tv' ? `${imdbId}:${season}:${episode}` : imdbId;
        const endpoint = mediaType === 'tv' ? 'series' : 'movie';

        // Consultar Torrentio con proveedores dedicados de español y también con trackers globales
        const scrapeUrls = [
          `https://torrentio.strem.fun/providers=cinecalidad,mejortorrent,wolfmax4k/stream/${endpoint}/${target}.json`,
          `https://torrentio.strem.fun/language=spanish,latino/stream/${endpoint}/${target}.json`,
          `https://torrentio.strem.fun/stream/${endpoint}/${target}.json`,
          `https://knightcrawler.elfhosted.com/stream/${endpoint}/${target}.json`
        ];

        const settled = await Promise.allSettled(
          scrapeUrls.map(u => axios.get(u, { timeout: 4500 }).catch(() => null))
        );

        for (const res of settled) {
          const streams = res.value?.data?.streams;
          if (Array.isArray(streams)) {
            for (const st of streams) {
              if (st.infoHash) {
                const filename = st.behaviorHints?.filename || st.title?.split('\n')[0] || 'VJ-STREAM';
                if (!realDebridService.isCamOrLowQuality(filename)) {
                  const matchCheck = this.validateTitleMatch(filename, mediaInfo);
                  if (matchCheck.isMatch) {
                    fallbackMagnets.push({
                      magnet: `magnet:?xt=urn:btih:${st.infoHash}&dn=${encodeURIComponent(filename)}&tr=udp://open.demonii.com:1337/announce`,
                      name: filename
                    });
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // Buscar en YTS / Trackers públicos si es película y aún no hay magnets
    if (fallbackMagnets.length === 0 && mediaType !== 'tv') {
      if (title && title !== originalTitle) {
        const span = await this.searchPublicTrackers(title, year);
        fallbackMagnets.push(...span);
      }
      if (originalTitle) {
        const orig = await this.searchPublicTrackers(originalTitle, year);
        fallbackMagnets.push(...orig);
      }
    }

    // Filtrar y ordenar magnets: 1° Cinecalidad / Latino, 2° Castellano
    const spanishMagnets = fallbackMagnets.filter(m => {
      const mName = (m.name || '').toLowerCase();
      return /cinecalidad|latino|dual[\s._-]*lat|latam|mexico|mejortorrent|wolfmax4k|castellano|español|\b(lat|cast|esp|spa)\b/i.test(mName);
    });

    const candidateMagnets = spanishMagnets.length > 0 ? spanishMagnets : fallbackMagnets;

    candidateMagnets.sort((a, b) => {
      const aName = (a.name || '').toLowerCase();
      const bName = (b.name || '').toLowerCase();
      const aLat = /cinecalidad|latino|dual[\s._-]*lat|latam|mexico|\blat\b/i.test(aName);
      const bLat = /cinecalidad|latino|dual[\s._-]*lat|latam|mexico|\blat\b/i.test(bName);
      if (aLat && !bLat) return -1;
      if (!aLat && bLat) return 1;

      const aEsp = /castellano|mejortorrent|wolfmax4k|español|\bcast\b/i.test(aName);
      const bEsp = /castellano|mejortorrent|wolfmax4k|español|\bcast\b/i.test(bName);
      if (aEsp && !bEsp) return -1;
      if (!aEsp && bEsp) return 1;

      return 0;
    });

    for (const candidate of candidateMagnets.slice(0, 2)) {
      try {
        let result = null;
        if (torboxService.isAvailable()) {
          try {
            result = await torboxService.resolveMagnetToStream(candidate.magnet, mediaInfo);
          } catch (_) {
            result = null;
          }
        }
        if (!result || !result.streamUrl) {
          result = await realDebridService.resolveMagnetToStream(candidate.magnet, {
            files: 'all',
            unrestrictAll: true
          });
        }

        const streamOptions = (result && Array.isArray(result.streams) && result.streams.length > 0)
          ? result.streams
          : (result && result.streamUrl ? [result] : []);

        if (streamOptions.length > 0) {
          for (const streamOption of streamOptions) {
            if (excludeUrls.includes(streamOption.streamUrl)) continue;

            const titleMatch = this.validateTitleMatch(streamOption.filename, mediaInfo);
            if (!titleMatch.isMatch) continue;

            const isClean = await this.isStreamPlayable(streamOption.streamUrl);
            if (!isClean) continue;

            const isLatino = /cinecalidad|latino|dual[\s._-]*lat|latam|mexico|\blat\b/i.test(streamOption.filename);
            const isCastellano = /mejortorrent|wolfmax4k|castellano|español|\bcast\b/i.test(streamOption.filename);
            const isSpanish = isLatino || isCastellano;

            // Si estábamos buscando mejorar a Latino y encontramos Latino, o si no teníamos ningún stream en español:
            if (isLatino || !bestSpanishStream) {
              const langLabel = isLatino
                ? 'Español Latino'
                : (isCastellano ? 'Castellano' : 'Audio Original (Subtitulado al Español)');

              console.log(`[VJ STREAM Auto-Resolver] ✅ Transmisión de respaldo verificada: [${langLabel}] "${streamOption.filename}"`);
              const subtitles = await this.fetchSubtitles(imdbId, mediaType, season, episode);
              const streamData = {
                success: true,
                streamUrl: streamOption.streamUrl,
                qualityLabel: streamOption.qualityLabel || '1080p Full HD',
                audioLanguage: langLabel,
                isSpanishAudio: isSpanish,
                filename: streamOption.filename,
                title: title,
                availableStreams: [
                  {
                    id: isLatino ? 'latino' : (isCastellano ? 'castellano' : 'original_sub'),
                    label: isLatino
                      ? 'Español Latino (Estéreo 2.0 🎧 🇲🇽)'
                      : (isCastellano ? 'Castellano (Estéreo 🇪🇸)' : 'Audio Original (Subtítulos en Español 🇲🇽)'),
                    language: langLabel,
                    audioChannels: 'Estéreo 2.0',
                    streamUrl: streamOption.streamUrl,
                    qualityLabel: streamOption.qualityLabel || '1080p',
                    filename: streamOption.filename,
                    isBackup: false
                  }
                ],
                subtitles: subtitles
              };

              this.cache.set(cacheKey, { timestamp: Date.now(), data: streamData });
              return streamData;
            }
          }
        }
      } catch (_) {}
    }

    // Si teníamos un stream en Castellano verificado en el Paso 1 y el Paso 2 no encontró Latino
    if (bestSpanishStream) {
      const subtitles = await this.fetchSubtitles(imdbId, mediaType, season, episode);
      const result = {
        success: true,
        streamUrl: bestSpanishStream.streamUrl,
        qualityLabel: bestSpanishStream.qualityLabel,
        audioLanguage: bestSpanishStream.audioLanguage,
        isSpanishAudio: true,
        filename: bestSpanishStream.filename,
        title: title,
        provider: bestProviderName,
        availableStreams: allAvailableStreams,
        subtitles: subtitles
      };
      this.cache.set(cacheKey, { timestamp: Date.now(), data: result });
      return result;
    }

    // Si NO existe doblaje en español en ningún servidor, pero se tiene versión original subtitulada:
    if (fallbackOriginalStream) {
      console.log(`[VJ STREAM Auto-Resolver] 🌐 Sin doblaje oficial disponible. Activando Audio Original con subtítulos en español para "${title}".`);
      const subtitles = await this.fetchSubtitles(imdbId, mediaType, season, episode);
      const result = {
        success: true,
        streamUrl: fallbackOriginalStream.streamUrl,
        qualityLabel: fallbackOriginalStream.qualityLabel,
        audioLanguage: 'Audio Original (Subtitulado al Español)',
        isSpanishAudio: false,
        isSubtitled: true,
        filename: fallbackOriginalStream.filename,
        title: title,
        provider: fallbackOriginalProvider,
        availableStreams: fallbackOriginalAvailable,
        subtitles: subtitles
      };
      this.cache.set(cacheKey, { timestamp: Date.now(), data: result });
      return result;
    }

    // 4. PASO 3: SI NO HAY VERSIÓN EN ESPAÑOL DISPONIBLE
    console.log(`[VJ STREAM Auto-Resolver] 🚫 Sin versión en español verificada para "${title}".`);
    const isRecentCinema = year && (new Date().getFullYear() - parseInt(year, 10) <= 0);
    let trailerKey = null;
    let trailer = null;
    const mediaId = id || mediaInfo.id;
    if (mediaId) {
      try {
        const client = tmdbService.getAxiosClient();
        const vidRes = await client.get(`/${mediaType === 'tv' ? 'tv' : 'movie'}/${mediaId}/videos`, {
          params: { language: 'es-ES', include_video_language: 'es,es-ES,es-MX,en,null' },
          timeout: 3000
        });
        const extracted = tmdbService._extractTrailer(vidRes.data);
        trailerKey = extracted.trailerKey;
        trailer = extracted.trailer;
      } catch (_) {}
    }

    return {
      success: false,
      isCinemaOnly: Boolean(isRecentCinema),
      hasNoSpanishAudio: true,
      trailerKey,
      trailer,
      message: isRecentCinema
        ? `"${title}" se encuentra actualmente en salas de cine o sin lanzamiento digital oficial en español. Puedes disfrutar de su tráiler oficial y recibir un aviso automático al estrenarse.`
        : `"${title}" está en proceso de digitalización para servidores en español. Puedes ver su tráiler oficial o activar el recordatorio.`
    };
  }

  /**
   * Comprueba de manera rápida y sin consumo innecesario de recursos
   * si un título ya cuenta con transmisiones activas con audio en Español (Latino o Castellano).
   * Permite la integración automática en el catálogo en cuanto aparezca la primera fuente en español.
   * @param {Object} mediaInfo 
   */
  async checkSpanishAvailability(mediaInfo) {
    const { title, originalTitle, year, mediaType = 'movie', id, season = 1, episode = 1 } = mediaInfo;

    // Si la película está configurada exclusivamente como tráiler hasta estreno oficial
    const forcedConf = tmdbService.getForcedTrailerConfig(mediaInfo);
    if (forcedConf) {
      return {
        hasSpanishAudio: false,
        isAvailable: false,
        isTrailerOnly: true,
        trailerKey: forcedConf.trailerKey,
        message: `"${forcedConf.title}" está en modo tráiler oficial hasta su estreno y disponibilidad oficial en español.`
      };
    }

    const cacheKey = this._getCacheKey(mediaInfo);

    // 1. Revisar caché
    const cached = this.cache.get(cacheKey);
    if (cached && (Date.now() - cached.timestamp < this.CACHE_TTL_MS)) {
      if (cached.data?.isSpanishAudio && cached.data?.streamUrl) {
        return {
          hasSpanishAudio: true,
          isAvailable: true,
          audioLanguage: cached.data.audioLanguage || 'Español'
        };
      }
    }

    // 2. Obtener imdbId
    let imdbId = mediaInfo.imdbId;
    if (!imdbId && id) {
      try {
        const client = tmdbService.getAxiosClient();
        const extRes = await client.get(`/${mediaType === 'tv' ? 'tv' : 'movie'}/${id}/external_ids`);
        imdbId = extRes.data?.imdb_id;
      } catch (_) {}
    }

    if (!imdbId) {
      return {
        hasSpanishAudio: false,
        isAvailable: false,
        message: 'Aún no disponible en español.'
      };
    }

    // 3. Consulta rápida en proveedores (TorBox Base 1, luego Real-Debrid Base 2)
    let instant = { latino: [], castellano: [] };
    if (torboxService.isAvailable()) {
      instant = await this._searchInstantCachedStreams(imdbId, mediaType, season, episode, mediaInfo, 'torbox');
    }
    if ((!instant.latino || instant.latino.length === 0) && (!instant.castellano || instant.castellano.length === 0)) {
      instant = await this._searchInstantCachedStreams(imdbId, mediaType, season, episode, mediaInfo, 'realdebrid');
    }
    const hasLatino = instant.latino && instant.latino.length > 0;
    const hasCastellano = instant.castellano && instant.castellano.length > 0;

    if (hasLatino || hasCastellano) {
      const topAudio = hasLatino ? 'Español Latino' : 'Castellano';
      return {
        hasSpanishAudio: true,
        isAvailable: true,
        audioLanguage: topAudio,
        counts: {
          latino: instant.latino.length,
          castellano: instant.castellano.length
        }
      };
    }

    return {
      hasSpanishAudio: false,
      isAvailable: false,
      message: 'Esta película aún está en idioma original (inglés / cines). Se integrará al catálogo automáticamente cuando esté en español.'
    };
  }
}

module.exports = new StreamResolverService();
