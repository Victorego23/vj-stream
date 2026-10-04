/// Modelo de datos para películas y series.
/// Diseñado para alinearse con las respuestas de la API de Node.js (TMDB Service).
class MediaItem {
  final dynamic id;
  final String title;
  final String originalTitle;
  final String synopsis;
  final String? releaseDate;
  final double rating;
  final int voteCount;
  final String mediaType; // 'movie' o 'tv'
  final String? posterThumbnail;
  final String? posterMedium;
  final String? posterOriginal;
  final String? backdropMedium;
  final String? backdropLarge;
  final String? backdropOriginal;
  final int? runtime;
  final List<String> genres;
  final String? trailerUrl;
  final String? trailerKey;
  final bool isTrailerOnly;
  final bool hasSpanishAudio;
  final String? statusBadge;

  MediaItem({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.synopsis = '',
    this.releaseDate,
    this.rating = 0.0,
    this.voteCount = 0,
    this.mediaType = 'movie',
    this.posterThumbnail,
    this.posterMedium,
    this.posterOriginal,
    this.backdropMedium,
    this.backdropLarge,
    this.backdropOriginal,
    this.runtime,
    this.genres = const [],
    this.trailerUrl,
    this.trailerKey,
    this.isTrailerOnly = false,
    this.hasSpanishAudio = true,
    this.statusBadge,
  });

  /// Factory constructor para deserializar desde el JSON que retorna el backend en Node.js
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final posters = json['posters'] as Map<String, dynamic>?;
    final backdrops = json['backdrops'] as Map<String, dynamic>?;

    List<String> parsedGenres = [];
    if (json['genres'] is List) {
      parsedGenres = (json['genres'] as List).map((g) {
        if (g is Map) return (g['name'] ?? '').toString();
        return g.toString();
      }).where((name) => name.isNotEmpty).toList();
    }

    final titleLower = (json['title'] ?? json['name'] ?? '').toString().toLowerCase();
    final origLower = (json['originalTitle'] ?? json['original_title'] ?? '').toString().toLowerCase();
    final isForcedTrailer = titleLower.contains('coyote vs') ||
        titleLower.contains('coyote contra acme') ||
        titleLower.contains('spider-man: brand new day') ||
        titleLower.contains('spider man brand new day') ||
        titleLower.contains('spiderman brand new day') ||
        titleLower.contains('la odisea') ||
        titleLower.contains('the odyssey') ||
        json['id'] == 1204680 ||
        json['id'] == 1368337 ||
        json['id'] == 969681;

    final isTrailer = json['isTrailerOnly'] == true || isForcedTrailer;
    final hasSpanish = isForcedTrailer
        ? false
        : (json['hasSpanishAudio'] is bool
            ? json['hasSpanishAudio'] as bool
            : !isTrailer);

    String? key = json['trailerKey']?.toString();
    if (key == null || key.isEmpty) {
      if (json['id'] == 1204680 || titleLower.contains('coyote vs')) key = 'WQRoa6l4bwI';
      if (json['id'] == 1368337 || titleLower.contains('odisea') || origLower.contains('odyssey')) key = '8un_UztYsw0';
      if (json['id'] == 969681 || titleLower.contains('brand new day')) key = 'pqLSLoDkZWE';
    }

    final badge = isForcedTrailer
        ? 'Solo Tráiler - Próximamente en Español'
        : json['statusBadge']?.toString();

    return MediaItem(
      id: json['id'],
      title: json['title'] ?? json['name'] ?? 'Sin título',
      originalTitle: json['originalTitle'] ?? json['original_title'] ?? '',
      synopsis: json['synopsis'] ?? json['overview'] ?? 'Sin sinopsis disponible.',
      releaseDate: json['releaseDate'] ?? json['release_date'] ?? json['first_air_date'],
      rating: ((json['rating'] ?? json['vote_average'] ?? 0.0) as num).toDouble(),
      voteCount: (json['voteCount'] ?? json['vote_count'] ?? 0) as int,
      mediaType: json['mediaType'] ?? json['media_type'] ?? 'movie',
      posterThumbnail: posters?['thumbnail'],
      posterMedium: posters?['medium'],
      posterOriginal: posters?['original'],
      backdropMedium: backdrops?['medium'],
      backdropLarge: backdrops?['large'],
      backdropOriginal: backdrops?['original'],
      runtime: json['runtime'] as int?,
      genres: parsedGenres,
      trailerUrl: json['trailer'] ?? json['trailerUrl'],
      trailerKey: key,
      isTrailerOnly: isTrailer,
      hasSpanishAudio: hasSpanish,
      statusBadge: badge,
    );
  }

  /// Retorna el año extraído de la fecha de lanzamiento (ej. "2024")
  String get releaseYear {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    return releaseDate!.split('-').first;
  }

  /// Formatea la puntuación con un decimal (ej. "8.5")
  String get formattedRating {
    return rating.toStringAsFixed(1);
  }

  /// Retorna la mejor URL de póster disponible
  String get bestPosterUrl {
    return posterMedium ?? posterOriginal ?? posterThumbnail ?? '';
  }

  /// Retorna si el contenido es una serie de televisión
  bool get isSeries => mediaType == 'tv';

  /// Retorna la mejor URL de fondo disponible para banners
  String get bestBackdropUrl {
    return backdropLarge ?? backdropOriginal ?? backdropMedium ?? bestPosterUrl;
  }

  /// Retorna una copia con campos modificados (ej. cuando pasa de solo tráiler a disponible en español)
  MediaItem copyWith({
    dynamic id,
    String? title,
    String? originalTitle,
    String? synopsis,
    String? releaseDate,
    double? rating,
    int? voteCount,
    String? mediaType,
    String? posterThumbnail,
    String? posterMedium,
    String? posterOriginal,
    String? backdropMedium,
    String? backdropLarge,
    String? backdropOriginal,
    int? runtime,
    List<String>? genres,
    String? trailerUrl,
    String? trailerKey,
    bool? isTrailerOnly,
    bool? hasSpanishAudio,
    String? statusBadge,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      synopsis: synopsis ?? this.synopsis,
      releaseDate: releaseDate ?? this.releaseDate,
      rating: rating ?? this.rating,
      voteCount: voteCount ?? this.voteCount,
      mediaType: mediaType ?? this.mediaType,
      posterThumbnail: posterThumbnail ?? this.posterThumbnail,
      posterMedium: posterMedium ?? this.posterMedium,
      posterOriginal: posterOriginal ?? this.posterOriginal,
      backdropMedium: backdropMedium ?? this.backdropMedium,
      backdropLarge: backdropLarge ?? this.backdropLarge,
      backdropOriginal: backdropOriginal ?? this.backdropOriginal,
      runtime: runtime ?? this.runtime,
      genres: genres ?? this.genres,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      trailerKey: trailerKey ?? this.trailerKey,
      isTrailerOnly: isTrailerOnly ?? this.isTrailerOnly,
      hasSpanishAudio: hasSpanishAudio ?? this.hasSpanishAudio,
      statusBadge: statusBadge ?? this.statusBadge,
    );
  }
}
