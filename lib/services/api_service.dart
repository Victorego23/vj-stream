import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import '../models/stream_link.dart';

/// Servicio HTTP para comunicar la app Flutter con el backend de Node.js / Express.
class ApiService {
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _prefKey = 'vj_stream_backend_url';

  /// URL oficial fija del servidor VJ STREAM en la nube (activo 24/7 sin IPs)
  static const String defaultCloudUrl = 'https://vj-stream-m9sa.onrender.com/api/streaming';

  /// URL base por defecto del backend.
  String baseUrl = defaultCloudUrl;

  /// Normaliza cualquier formato de URL ingresado por el usuario o descubierto
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return defaultCloudUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/api/streaming')) {
      if (url.endsWith('/api')) {
        url = '$url/streaming';
      } else {
        url = '$url/api/streaming';
      }
    }
    return url;
  }

  /// Obtiene el origen (protocolo + host + puerto) del backend para descargas y endpoints raíz
  String get serverOrigin {
    try {
      final uri = Uri.parse(baseUrl);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      }
    } catch (_) {}
    return baseUrl.replaceAll('/api/streaming', '');
  }

  Future<void> setBaseUrl(String newUrl) async {
    final clean = normalizeBaseUrl(newUrl);
    baseUrl = clean;
    await saveBaseUrl(clean);
  }

  /// Guarda en almacenamiento persistente la IP exitosa
  Future<void> saveBaseUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, url);
    } catch (_) {}
  }

  /// Inicializa la URL del backend conectando directo a la nube 24/7 o descubriendo en LAN
  Future<bool> initBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && saved.isNotEmpty) {
        final cleanSaved = normalizeBaseUrl(saved);
        final ok = await checkHealth(cleanSaved);
        if (ok) {
          baseUrl = cleanSaved;
          return true;
        }
      }
    } catch (_) {}

    // 1. Probar conexión inmediata con el servidor oficial en la nube 24/7
    if (await checkHealth(defaultCloudUrl)) {
      baseUrl = defaultCloudUrl;
      await saveBaseUrl(defaultCloudUrl);
      return true;
    }

    // 2. Si no hay conexión a internet o está en red local privada, sondeo en LAN
    return await discoverBackend();
  }

  /// Verifica si una URL responde con el protocolo VJ STREAM
  Future<bool> checkHealth(String url) async {
    try {
      final cleanUrl = normalizeBaseUrl(url);
      final uri = Uri.parse('$cleanUrl/version');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 3000));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['app'] == 'VJ STREAM' || body['success'] == true) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Descubrimiento instantáneo por baliza UDP en LAN (0.05 segundos)
  Future<String?> discoverViaUdp() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final pingBytes = utf8.encode('VJ_STREAM_PING');
      socket.send(pingBytes, InternetAddress('255.255.255.255'), 3001);

      final completer = Completer<String?>();

      final sub = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data);
              final decoded = json.decode(text);
              if (decoded['app'] == 'VJ STREAM') {
                final host = datagram.address.address;
                final port = decoded['port'] ?? 3000;
                final foundUrl = 'http://$host:$port/api/streaming';
                if (!completer.isCompleted) {
                  completer.complete(foundUrl);
                }
              }
            } catch (_) {}
          }
        }
      });

      final result = await completer.future.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );

      await sub.cancel();
      socket.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Sondeo inteligente y concurrente en red local para conexión 100% transparente
  Future<bool> discoverBackend() async {
    // 0. Baliza UDP ultrarrápida (menos de 100ms)
    final udpUrl = await discoverViaUdp();
    if (udpUrl != null && await checkHealth(udpUrl)) {
      baseUrl = udpUrl;
      await saveBaseUrl(udpUrl);
      return true;
    }

    // 1. Probar entornos inmediatos (localhost, emulador android, loopback)
    final immediateCandidates = [
      'http://localhost:3000/api/streaming',
      'http://10.0.2.2:3000/api/streaming',
      'http://127.0.0.1:3000/api/streaming',
    ];

    for (final candidate in immediateCandidates) {
      if (await checkHealth(candidate)) {
        baseUrl = candidate;
        await saveBaseUrl(candidate);
        return true;
      }
    }

    // 2. Extraer dinámicamente la subred local del dispositivo
    final List<String> subnets = [];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final sub = '${parts[0]}.${parts[1]}.${parts[2]}';
              if (!subnets.contains(sub)) subnets.add(sub);
            }
          }
        }
      }
    } catch (_) {}

    // Agregar subredes comunes estándar
    for (final defSub in ['192.168.1', '192.168.0', '192.168.100', '10.0.0']) {
      if (!subnets.contains(defSub)) subnets.add(defSub);
    }

    // 3. Probar hosts prioritarios concurrentemente en bloques rápidos
    final priorityHosts = [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      18, 20, 25, 30, 40, 50, 60, 70, 80, 100, 101, 102, 103, 104, 105, 110, 120, 150, 200, 254
    ];

    for (final subnet in subnets) {
      final List<String> urlsToProbe = priorityHosts.map((h) => 'http://$subnet.$h:3000/api/streaming').toList();

      for (int i = 0; i < urlsToProbe.length; i += 12) {
        final chunk = urlsToProbe.sublist(i, (i + 12 > urlsToProbe.length) ? urlsToProbe.length : i + 12);
        final futures = chunk.map((url) async {
          final isAlive = await checkHealth(url);
          return isAlive ? url : null;
        });

        final results = await Future.wait(futures);
        for (final matchedUrl in results) {
          if (matchedUrl != null) {
            baseUrl = matchedUrl;
            await saveBaseUrl(matchedUrl);
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Busca contenidos en TMDB a través de nuestro endpoint backend
  Future<List<MediaItem>> searchMedia(String query, {String type = 'multi', int page = 1}) async {
    try {
      final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
        'q': query,
        'type': type,
        'page': page.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final results = data['data']['results'] as List<dynamic>? ?? [];
          return results.map((item) => MediaItem.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      // Retorna lista vacía en caso de error de conexión
      return [];
    }
  }

  /// Obtiene detalles completos de una película o serie
  Future<MediaItem?> getMediaDetails(String type, dynamic id) async {
    try {
      final uri = Uri.parse('$baseUrl/media/$type/$id');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return MediaItem.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Envía un magnet al backend para que Real-Debrid lo desbride y devuelva enlaces de streaming
  Future<List<StreamLink>> resolveMagnet(String magnet, {String files = 'all'}) async {
    try {
      final uri = Uri.parse('$baseUrl/resolve-stream');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'magnet': magnet,
          'files': files,
          'unrestrictAll': true,
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['streams'] != null) {
          final streams = data['streams'] as List<dynamic>;
          return streams.map((s) => StreamLink.fromJson(s)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Obtiene las 5 categorías completas del catálogo (Tendencias, Estrenos, Acción, Ciencia Ficción, Series)
  Future<Map<String, List<MediaItem>>> fetchFullCatalog() async {
    try {
      final uri = Uri.parse('$baseUrl/catalog');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final catalogData = data['data'] as Map<String, dynamic>;
          
          List<MediaItem> parseList(dynamic raw) {
            if (raw is List) {
              return raw.map((item) => MediaItem.fromJson(item)).toList();
            }
            return [];
          }

          final trending = parseList(catalogData['trending']);
          final nowPlaying = parseList(catalogData['nowPlaying']);
          final action = parseList(catalogData['action']);
          final scifi = parseList(catalogData['scifi']);
          final series = parseList(catalogData['series']);

          if (trending.isNotEmpty || nowPlaying.isNotEmpty || series.isNotEmpty) {
            return {
              'trending': trending,
              'nowPlaying': nowPlaying,
              'action': action,
              'scifi': scifi,
              'series': series,
            };
          }
        }
      }
      return _getFallbackContent();
    } catch (_) {
      return _getFallbackContent();
    }
  }

  /// Carga contenidos por lotes para compatibilidad
  Future<Map<String, List<MediaItem>>> fetchHomeCategories() async {
    return fetchFullCatalog();
  }

  /// Obtiene nuevas colecciones y filas temáticas para el scroll infinito de la Cartelera VJ STREAM
  Future<List<Map<String, dynamic>>> fetchInfiniteCategories(int page) async {
    try {
      final uri = Uri.parse('$baseUrl/catalog/infinite?page=$page');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['categories'] is List) {
          final List<Map<String, dynamic>> result = [];
          for (final cat in data['categories']) {
            if (cat is Map<String, dynamic>) {
              final title = (cat['title'] ?? 'Películas').toString();
              final rawItems = cat['items'];
              if (rawItems is List && rawItems.isNotEmpty) {
                final items = rawItems
                    .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
                    .where((m) => m.bestPosterUrl.isNotEmpty)
                    .toList();
                if (items.isNotEmpty) {
                  result.add({
                    'title': title,
                    'items': items,
                  });
                }
              }
            }
          }
          return result;
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }


  /// Resolución 100% automática para VJ STREAM con filtro estricto Anti-CAM y soporte para episodios:
  Future<Map<String, dynamic>?> autoResolveStream(
    MediaItem item, {
    int season = 1,
    int episode = 1,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/auto-resolve');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': item.title,
          'originalTitle': item.originalTitle,
          'year': item.releaseYear,
          'mediaType': item.mediaType,
          'id': item.id,
          'season': season,
          'episode': episode,
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true && body['data'] != null) {
          return body['data'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Obtiene los episodios detallados de una temporada para series
  Future<List<Map<String, dynamic>>> fetchTvSeasonEpisodes(dynamic tvId, int seasonNumber) async {
    try {
      final uri = Uri.parse('$baseUrl/tv/$tvId/season/$seasonNumber');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(utf8.decode(response.bodyBytes));
        if (body['success'] == true && body['episodes'] is List) {
          return List<Map<String, dynamic>>.from(body['episodes']);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Datos de muestra visuales estilo Netflix de alta fidelidad si la red no está conectada
  Map<String, List<MediaItem>> _getFallbackContent() {
    final mockMovies = [
      MediaItem(
        id: 27205,
        title: 'Origen (Inception)',
        synopsis: 'Dom Cobb es un ladrón hábil que roba secretos corporativos a través del uso de la tecnología de compartir sueños.',
        rating: 8.4,
        releaseDate: '2010-07-15',
        mediaType: 'movie',
        posterMedium: 'https://image.tmdb.org/t/p/w500/tXQvtRWfkUUnWJAn2tN3jERIUG.jpg',
        backdropLarge: 'https://image.tmdb.org/t/p/w1280/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg',
        genres: ['Ciencia Ficción', 'Acción', 'Aventura'],
      ),
      MediaItem(
        id: 157336,
        title: 'Interstellar',
        synopsis: 'Un equipo de exploradores viaja a través de un agujero de gusano en el espacio en un intento por asegurar la supervivencia de la humanidad.',
        rating: 8.6,
        releaseDate: '2014-11-05',
        mediaType: 'movie',
        posterMedium: 'https://image.tmdb.org/t/p/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg',
        backdropLarge: 'https://image.tmdb.org/t/p/w1280/xJHokMbljvjADYdit5fK5VQsXEG.jpg',
        genres: ['Aventura', 'Drama', 'Ciencia Ficción'],
      ),
      MediaItem(
        id: 299534,
        title: 'Vengadores: Endgame',
        synopsis: 'Después de los eventos devastadores de Infinity War, el universo está en ruinas debido a las acciones de Thanos.',
        rating: 8.3,
        releaseDate: '2019-04-24',
        mediaType: 'movie',
        posterMedium: 'https://image.tmdb.org/t/p/w500/or06FN3Dka5tukK1e9sl16pB3iy.jpg',
        backdropLarge: 'https://image.tmdb.org/t/p/w1280/7RyHsO4yDXtBv1zUU3mTpHeQ0d5.jpg',
        genres: ['Acción', 'Ciencia Ficción'],
      ),
      MediaItem(
        id: 603,
        title: 'The Matrix',
        synopsis: 'Un hacker informático descubre la verdadera naturaleza de su realidad y su papel en la guerra contra sus controladores.',
        rating: 8.2,
        releaseDate: '1999-03-30',
        mediaType: 'movie',
        posterMedium: 'https://image.tmdb.org/t/p/w500/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg',
        backdropLarge: 'https://image.tmdb.org/t/p/w1280/7u3fh9h9u7v7j5f6Y0bQ6m8l5T7.jpg',
        genres: ['Acción', 'Ciencia Ficción'],
      ),
    ];

    final mockSeries = [
      MediaItem(
        id: 66732,
        title: 'Stranger Things',
        synopsis: 'Cuando un niño desaparece, sus amigos, la familia y la policía se ven envueltos en un misterio que involucra experimentos ultrasecretos.',
        rating: 8.6,
        releaseDate: '2016-07-15',
        mediaType: 'tv',
        posterMedium: 'https://image.tmdb.org/t/p/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
        backdropLarge: 'https://image.tmdb.org/t/p/w1280/56v2KjBlU4XaOv9rVYEQypROD7P.jpg',
        genres: ['Ciencia Ficción', 'Drama', 'Misterio'],
      ),
      MediaItem(
        id: 1399,
        title: 'Juego de Tronos',
        synopsis: 'Nueve familias nobles luchan por el control de las tierras míticas de Poniente.',
        rating: 8.4,
        releaseDate: '2011-04-17',
        mediaType: 'tv',
        posterMedium: 'https://image.tmdb.org/t/p/w500/u3bZgnGQ9T01sWNhyveQz0wH0Hl.jpg',
        backdropLarge: 'https://image.tmdb.org/t/p/w1280/2OMB0ynKlyIenMJWI2Dy9IWT4c.jpg',
        genres: ['Drama', 'Fantasía'],
      ),
    ];

    return {
      'trending': mockMovies,
      'nowPlaying': [...mockMovies.reversed],
      'action': mockMovies.where((m) => m.genres.contains('Acción')).toList(),
      'scifi': mockMovies.where((m) => m.genres.contains('Ciencia Ficción')).toList(),
      'series': mockSeries,
    };
  }
}
