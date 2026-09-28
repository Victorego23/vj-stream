import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'api_service.dart';

/// Servicio para gestionar la lista de seguimiento de estrenos y notificaciones:
/// "Avisarme cuando esté en español" con detección automática de disponibilidad.
class ComingSoonService {
  static const String _storageKey = 'vj_stream_coming_soon_reminders';

  /// Obtiene la lista de películas guardadas en espera de audio en español
  static Future<List<MediaItem>> getReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_storageKey) ?? [];
      return jsonList
          .map((str) => MediaItem.fromJson(json.decode(str) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Verifica si una película está en la lista de recordatorios
  static Future<bool> hasReminder(dynamic id) async {
    if (id == null) return false;
    final items = await getReminders();
    return items.any((i) => i.id.toString() == id.toString());
  }

  /// Agrega o elimina una película de la lista de espera
  static Future<bool> toggleReminder(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getReminders();
    final exists = items.any((i) => i.id.toString() == item.id.toString());

    if (exists) {
      items.removeWhere((i) => i.id.toString() == item.id.toString());
    } else {
      items.add(item);
    }

    final rawList = items.map((i) => json.encode({
      'id': i.id,
      'title': i.title,
      'originalTitle': i.originalTitle,
      'overview': i.synopsis,
      'release_date': i.releaseDate,
      'vote_average': i.rating,
      'media_type': i.mediaType,
      'trailer': i.trailerUrl,
      'trailerKey': i.trailerKey,
      'isTrailerOnly': true,
      'hasSpanishAudio': false,
      'posters': {
        'medium': i.posterMedium,
        'original': i.posterOriginal,
        'thumbnail': i.posterThumbnail,
      },
      'backdrops': {
        'large': i.backdropLarge,
        'original': i.backdropOriginal,
        'medium': i.backdropMedium,
      }
    })).toList();

    await prefs.setStringList(_storageKey, rawList);
    return !exists;
  }

  /// Comprueba si alguna de las películas en espera ya tiene versión en español disponible
  static Future<List<MediaItem>> checkNewReleasesInSpanish(ApiService apiService) async {
    final reminders = await getReminders();
    if (reminders.isEmpty) return [];

    final List<MediaItem> newlyAvailable = [];
    final List<MediaItem> remaining = [];

    for (final item in reminders) {
      try {
        final status = await apiService.checkSpanishAvailability(item);
        if (status?['hasSpanishAudio'] == true || status?['isAvailable'] == true) {
          newlyAvailable.add(item.copyWith(
            isTrailerOnly: false,
            hasSpanishAudio: true,
            statusBadge: '¡Ya disponible en Español!',
          ));
        } else {
          remaining.add(item);
        }
      } catch (_) {
        remaining.add(item);
      }
    }

    // Si hubo películas que ya salieron en español, actualizar la lista persistente
    if (newlyAvailable.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final rawList = remaining.map((i) => json.encode({
        'id': i.id,
        'title': i.title,
        'originalTitle': i.originalTitle,
        'overview': i.synopsis,
        'release_date': i.releaseDate,
        'vote_average': i.rating,
        'media_type': i.mediaType,
        'trailer': i.trailerUrl,
        'trailerKey': i.trailerKey,
        'isTrailerOnly': true,
        'hasSpanishAudio': false,
        'posters': {'medium': i.posterMedium},
        'backdrops': {'large': i.backdropLarge}
      })).toList();
      await prefs.setStringList(_storageKey, rawList);
    }

    return newlyAvailable;
  }
}
