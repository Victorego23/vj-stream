import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Reproductor de Video optimizado para Streaming directo (Real-Debrid CDN).
/// Soporta aceleración por hardware, controles Smart TV con D-Pad, tolerancia a códecs y reconexión automática.
class VideoPlayerView extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerView({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  late FocusNode _tvFocusNode;
  final FocusNode _retryFocusNode = FocusNode();

  bool _isInitialized = false;
  bool _hasError = false;
  bool _isBuffering = false;
  String? _errorMessage;

  int _retryCount = 0;
  static const int _maxRetries = 2;

  bool _showControls = true;
  Timer? _hideControlsTimer;

  // Indicador visual de salto en pantalla (+10s o -10s)
  String? _seekIndicatorText;
  Timer? _seekIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _tvFocusNode = FocusNode();

    // Habilitar pantalla completa inmersiva para streaming
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initializePlayer();
  }

  Future<void> _initializePlayer({bool isUserRetry = false}) async {
    if (isUserRetry) {
      _retryCount = 0;
      setState(() {
        _hasError = false;
        _isInitialized = false;
        _errorMessage = null;
      });
    }

    try {
      // Limpiar controlador anterior si existiese
      if (_controller != null) {
        _controller!.removeListener(_videoListener);
        await _controller!.dispose();
        _controller = null;
      }

      final trimmedUrl = widget.videoUrl.trim();
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

      // Cabeceras de red estándar compatibles con streaming de alta velocidad y ExoPlayer
      final controller = VideoPlayerController.networkUrl(
        uri,
        formatHint: formatHint,
        httpHeaders: const {
          'User-Agent': 'VJ-STREAM/2.2.6 (Linux; Android; ExoPlayer)',
        },
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      _controller = controller;

      await controller.initialize();
      controller.addListener(_videoListener);

      // Reproducción inmediata
      await controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
          _errorMessage = null;
          _retryCount = 0;
        });

        _startHideTimer();
        _tvFocusNode.requestFocus();
      }
    } catch (e) {
      // Intento de reconexión automática si el CDN tarda en responder en el primer handshake
      if (_retryCount < _maxRetries && mounted) {
        _retryCount++;
        await Future.delayed(const Duration(milliseconds: 650));
        if (mounted) {
          return _initializePlayer();
        }
      }

      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
          _errorMessage =
              'No fue posible inicializar el flujo multimedia para "${widget.title}".\n'
              'Verifica tu conexión a internet o pulsa Reintentar.';
        });
        _retryFocusNode.requestFocus();
      }
    }
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;

    // Detectar fallos de decodificación o interrupción de códec en tiempo de ejecución
    if (_controller!.value.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = _controller!.value.errorDescription ??
            'Error al decodificar el flujo de video en Real-Debrid CDN.\nPor favor reintenta la conexión.';
      });
      _retryFocusNode.requestFocus();
      return;
    }

    final buffering = _controller!.value.isBuffering;
    if (buffering != _isBuffering) {
      setState(() {
        _isBuffering = buffering;
      });
    } else {
      setState(() {});
    }
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
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

  void _seekRelative(int seconds) {
    if (!_isInitialized || _controller == null) return;

    final currentPosition = _controller!.value.position;
    final targetPosition = currentPosition + Duration(seconds: seconds);
    final totalDuration = _controller!.value.duration;

    Duration finalDuration;
    if (targetPosition < Duration.zero) {
      finalDuration = Duration.zero;
    } else if (targetPosition > totalDuration) {
      finalDuration = totalDuration;
    } else {
      finalDuration = targetPosition;
    }

    _controller!.seekTo(finalDuration);
    _showFeedbackIndicator(seconds > 0 ? '+$seconds s' : '$seconds s');
    _startHideTimer();
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

  @override
  void dispose() {
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
          // Si hay error, permitir interacción con los botones
          if (_hasError) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }

          // Controles de Smart TV D-Pad
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
              // Área principal del video
              _buildVideoSurface(),

              // Indicador flotante en el centro (+10s, -10s, play/pausa)
              if (_seekIndicatorText != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE50914), width: 1.5),
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
                    'Problema de Transmisión CDN',
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
              const Text(
                'Conectando con CDN de Real-Debrid...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _retryCount > 0
                    ? 'Reintentando conexión automática ($_retryCount/$_maxRetries)...'
                    : 'Aceleración por hardware y optimización Smart TV activa',
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
        if (_isBuffering)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFFE50914),
                      strokeWidth: 2.5,
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Cargando stream CDN...',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    if (!_isInitialized || _controller == null) return const SizedBox.shrink();

    final position = _controller!.value.position;
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
                    child: const Text(
                      'VJ STREAM 4K',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.greenAccent, width: 0.8),
                    ),
                    child: const Text(
                      'AUDIO ESP',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
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
                  // Slider de progreso
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
                        _controller?.seekTo(Duration(milliseconds: val.toInt()));
                        _startHideTimer();
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
