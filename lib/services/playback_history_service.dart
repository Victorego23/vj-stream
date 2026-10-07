import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'api_service.dart';
import 'auth_service.dart';

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

/// Gestor de persistencia de "Continuar Viendo" y "Mi Lista" (Favoritos) con sincronización en la nube
class PlaybackHistoryService {
  static const String _historyKey = 'vj_stream_watch_history';
  static const String _favoritesKey = 'vj_stream_favorites';
  static const String _deletedHistoryIdsKey = 'vj_stream_deleted_history_ids';
  static const String _historyClearedAllKey = 'vj_stream_history_cleared_all';

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

      // Si el usuario vuelve a reproducir este título, quitarlo del conjunto de eliminados
      final deletedList = prefs.getStringList(_deletedHistoryIdsKey) ?? <String>[];
      final idStr = id.toString();
      final titleNorm = title.trim().toLowerCase();
      if (deletedList.contains(idStr) || deletedList.contains(titleNorm)) {
        deletedList.removeWhere((d) => d == idStr || d == titleNorm);
        await prefs.setStringList(_deletedHistoryIdsKey, deletedList);
      }
      await prefs.remove(_historyClearedAllKey);

      final currentList = await getWatchHistory();

      // Si vio más del 95% o faltan menos de 90s, considerarlo terminado y quitarlo
      if (positionSeconds >= durationSeconds - 90 || (positionSeconds / durationSeconds) >= 0.95) {
        currentList.removeWhere((item) =>
            item.id.toString() == idStr ||
            (title.isNotEmpty && item.title.trim().toLowerCase() == titleNorm));
      } else if (positionSeconds > 15) {
        // Guardar si vio más de 15 segundos
        currentList.removeWhere((item) =>
            item.id.toString() == idStr ||
            (title.isNotEmpty && item.title.trim().toLowerCase() == titleNorm));
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

      // Sincronizar en segundo plano con la nube
      _syncProgressToCloud({
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'mediaType': mediaType,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'season': season,
        'episode': episode,
      });
    } catch (_) {}
  }

  static void _syncProgressToCloud(Map<String, dynamic> item) async {
    try {
      final code = await AuthService.getSavedClientCode();
      if (code != null && code.isNotEmpty) {
        ApiService().syncPlaybackProgress(code, item);
      }
    } catch (_) {}
  }

  static Future<void> removeFromHistory(dynamic id, {String? title}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idStr = id.toString();
      final titleNorm = (title ?? '').trim().toLowerCase();

      // 1. Guardar en registro de eliminados (tombstone) para evitar resurrección durante sync
      final deletedList = prefs.getStringList(_deletedHistoryIdsKey) ?? <String>[];
      if (!deletedList.contains(idStr)) {
        deletedList.add(idStr);
      }
      if (titleNorm.isNotEmpty && !deletedList.contains(titleNorm)) {
        deletedList.add(titleNorm);
      }
      await prefs.setStringList(_deletedHistoryIdsKey, deletedList);

      // 2. Eliminar inmediatamente de la caché local persistente
      final currentList = await getWatchHistory();
      currentList.removeWhere((item) =>
          item.id.toString() == idStr ||
          (titleNorm.isNotEmpty && item.title.trim().toLowerCase() == titleNorm));
      await prefs.setString(_historyKey, json.encode(currentList.map((e) => e.toJson()).toList()));

      // 3. Sincronizar eliminación con la nube en segundo plano
      final code = await AuthService.getSavedClientCode();
      if (code != null && code.isNotEmpty) {
        ApiService().deletePlaybackProgress(code, id, title: title);
      }
    } catch (_) {}
  }

  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      await prefs.remove(_deletedHistoryIdsKey);
      await prefs.setBool(_historyClearedAllKey, true);

      // Sincronizar limpieza masiva con la nube
      final code = await AuthService.getSavedClientCode();
      if (code != null && code.isNotEmpty) {
        ApiService().clearPlaybackProgress(code);
      }
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

      // Sincronizar en segundo plano con la nube
      _syncFavoriteToCloud(item);

      return !exists;
    } catch (_) {
      return false;
    }
  }

  static void _syncFavoriteToCloud(MediaItem item) async {
    try {
      final code = await AuthService.getSavedClientCode();
      if (code != null && code.isNotEmpty) {
        ApiService().syncFavorite(code, {
          'id': item.id,
          'title': item.title,
          'posterUrl': item.posterMedium,
          'backdropUrl': item.backdropLarge,
          'mediaType': item.mediaType,
        });
      }
    } catch (_) {}
  }

  /// Sincroniza y fusiona los datos locales con la nube
  static Future<void> syncWithCloud() async {
    try {
      final code = await AuthService.getSavedClientCode();
      if (code == null || code.isEmpty) return;
      final cloudData = await ApiService().fetchUserSyncData(code);
      if (cloudData == null) return;

      final prefs = await SharedPreferences.getInstance();

      // Sincronizar Historial
      if (cloudData['history'] is List) {
        // Si el usuario ejecutó un borrado masivo y aún no tiene nuevos items locales, no restaurar historial de nube
        final wasClearedAll = prefs.getBool(_historyClearedAllKey) ?? false;
        final localHistory = await getWatchHistory();

        if (wasClearedAll && localHistory.isEmpty) {
          // Mantener limpio localmente
        } else {
          final cloudHistory = (cloudData['history'] as List)
              .map((e) => WatchHistoryItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();

          final deletedList = prefs.getStringList(_deletedHistoryIdsKey) ?? <String>[];

          final historyMap = <String, WatchHistoryItem>{};
          for (final h in localHistory) {
            historyMap[h.id.toString()] = h;
          }

          for (final h in cloudHistory) {
            final hId = h.id.toString();
            final hTitle = h.title.trim().toLowerCase();

            // Nunca resucitar un elemento que el usuario eliminó explícitamente
            if (deletedList.contains(hId) || (hTitle.isNotEmpty && deletedList.contains(hTitle))) {
              continue;
            }

            final existing = historyMap[hId];
            if (existing == null || h.lastWatched.isAfter(existing.lastWatched)) {
              historyMap[hId] = h;
            }
          }

          final merged = historyMap.values.toList()
            ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
          await prefs.setString(_historyKey, json.encode(merged.take(20).map((e) => e.toJson()).toList()));
        }
      }

      // Sincronizar Favoritos
      if (cloudData['favorites'] is List) {
        final cloudFavorites = (cloudData['favorites'] as List)
            .map((e) => MediaItem(
                  id: e['id'],
                  title: e['title'] ?? 'Sin título',
                  mediaType: e['mediaType'] ?? 'movie',
                  posterMedium: e['posterUrl'] ?? '',
                  backdropLarge: e['backdropUrl'] ?? '',
                ))
            .toList();
        final localFavorites = await getFavorites();
        final favMap = <String, MediaItem>{};
        for (final f in localFavorites) {
          favMap[f.id.toString()] = f;
        }
        for (final f in cloudFavorites) {
          if (!favMap.containsKey(f.id.toString())) {
            favMap[f.id.toString()] = f;
          }
        }
        final mergedFavs = favMap.values.toList();
        await prefs.setString(_favoritesKey, json.encode(mergedFavs.map((i) => {
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
        }).toList()));
      }
    } catch (_) {}
  }
}
