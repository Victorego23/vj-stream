import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Servicio especializado para extraer y reproducir streams directos de tráilers oficiales
/// de YouTube sin necesidad de WebView ni aplicaciones externas, compatible 100% con Smart TV y móvil.
class TrailerService {
  static final TrailerService _instance = TrailerService._internal();
  factory TrailerService() => _instance;
  TrailerService._internal();

  final Map<String, String> _resolvedCache = {};

  /// Extrae el ID de un video de YouTube a partir de una URL o de una clave directa
  static String? extractVideoId(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final clean = input.trim();

    // Si ya es un ID simple de 11 caracteres (ej. "d6oszs7f5aI")
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) {
      return clean;
    }

    try {
      final videoId = VideoId(clean);
      return videoId.value;
    } catch (_) {
      // Búsqueda regex manual de respaldo
      final regExp = RegExp(
        r'(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([\w-]{11})',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(clean);
      return match?.group(1);
    }
  }

  /// Resuelve la URL directa del stream MP4 con audio y video combinados para reproducción nativa
  Future<String?> resolveDirectStreamUrl(String? trailerUrlOrKey) async {
    final videoId = extractVideoId(trailerUrlOrKey);
    if (videoId == null) return null;

    // Verificar si ya está en caché local
    if (_resolvedCache.containsKey(videoId)) {
      return _resolvedCache[videoId];
    }

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      
      // Buscar stream combinado (audio + video muxed) con mayor tasa de bits (720p/1080p/360p)
      final muxedStreams = manifest.muxed.sortByVideoQuality();
      if (muxedStreams.isNotEmpty) {
        final bestStream = muxedStreams.first;
        final directUrl = bestStream.url.toString();
        _resolvedCache[videoId] = directUrl;
        return directUrl;
      }

      // Si no hay muxed ordenado, buscar cualquier mp4
      final mp4Streams = manifest.muxed.where((s) => s.container.name.toLowerCase() == 'mp4');
      if (mp4Streams.isNotEmpty) {
        final directUrl = mp4Streams.first.url.toString();
        _resolvedCache[videoId] = directUrl;
        return directUrl;
      }

      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[TrailerService] Error al resolver trailer $videoId: $e');
      return null;
    } finally {
      yt.close();
    }
  }
}
