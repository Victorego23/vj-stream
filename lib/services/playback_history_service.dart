import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// Modelo de un elemento en reproducción guardado
class WatchHistoryItem {
  final dynamic id;
  final String title;
  final String posterUrl;
  final String backdropUrl;
  final String mediaType;
  final int positionSeconds;
  final int durationSeconds;
  final int? season;
  final int? episode;
  final DateTime lastWatched;

  WatchHistoryItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.backdropUrl,
    required this.mediaType,
    required this.positionSeconds,
    required this.durationSeconds,
    this.season,
    this.episode,
    required this.lastWatched,
  });

  double get progressPercentage {
    if (durationSeconds <= 0) return 0.0;
    final p = positionSeconds / durationSeconds;
    return p.clamp(0.0, 1.0);
  }

  String get formattedProgress {
    final rem = (durationSeconds - positionSeconds).clamp(0, durationSeconds);
    final minutes = (rem / 60).round();
    if (minutes <= 1) return 'Faltan menos de 1 min';
    return 'Quedan $minutes min';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'mediaType': mediaType,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
    'season': season,
    'episode': episode,
    'lastWatched': lastWatched.toIso8601String(),
  };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) => WatchHistoryItem(
    id: json['id'],
    title: json['title'] ?? 'Sin título',
    posterUrl: json['posterUrl'] ?? '',
    backdropUrl: json['backdropUrl'] ?? '',
    mediaType: json['mediaType'] ?? 'movie',
    positionSeconds: json['positionSeconds'] ?? 0,
    durationSeconds: json['durationSeconds'] ?? 0,
    season: json['season'],
    episode: json['episode'],
    lastWatched: DateTime.tryParse(json['lastWatched'] ?? '') ?? DateTime.now(),
  );

  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: title,
    mediaType: mediaType,
    posterMedium: posterUrl,
    backdropLarge: backdropUrl,
  );
}

/// Gestor de persistencia de "Continuar Viendo" y "Mi Lista" (Favoritos)
class PlaybackHistoryService {
  static const String _historyKey = 'vj_stream_watch_history';
  static const String _favoritesKey = 'vj_stream_favorites';

  // -------------------------------------------------------------
  // CONTINUAR VIENDO (HISTORIAL DE REPRODUCCIÓN)
  // -------------------------------------------------------------

  static Future<List<WatchHistoryItem>> getWatchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return [];

      final List decoded = json.decode(raw);
      final items = decoded.map((e) => WatchHistoryItem.fromJson(e)).toList();
      items.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveProgress({
    required dynamic id,
    required String title,
    required String posterUrl,
    required String backdropUrl,
    required String mediaType,
    required int positionSeconds,
    required int durationSeconds,
    int? season,
    int? episode,
  }) async {
    try {
      if (durationSeconds <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getWatchHistory();

      // Si vio más del 95% o faltan menos de 90s, considerarlo terminado y quitarlo
      if (positionSeconds >= durationSeconds - 90 || (positionSeconds / durationSeconds) >= 0.95) {
        currentList.removeWhere((item) => item.id.toString() == id.toString());
      } else if (positionSeconds > 15) {
        // Guardar si vio más de 15 segundos
        currentList.removeWhere((item) => item.id.toString() == id.toString());
        currentList.insert(
          0,
          WatchHistoryItem(
            id: id,
            title: title,
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            mediaType: mediaType,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            season: season,
            episode: episode,
            lastWatched: DateTime.now(),
          ),
        );
      }

      // Limitar a máximo 20 elementos recientes
      final trimmed = currentList.take(20).toList();
      await prefs.setString(_historyKey, json.encode(trimmed.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> removeFromHistory(dynamic id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getWatchHistory();
      currentList.removeWhere((item) => item.id.toString() == id.toString());
      await prefs.setString(_historyKey, json.encode(currentList.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // MI LISTA (FAVORITOS)
  // -------------------------------------------------------------

  static Future<List<MediaItem>> getFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesKey);
      if (raw == null || raw.isEmpty) return [];

      final List decoded = json.decode(raw);
      return decoded.map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isFavorite(dynamic id) async {
    try {
      final list = await getFavorites();
      return list.any((item) => item.id.toString() == id.toString());
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleFavorite(MediaItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getFavorites();
      final exists = list.any((i) => i.id.toString() == item.id.toString());

      if (exists) {
        list.removeWhere((i) => i.id.toString() == item.id.toString());
      } else {
        list.insert(0, item);
      }

      final encoded = json.encode(list.map((i) => {
        'id': i.id,
        'title': i.title,
        'originalTitle': i.originalTitle,
        'synopsis': i.synopsis,
        'releaseDate': i.releaseDate,
        'rating': i.rating,
        'voteCount': i.voteCount,
        'mediaType': i.mediaType,
        'posters': {'medium': i.posterMedium, 'original': i.posterOriginal, 'thumbnail': i.posterThumbnail},
        'backdrops': {'large': i.backdropLarge, 'original': i.backdropOriginal, 'medium': i.backdropMedium},
        'genres': i.genres,
        'trailer': i.trailerUrl,
      }).toList());

      await prefs.setString(_favoritesKey, encoded);
      return !exists;
    } catch (_) {
      return false;
    }
  }
}
