import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/playback_history_service.dart';
import '../services/screen_service.dart';

/// Elemento individual de subtítulo sincronizado
class _SubtitleItem {
  final Duration start;
  final Duration end;
  final String text;

  const _SubtitleItem({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Reproductor de Video optimizado para Streaming directo con aceleración por hardware.
/// Soporta controles Smart TV con D-Pad, prevención de apagado de pantalla (WakeLock nativo),
/// saltos de tiempo fluidos sin congelamientos y fallback automático transparente ante bloqueos de copyright.
class VideoPlayerView extends StatefulWidget {
  final String videoUrl;
  final String title;
  final dynamic mediaId;
  final String? posterUrl;
  final String? backdropUrl;
  final String? mediaType;
  final int? startPositionSeconds;
  final int? season;
  final int? episode;
  final String? audioLanguage;
  final String? qualityLabel;
  final MediaItem? mediaItem;
  final List<Map<String, dynamic>>? availableStreams;
  final List<Map<String, dynamic>>? subtitles;
  final bool isLive;

  const VideoPlayerView({
    super.key,
    required this.videoUrl,
    required this.title,
    this.mediaId,
    this.posterUrl,
    this.backdropUrl,
    this.mediaType,
    this.startPositionSeconds,
    this.season,
    this.episode,
    this.audioLanguage,
    this.qualityLabel,
    this.mediaItem,
    this.availableStreams,
    this.subtitles,
    this.isLive = false,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  VideoPlayerController? _controller;
  late FocusNode _tvFocusNode;
  final FocusNode _retryFocusNode = FocusNode();

  late String _currentVideoUrl;
  String? _currentQualityLabel;
  String? _currentAudioLanguage;
  String? _currentStreamId;
  List<Map<String, dynamic>> _availableStreams = [];
  BoxFit _videoFit = BoxFit.contain;
  bool _isLoadingNextEpisode = false;

  // Subtítulos
  List<Map<String, dynamic>> _subtitles = [];
  bool _subtitlesEnabled = false;
  String? _currentSubtitleUrl;
  List<_SubtitleItem> _parsedSubtitles = [];
  String? _activeSubtitleText;

  bool _isInitialized = false;
  bool _hasError = false;
  bool _isBuffering = false;
  bool _isSeeking = false;
  bool _isFallingBack = false;
  String? _errorMessage;

  int _retryCount = 0;
  static const int _maxRetries = 2;

  // Lista de URLs fallidas durante esta sesión para evitar reincidir en ellas
  final List<String> _failedUrls = [];

  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _progressSaveTimer;

  // Salto acumulativo y debouncing para adelantar/retroceder sin congelar la app
  int _accumulatedSeekSeconds = 0;
  Duration? _pendingSeekPosition;
  Timer? _seekDebounceTimer;
  Timer? _bufferingWatchdogTimer;

  // Arrastre manual en slider de tiempo
  Duration? _dragPosition;

  // Indicador visual de salto en pantalla (+10s, -10s, etc.)
  String? _seekIndicatorText;
  Timer? _seekIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _tvFocusNode = FocusNode();
    _currentVideoUrl = widget.videoUrl;
    _currentQualityLabel = widget.qualityLabel;
    _currentAudioLanguage = widget.audioLanguage;

    if (widget.availableStreams != null && widget.availableStreams!.isNotEmpty) {
      _availableStreams = List<Map<String, dynamic>>.from(widget.availableStreams!);
      final matching = _availableStreams.firstWhere(
        (s) => s['streamUrl'] == _currentVideoUrl,
        orElse: () => _availableStreams.first,
      );
      _currentStreamId = matching['id'] as String?;
    } else {
      _availableStreams = [
        {
          'id': 'latino',
          'label': _currentAudioLanguage ?? 'Español Latino (🇲🇽)',
          'language': _currentAudioLanguage ?? 'Español Latino',
          'streamUrl': _currentVideoUrl,
          'qualityLabel': _currentQualityLabel ?? '1080p FHD',
          'isBackup': false,
        }
      ];
      _currentStreamId = 'latino';
    }

    if (widget.subtitles != null && widget.subtitles!.isNotEmpty) {
      _subtitles = List<Map<String, dynamic>>.from(widget.subtitles!);
      // Si el audio predeterminado no es español, activar subtítulos automáticamente
      final isOriginalOrEnglish = (_currentAudioLanguage ?? '').toLowerCase().contains('ing') ||
          (_currentAudioLanguage ?? '').toLowerCase().contains('orig') ||
          _currentStreamId == 'original';
      if (isOriginalOrEnglish) {
        _subtitlesEnabled = true;
        _loadSubtitle(_subtitles.first);
      }
    }

    // Registrar observador del ciclo de vida de la aplicación
    WidgetsBinding.instance.addObserver(this);

    // Activar pantalla encendida permanente (FLAG_KEEP_SCREEN_ON) para que el celular no se apague
    ScreenService.keepScreenOn(true);

    // Habilitar pantalla completa inmersiva para streaming
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-asegurar encendido de pantalla al volver al primer plano
      ScreenService.keepScreenOn(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Liberar permanencia al pasar a segundo plano para ahorrar batería
      ScreenService.keepScreenOn(false);
    }
  }

  Future<void> _initializePlayer({bool isUserRetry = false, Duration? resumeAt}) async {
    if (isUserRetry) {
      _retryCount = 0;
      setState(() {
        _hasError = false;
        _isInitialized = false;
        _errorMessage = null;
      });
    }

    try {
      if (_controller != null) {
        _controller!.removeListener(_videoListener);
        await _controller!.dispose();
        _controller = null;
      }

      final trimmedUrl = _currentVideoUrl.trim();
      final uri = Uri.parse(trimmedUrl);

      // Detección tolerante de formato para CDN
      VideoFormat? formatHint;
      final lowerUrl = trimmedUrl.toLowerCase();
      if (lowerUrl.contains('.m3u8')) {
        formatHint = VideoFormat.hls;
      } else if (lowerUrl.contains('.mpd')) {
        formatHint = VideoFormat.dash;
      } else if (lowerUrl.contains('.mp4')) {
        formatHint = VideoFormat.other;
      }

      final controller = VideoPlayerController.networkUrl(
        uri,
        formatHint: formatHint,
        httpHeaders: const {
          'User-Agent': 'VJ-STREAM/2.4.1 (Linux; Android; ExoPlayer)',
        },
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      _controller = controller;

      await controller.initialize();
      controller.addListener(_videoListener);

      // Reanudar en la posición solicitada o en la guardada
      if (resumeAt != null && resumeAt > Duration.zero) {
        await controller.seekTo(resumeAt);
      } else if (widget.startPositionSeconds != null && widget.startPositionSeconds! > 0) {
        await controller.seekTo(Duration(seconds: widget.startPositionSeconds!));
      }

      await controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
          _errorMessage = null;
          _retryCount = 0;
          _isFallingBack = false;
        });

        _startHideTimer();
        _tvFocusNode.requestFocus();

        _progressSaveTimer?.cancel();
        _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          _saveCurrentProgress();
        });
      }
    } catch (e) {
      // Si la URL actual falló, intentar fallback automático a otra fuente antes de alarmar al usuario
      if (widget.mediaItem != null && !_isFallingBack && _retryCount < 2) {
        _retryCount++;
        final handled = await _triggerAutoFallback();
        if (handled) return;
      }

      if (_retryCount < _maxRetries && mounted) {
        _retryCount++;
        await Future.delayed(const Duration(milliseconds: 650));
        if (mounted) {
          return _initializePlayer(resumeAt: resumeAt);
        }
      }

      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
          _errorMessage =
              'No fue posible reproducir la transmisión para "${widget.title}".\n'
              'Verifica tu conexión a internet o pulsa Reintentar.';
        });
        _retryFocusNode.requestFocus();
      }
    }
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;

    // Detectar si el reproductor cargó un video estático de advertencia de error o DMCA
    // Los videos de advertencia de copyright de Debrid duran menos de 20 segundos
    if (_isInitialized && !_isFallingBack) {
      final totalDuration = _controller!.value.duration;
      final isMovieOrTv = (widget.mediaType == 'movie' || widget.mediaType == 'tv' || widget.mediaItem != null);
      if (isMovieOrTv && totalDuration > Duration.zero && totalDuration < const Duration(seconds: 22)) {
        debugPrint('[VideoPlayerView] 🛡️ Detectado clip de advertencia/error de Debrid (${totalDuration.inSeconds}s). Activando fallback transparente...');
        _triggerAutoFallback();
        return;
      }
    }

    // Detectar fallos de decodificación o caída del stream en vivo
    if (_controller!.value.hasError && !_hasError && !_isFallingBack) {
      // Intentar fallback automático antes de mostrar error al usuario
      if (widget.mediaItem != null) {
        _triggerAutoFallback();
        return;
      }

      setState(() {
        _hasError = true;
        _errorMessage = 'Se interrumpió el flujo de video.\nPor favor reintenta la conexión.';
      });
      _retryFocusNode.requestFocus();
      return;
    }

    final buffering = _controller!.value.isBuffering;
    if (buffering != _isBuffering) {
      setState(() {
        _isBuffering = buffering;
      });
      _resetBufferingWatchdog();
    }

    // Actualizar subtítulo activo según la posición de reproducción
    if (_subtitlesEnabled && _parsedSubtitles.isNotEmpty) {
      final pos = _controller!.value.position;
      String? foundText;
      for (final sub in _parsedSubtitles) {
        if (pos >= sub.start && pos <= sub.end) {
          foundText = sub.text;
          break;
        }
      }
      if (foundText != _activeSubtitleText) {
        setState(() {
          _activeSubtitleText = foundText;
        });
      }
    } else if (_activeSubtitleText != null) {
      setState(() {
        _activeSubtitleText = null;
      });
    } else {
      setState(() {});
    }
  }

  /// Watchdog para evitar que el reproductor quede congelado en buffering indefinidamente
  void _resetBufferingWatchdog() {
    _bufferingWatchdogTimer?.cancel();
    if (_isBuffering || _isSeeking) {
      _bufferingWatchdogTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && (_isBuffering || _isSeeking) && _controller != null) {
          debugPrint('[VideoPlayerView] 🔄 Watchdog activado: destrabando reproducción en búfer...');
          _controller!.play();
          setState(() {
            _isBuffering = false;
            _isSeeking = false;
          });
        }
      });
    }
  }

  /// Fallback automático transparente: busca la siguiente fuente disponible en el backend
  /// y la reproduce inmediatamente sin mostrar el cuadro naranja de error al usuario.
  Future<bool> _triggerAutoFallback() async {
    if (_isFallingBack) return false;

    _failedUrls.add(_currentVideoUrl);
    setState(() {
      _isFallingBack = true;
    });

    final currentPos = _controller?.value.position ?? Duration.zero;

    // 1. Intentar conmutar inmediatamente a un servidor de respaldo ya precargado
    final backup = _availableStreams.firstWhere(
      (s) =>
          (s['streamUrl'] as String?) != null &&
          s['streamUrl'] != _currentVideoUrl &&
          !_failedUrls.contains(s['streamUrl']),
      orElse: () => <String, dynamic>{},
    );
    if (backup.isNotEmpty) {
      debugPrint('[VideoPlayerView] 🔄 Usando servidor de respaldo pre-verificado...');
      _showFeedbackIndicator('Conectando a servidor alternativo...');
      await _switchStream(backup);
      if (mounted) setState(() => _isFallingBack = false);
      return true;
    }

    if (widget.mediaItem == null) {
      if (mounted) setState(() => _isFallingBack = false);
      return false;
    }

    try {
      debugPrint('[VideoPlayerView] 🔄 Solicitando fuente alternativa limpia para "${widget.title}"...');
      final fallbackStream = await _apiService.autoResolveStream(
        widget.mediaItem!,
        season: widget.season ?? 1,
        episode: widget.episode ?? 1,
        bypassCache: true,
        excludeUrls: _failedUrls,
      );

      final newUrl = fallbackStream?['streamUrl'] as String?;
      if (newUrl != null && newUrl.isNotEmpty && newUrl != _currentVideoUrl) {
        debugPrint('[VideoPlayerView] ✅ Fuente alternativa obtenida: $newUrl');
        _currentVideoUrl = newUrl;
        _currentQualityLabel = fallbackStream?['qualityLabel'] as String? ?? _currentQualityLabel;
        _currentAudioLanguage = fallbackStream?['audioLanguage'] as String? ?? _currentAudioLanguage;

        // Actualizar lista de streams disponibles si vinieron nuevos
        if (fallbackStream?['availableStreams'] is List) {
          _availableStreams = (fallbackStream!['availableStreams'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }

        _showFeedbackIndicator('Optimizando fuente...');
        await _initializePlayer(resumeAt: currentPos);
        return true;
      }
    } catch (e) {
      debugPrint('[VideoPlayerView] Error durante auto-fallback: $e');
    }

    if (mounted) {
      setState(() {
        _isFallingBack = false;
      });
    }
    return false;
  }

  Future<void> _switchStream(Map<String, dynamic> stream) async {
    final newUrl = stream['streamUrl'] as String?;
    if (newUrl == null || newUrl.isEmpty || newUrl == _currentVideoUrl) return;

    final currentPos = _controller?.value.position ?? Duration.zero;

    setState(() {
      _currentVideoUrl = newUrl;
      _currentAudioLanguage = stream['language'] as String? ?? stream['label'] as String?;
      _currentQualityLabel = stream['qualityLabel'] as String? ?? _currentQualityLabel;
      _currentStreamId = stream['id'] as String?;
      _isInitialized = false;
      _seekIndicatorText = 'Cambiando a ${_currentAudioLanguage ?? "fuente seleccionada"}...';
    });

    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _seekIndicatorText = null);
    });

    await _initializePlayer(resumeAt: currentPos);
  }

  /// Descarga y parsea el archivo de subtítulos (.srt / .vtt)
  Future<void> _loadSubtitle(Map<String, dynamic> sub) async {
    final url = sub['url'] as String?;
    if (url == null || url.isEmpty) return;

    _currentSubtitleUrl = url;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final parsed = _parseSubtitles(response.body);
        if (mounted) {
          setState(() {
            _parsedSubtitles = parsed;
            _subtitlesEnabled = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[VideoPlayerView] Error al cargar subtítulos: $e');
    }
  }

  /// Parsea archivos SRT a una lista estructurada con tiempos de inicio y fin
  List<_SubtitleItem> _parseSubtitles(String raw) {
    final items = <_SubtitleItem>[];
    final blocks = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n\n');
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;
      final timeLine = lines.length >= 2 && lines[1].contains('-->')
          ? lines[1]
          : (lines[0].contains('-->') ? lines[0] : null);
      if (timeLine == null) continue;

      final parts = timeLine.split('-->');
      if (parts.length != 2) continue;

      final start = _parseTimestamp(parts[0].trim());
      final end = _parseTimestamp(parts[1].trim());
      if (start == null || end == null) continue;

      final textIndex = lines.indexOf(timeLine) + 1;
      final textLines = lines.sublist(textIndex).join('\n');
      final cleanText = textLines.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (cleanText.isNotEmpty) {
        items.add(_SubtitleItem(start: start, end: end, text: cleanText));
      }
    }
    return items;
  }

  /// Convierte el formato 00:01:23,456 a Duration
  Duration? _parseTimestamp(String time) {
    try {
      final clean = time.replaceAll(',', '.');
      final parts = clean.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final seconds = int.parse(secParts[0]);
        final millis = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
      }
    } catch (_) {}
    return null;
  }

  bool get _hasNextEpisode =>
      widget.mediaType == 'tv' &&
      widget.season != null &&
      widget.episode != null &&
      widget.mediaItem != null;

  bool get _shouldShowNextEpisodeButton {
    if (!_hasNextEpisode || _controller == null || !_isInitialized) return false;
    final dur = _controller!.value.duration;
    final pos = _controller!.value.position;
    if (dur <= Duration.zero) return false;
    final remaining = (dur - pos).inSeconds;
    return remaining <= 90 && remaining > 0;
  }

  Future<void> _playNextEpisode() async {
    if (!_hasNextEpisode || _isLoadingNextEpisode) return;

    final nextEp = (widget.episode ?? 1) + 1;
    final season = widget.season ?? 1;

    setState(() {
      _isLoadingNextEpisode = true;
      _seekIndicatorText = 'Cargando Temporada $season, Ep. $nextEp...';
    });

    try {
      final streamInfo = await _apiService.autoResolveStream(
        widget.mediaItem!,
        season: season,
        episode: nextEp,
      );

      final nextUrl = streamInfo?['streamUrl'] as String?;
      if (nextUrl != null && nextUrl.isNotEmpty && mounted) {
        final available = (streamInfo?['availableStreams'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VideoPlayerView(
              videoUrl: nextUrl,
              title: '${widget.mediaItem!.title} T$season:E$nextEp',
              mediaId: widget.mediaItem!.id,
              posterUrl: widget.mediaItem!.bestPosterUrl,
              backdropUrl: widget.mediaItem!.bestBackdropUrl,
              mediaType: 'tv',
              season: season,
              episode: nextEp,
              audioLanguage: streamInfo?['audioLanguage'] as String?,
              qualityLabel: streamInfo?['qualityLabel'] as String?,
              mediaItem: widget.mediaItem,
              availableStreams: available,
              subtitles: (streamInfo?['subtitles'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
            ),
          ),
        );
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoadingNextEpisode = false;
        _seekIndicatorText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay más episodios disponibles para la Temporada $season.'),
          backgroundColor: const Color(0xFFE50914),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSettingsModal() {
    _hideControlsTimer?.cancel();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      barrierColor: Colors.black54,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0x33E50914), width: 1),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final audioStreams = _availableStreams.where((s) => s['isBackup'] != true).toList();
            final serverStreams = _availableStreams;

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: Color(0xFFE50914), size: 22),
                        const SizedBox(width: 10),
                        const Text(
                          'Ajustes de Reproducción',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // SECCIÓN 1: IDIOMA Y DOBLAJE
                    const Row(
                      children: [
                        Icon(Icons.record_voice_over_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Idioma de Audio y Doblaje',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (audioStreams.isNotEmpty)
                      ...audioStreams.map((st) {
                        final isSelected = (st['id'] == _currentStreamId) || (st['streamUrl'] == _currentVideoUrl);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0x22E50914) : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFE50914) : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.volume_up_rounded,
                              color: isSelected ? const Color(0xFFE50914) : Colors.white60,
                            ),
                            title: Text(
                              st['label'] ?? st['language'] ?? 'Audio',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              st['qualityLabel'] ?? 'Calidad HD',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFFE50914), size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _switchStream(st);
                            },
                          ),
                        );
                      })
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Audio en español latino activo por defecto.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // SECCIÓN 2: SERVIDOR / FUENTE
                    if (serverStreams.length > 1) ...[
                      const Row(
                        children: [
                          Icon(Icons.dns_rounded, color: Colors.cyanAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Servidor de Transmisión',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...serverStreams.map((st) {
                        final isSelected = st['streamUrl'] == _currentVideoUrl;
                        final isBackup = st['isBackup'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0x2200E5FF) : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.cyanAccent : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isBackup ? Icons.cloud_queue_rounded : Icons.cloud_done_rounded,
                              color: isSelected ? Colors.cyanAccent : Colors.white60,
                            ),
                            title: Text(
                              isBackup ? 'Servidor 2 (Alternativo / Respaldo)' : 'Servidor 1 (Alta Velocidad Principal)',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${st['language'] ?? 'Español'} • ${st['qualityLabel'] ?? 'HD'}',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Colors.cyanAccent, size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _switchStream(st);
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 14),
                    ],

                    // SECCIÓN 3: FORMATO DE PANTALLA (ASPECT RATIO)
                    const Row(
                      children: [
                        Icon(Icons.aspect_ratio_rounded, color: Colors.greenAccent, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Ajuste de Pantalla (Zoom y Proporción)',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildAspectOption(
                      title: 'Original (16:9)',
                      subtitle: 'Formato cinematográfico con barras negras naturales',
                      fit: BoxFit.contain,
                      icon: Icons.fit_screen_rounded,
                      onSelect: () {
                        setState(() => _videoFit = BoxFit.contain);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildAspectOption(
                      title: 'Ajustar a Pantalla (Sin Barras)',
                      subtitle: 'Zoom inteligente para cubrir toda la pantalla del móvil',
                      fit: BoxFit.cover,
                      icon: Icons.crop_free_rounded,
                      onSelect: () {
                        setState(() => _videoFit = BoxFit.cover);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildAspectOption(
                      title: 'Estirar Pantalla Completa',
                      subtitle: 'Estira la imagen para ocupar el 100% de la pantalla',
                      fit: BoxFit.fill,
                      icon: Icons.fullscreen_rounded,
                      onSelect: () {
                        setState(() => _videoFit = BoxFit.fill);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),

                    // SECCIÓN 4: SUBTÍTULOS EN ESPAÑOL
                    const Row(
                      children: [
                        Icon(Icons.subtitles_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Subtítulos en Español',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Opción: Desactivar Subtítulos
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: !_subtitlesEnabled ? const Color(0x22E50914) : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !_subtitlesEnabled ? const Color(0xFFE50914) : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.subtitles_off_rounded,
                          color: !_subtitlesEnabled ? const Color(0xFFE50914) : Colors.white60,
                        ),
                        title: const Text(
                          'Desactivar Subtítulos',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        trailing: !_subtitlesEnabled
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFFE50914), size: 20)
                            : null,
                        onTap: () {
                          setState(() {
                            _subtitlesEnabled = false;
                            _activeSubtitleText = null;
                          });
                          setSheetState(() {});
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ),

                    if (_subtitles.isNotEmpty)
                      ..._subtitles.map((sub) {
                        final isSelected = _subtitlesEnabled && (_currentSubtitleUrl == sub['url']);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0x22FFC107) : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.amber : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.closed_caption_rounded,
                              color: isSelected ? Colors.amber : Colors.white60,
                            ),
                            title: Text(
                              sub['label'] ?? 'Español',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              sub['fileName'] ?? 'Sincronizado',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Colors.amber, size: 20)
                                : null,
                            onTap: () {
                              _loadSubtitle(sub);
                              setState(() {
                                _subtitlesEnabled = true;
                              });
                              setSheetState(() {});
                              Navigator.pop(sheetContext);
                            },
                          ),
                        );
                      })
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Sin subtítulos adicionales para este contenido.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) _startHideTimer();
    });
  }

  Widget _buildAspectOption({
    required String title,
    required String subtitle,
    required BoxFit fit,
    required IconData icon,
    required VoidCallback onSelect,
  }) {
    final isSelected = _videoFit == fit;
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x2200E676) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? Colors.greenAccent : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: isSelected ? Colors.greenAccent : Colors.white60,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20)
            : null,
        onTap: onSelect,
      ),
    );
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && _controller != null && _controller!.value.isPlaying && !_isSeeking) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _togglePlayPause() {
    if (!_isInitialized || _controller == null) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _showControls = true);
      _hideControlsTimer?.cancel();
    } else {
      _controller!.play();
      _startHideTimer();
    }
    _showFeedbackIndicator(_controller!.value.isPlaying ? '▶' : '⏸');
  }

  /// Salto relativo acumulativo con debouncing inteligente.
  /// Permite presionar repetidamente (+10s, +20s, -10s) sin congelar la app ni saturar ExoPlayer.
  void _seekRelative(int seconds) {
    if (!_isInitialized || _controller == null) return;

    final currentPosition = _controller!.value.position;
    final totalDuration = _controller!.value.duration;

    if (_seekDebounceTimer?.isActive == true && _pendingSeekPosition != null) {
      _accumulatedSeekSeconds += seconds;
      _pendingSeekPosition = _pendingSeekPosition! + Duration(seconds: seconds);
    } else {
      _accumulatedSeekSeconds = seconds;
      _pendingSeekPosition = currentPosition + Duration(seconds: seconds);
    }

    if (_pendingSeekPosition! < Duration.zero) {
      _pendingSeekPosition = Duration.zero;
    } else if (_pendingSeekPosition! > totalDuration) {
      _pendingSeekPosition = totalDuration;
    }

    // Mostrar feedback instantáneo al usuario (+10 s, +20 s, -10 s)
    _showFeedbackIndicator(
      _accumulatedSeekSeconds > 0
          ? '+$_accumulatedSeekSeconds s'
          : '$_accumulatedSeekSeconds s',
    );

    _startHideTimer();
    setState(() {}); // Actualiza de inmediato el slider visual

    // Debounce de 320ms: Solo ejecuta un único salto real cuando el usuario deja de presionar
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 320), () async {
      final target = _pendingSeekPosition;
      if (target == null || _controller == null || !mounted) return;

      setState(() {
        _isSeeking = true;
      });

      try {
        await _controller!.seekTo(target);
        if (mounted && !_controller!.value.isPlaying) {
          await _controller!.play();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isSeeking = false;
          _pendingSeekPosition = null;
          _accumulatedSeekSeconds = 0;
        });
        _resetBufferingWatchdog();
      }
    });
  }

  void _showFeedbackIndicator(String text) {
    setState(() {
      _seekIndicatorText = text;
    });
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _seekIndicatorText = null);
      }
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _saveCurrentProgress() {
    if (_controller == null || !_isInitialized || widget.mediaId == null) return;
    try {
      final pos = _controller!.value.position.inSeconds;
      final dur = _controller!.value.duration.inSeconds;
      if (dur > 0) {
        PlaybackHistoryService.saveProgress(
          id: widget.mediaId,
          title: widget.title,
          posterUrl: widget.posterUrl ?? '',
          backdropUrl: widget.backdropUrl ?? '',
          mediaType: widget.mediaType ?? 'movie',
          positionSeconds: pos,
          durationSeconds: dur,
          season: widget.season,
          episode: widget.episode,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Liberar permanencia de pantalla al salir del reproductor
    ScreenService.keepScreenOn(false);

    _progressSaveTimer?.cancel();
    _saveCurrentProgress();

    _seekDebounceTimer?.cancel();
    _bufferingWatchdogTimer?.cancel();
    _hideControlsTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _tvFocusNode.dispose();
    _retryFocusNode.dispose();

    if (_controller != null) {
      _controller!.removeListener(_videoListener);
      _controller!.dispose();
    }

    // Restaurar barras del sistema al salir del reproductor
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _tvFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (_hasError) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }

          // Controles Smart TV D-Pad
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
            _togglePlayPause();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.mediaFastForward) {
            _seekRelative(10);
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.mediaRewind) {
            _seekRelative(-10);
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _toggleControls();
            return KeyEventResult.handled;
          }

          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < screenWidth / 2) {
              _seekRelative(-10);
            } else {
              _seekRelative(10);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Superficie principal de video
              _buildVideoSurface(),

              // Indicador flotante en el centro (+10s, -10s, play/pausa)
              if (_seekIndicatorText != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE50914), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE50914).withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      _seekIndicatorText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Botón flotante 'Siguiente Episodio' cuando queda poco tiempo en la serie
              if (!widget.isLive && _shouldShowNextEpisodeButton)
                Positioned(
                  bottom: _showControls ? 95 : 24,
                  right: 20,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      elevation: 6,
                      shadowColor: const Color(0xFFE50914).withValues(alpha: 0.5),
                    ),
                    onPressed: _playNextEpisode,
                    icon: const Icon(Icons.skip_next_rounded, size: 22),
                    label: Text(
                      'Siguiente Ep. ${(widget.episode ?? 0) + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),

              // Capa de controles (OSD) estilo Netflix
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: _showControls ? _buildControlsOverlay() : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2E2E), width: 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 20, spreadRadius: 4),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Problema de Transmisión',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage ?? 'No fue posible conectar con el servidor de streaming.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        focusNode: _retryFocusNode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _initializePlayer(isUserRetry: true),
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                        label: const Text('Reintentar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF444444)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Volver'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(
                  color: Color(0xFFE50914),
                  strokeWidth: 3.5,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isFallingBack ? 'Optimizando fuente alternativa limpia...' : 'Cargando reproducción...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _retryCount > 0
                    ? 'Reintentando conexión automática ($_retryCount/$_maxRetries)...'
                    : 'Aceleración por hardware y optimización activa',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final double videoAspect =
        _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9;

    Widget videoWidget;
    if (_videoFit == BoxFit.contain) {
      videoWidget = Center(
        child: AspectRatio(
          aspectRatio: videoAspect,
          child: VideoPlayer(_controller!),
        ),
      );
    } else if (_videoFit == BoxFit.cover) {
      videoWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 1920,
            height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 1080,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    } else {
      videoWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 1920,
            height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 1080,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        videoWidget,

        // Pantalla limpia y fluida de buffering (sin textos técnicos ni bloqueos)
        if (_isBuffering || _isSeeking)
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  color: Color(0xFFE50914),
                  strokeWidth: 3.0,
                ),
              ),
            ),
          ),

        // Subtítulos flotantes estilo Netflix (centrados, con fondo oscuro legible y sombras)
        if (_subtitlesEnabled && _activeSubtitleText != null && _activeSubtitleText!.isNotEmpty)
          Positioned(
            bottom: _showControls ? 95 : 38,
            left: 28,
            right: 28,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _activeSubtitleText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    shadows: [
                      Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    if (!_isInitialized || _controller == null) return const SizedBox.shrink();

    final position = _dragPosition ?? _pendingSeekPosition ?? _controller!.value.position;
    final duration = _controller!.value.duration;
    final isPlaying = _controller!.value.isPlaying;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.25, 0.70, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Barra superior
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isLive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(color: Color(0x88E50914), blurRadius: 8, spreadRadius: 1),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
                          SizedBox(width: 4),
                          Text(
                            'EN VIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFF990000)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _currentQualityLabel ?? '1080p FHD',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.greenAccent, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.volume_up_rounded, color: Colors.greenAccent, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _currentAudioLanguage ?? 'Español',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isLive) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        _subtitlesEnabled ? Icons.closed_caption_rounded : Icons.closed_caption_disabled_outlined,
                        color: _subtitlesEnabled ? Colors.amber : Colors.white70,
                        size: 24,
                      ),
                      tooltip: 'Subtítulos',
                      onPressed: () {
                        setState(() {
                          _subtitlesEnabled = !_subtitlesEnabled;
                          if (_subtitlesEnabled && _parsedSubtitles.isEmpty && _subtitles.isNotEmpty) {
                            _loadSubtitle(_subtitles.first);
                          }
                        });
                        _showFeedbackIndicator(_subtitlesEnabled ? 'Subtítulos Activados' : 'Subtítulos Desactivados');
                      },
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 24),
                    tooltip: 'Ajustes de Audio y Pantalla',
                    onPressed: _showSettingsModal,
                  ),
                ],
              ),
            ),

            // Controles centrales
            if (widget.isLive)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 42,
                    tooltip: 'Recargar Señal en Vivo',
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    onPressed: () => _initializePlayer(isUserRetry: true),
                  ),
                  const SizedBox(width: 28),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(
                      isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                      color: const Color(0xFFE50914),
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  const SizedBox(width: 28),
                  IconButton(
                    iconSize: 42,
                    tooltip: 'Ajuste de Pantalla',
                    icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        if (_videoFit == BoxFit.contain) {
                          _videoFit = BoxFit.cover;
                          _showFeedbackIndicator('Pantalla: Zoom');
                        } else if (_videoFit == BoxFit.cover) {
                          _videoFit = BoxFit.fill;
                          _showFeedbackIndicator('Pantalla: Estirar');
                        } else {
                          _videoFit = BoxFit.contain;
                          _showFeedbackIndicator('Pantalla: Original (16:9)');
                        }
                      });
                    },
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 42,
                    icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                    onPressed: () => _seekRelative(-10),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(
                      isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                      color: const Color(0xFFE50914),
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 42,
                    icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                    onPressed: () => _seekRelative(10),
                  ),
                ],
              ),

            // Barra inferior (Timeline y Tiempos o Directo)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: widget.isLive
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE50914),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Color(0xAAE50914), blurRadius: 6, spreadRadius: 1),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'SEÑAL DIRECTA EN VIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.access_time_rounded, color: Colors.white54, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Sintonizado: ${_formatDuration(position)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFE50914),
                            inactiveTrackColor: Colors.white24,
                            thumbColor: const Color(0xFFE50914),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayColor: const Color(0x33E50914),
                            trackHeight: 3.5,
                          ),
                          child: Slider(
                            value: position.inMilliseconds
                                .toDouble()
                                .clamp(0.0, duration.inMilliseconds.toDouble()),
                            min: 0.0,
                            max: duration.inMilliseconds.toDouble() > 0
                                ? duration.inMilliseconds.toDouble()
                                : 1.0,
                            onChanged: (val) {
                              setState(() {
                                _dragPosition = Duration(milliseconds: val.toInt());
                              });
                              _startHideTimer();
                            },
                            onChangeEnd: (val) async {
                              final dest = Duration(milliseconds: val.toInt());
                              setState(() {
                                _dragPosition = null;
                                _isSeeking = true;
                              });
                              try {
                                await _controller?.seekTo(dest);
                                if (mounted && !_controller!.value.isPlaying) {
                                  await _controller?.play();
                                }
                              } catch (_) {}
                              if (mounted) {
                                setState(() {
                                  _isSeeking = false;
                                });
                                _resetBufferingWatchdog();
                              }
                            },
                          ),
                        ),

                        // Tiempos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
