import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/playback_history_service.dart';
import '../services/screen_service.dart';

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
    if (_isFallingBack || widget.mediaItem == null) return false;

    _failedUrls.add(_currentVideoUrl);
    setState(() {
      _isFallingBack = true;
    });

    final currentPos = _controller?.value.position ?? Duration.zero;

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

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9,
            child: VideoPlayer(_controller!),
          ),
        ),

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
                ],
              ),
            ),

            // Controles centrales (Retroceder 10s, Play/Pause, Avanzar 10s)
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

            // Barra inferior (Timeline y Tiempos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
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
