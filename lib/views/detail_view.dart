import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/playback_history_service.dart';
import '../services/trailer_service.dart';
import '../services/coming_soon_service.dart';
import 'video_player_view.dart';

/// Pantalla de Detalles de Película / Serie (DetailView) para VJ STREAM.
/// Reproducción 100% automática, sin pantallas técnicas ni diálogos de magnets.
/// Soporta modo Tráiler para películas en inglés e integración automática al salir en español.

class DetailView extends StatefulWidget {
  final MediaItem item;

  const DetailView({super.key, required this.item});

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  final ApiService _apiService = ApiService();
  final FocusNode _playButtonFocus = FocusNode();
  late MediaItem _currentItem;
  bool _isTrailerOnly = false;
  bool _hasReminder = false;
  bool _isCheckingAvailability = false;
  bool _isPreparing = false;
  bool _isFavorite = false;
  int _selectedSeason = 1;
  List<Map<String, dynamic>> _episodes = [];
  bool _isLoadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    _isTrailerOnly = widget.item.isTrailerOnly;
    _checkFavorite();
    _checkReminder();
    if (_isTrailerOnly) {
      _verifySpanishAvailability();
    }
    if (widget.item.mediaType == 'tv') {
      _loadEpisodes(1);
    }
    // Autoenfocar el botón de reproducir en Smart TV
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playButtonFocus.requestFocus();
    });
  }

  Future<void> _checkFavorite() async {
    final fav = await PlaybackHistoryService.isFavorite(_currentItem.id);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final newFav = await PlaybackHistoryService.toggleFavorite(_currentItem);
    if (mounted) {
      setState(() => _isFavorite = newFav);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newFav ? '⭐ Agregado a Mi Lista' : 'Eliminado de Mi Lista'),
          backgroundColor: newFav ? const Color(0xFF22C55E) : const Color(0xFFE50914),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkReminder() async {
    final has = await ComingSoonService.hasReminder(_currentItem.id);
    if (mounted) setState(() => _hasReminder = has);
  }

  Future<void> _toggleReminder() async {
    final newReminder = await ComingSoonService.toggleReminder(_currentItem);
    if (mounted) {
      setState(() => _hasReminder = newReminder);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newReminder
                ? '🔔 Te avisaremos en cuanto salga en Español Latino / Castellano'
                : 'Recordatorio cancelado',
          ),
          backgroundColor: newReminder ? const Color(0xFFF59E0B) : const Color(0xFF333333),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Comprueba en segundo plano si la película ya salió con audio en español.
  /// Si es así, se integra automáticamente al catálogo disponible al instante.
  Future<void> _verifySpanishAvailability() async {
    setState(() => _isCheckingAvailability = true);
    try {
      final res = await _apiService.checkSpanishAvailability(_currentItem);
      if (!mounted) return;
      if (res?['hasSpanishAudio'] == true || res?['isAvailable'] == true) {
        setState(() {
          _isTrailerOnly = false;
          _currentItem = _currentItem.copyWith(
            isTrailerOnly: false,
            hasSpanishAudio: true,
            statusBadge: '¡Ya disponible en Español!',
          );
          _isCheckingAvailability = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text('🎉 ¡Genial! Esta película ya está disponible en Español.'),
                ),
              ],
            ),
            backgroundColor: Color(0xFF1B5E20),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _isCheckingAvailability = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingAvailability = false);
    }
  }

  /// Reproduce el tráiler oficial con extracción nativa sin salir de la aplicación
  Future<void> _playTrailer() async {
    final trailerSource = _currentItem.trailerKey ?? _currentItem.trailerUrl;
    if (trailerSource == null || trailerSource.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tráiler oficial no disponible para este título.'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Cargando tráiler oficial de ${_currentItem.title}...',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final directStreamUrl = await TrailerService().resolveDirectStreamUrl(trailerSource);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerView(
              videoUrl: directStreamUrl,
              title: '🎬 Tráiler: ${_currentItem.title}',
              posterUrl: _currentItem.bestPosterUrl,
              backdropUrl: _currentItem.bestBackdropUrl,
              mediaType: _currentItem.mediaType,
              audioLanguage: 'Tráiler Oficial (HD)',
              qualityLabel: 'HD 720p',
              mediaItem: _currentItem,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo iniciar el stream del tráiler. Intenta nuevamente.'),
            backgroundColor: Color(0xFFE50914),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al conectar con el servidor del tráiler.'),
          backgroundColor: Color(0xFFE50914),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadEpisodes(int season) async {
    setState(() {
      _selectedSeason = season;
      _isLoadingEpisodes = true;
    });
    try {
      final eps = await _apiService.fetchTvSeasonEpisodes(widget.item.id, season);
      if (mounted) {
        setState(() {
          _episodes = eps;
          _isLoadingEpisodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  /// Inicia el flujo de reproducción con filtro estricto Anti-CAM y soporte de episodios
  Future<void> _startPlayback({int season = 1, int episode = 1, String? episodeTitle}) async {
    if (_isPreparing) return;

    setState(() => _isPreparing = true);

    final displayTitle = episodeTitle != null ? '${widget.item.title}: $episodeTitle' : widget.item.title;

    // Diálogo minimalista de carga estilo Netflix / VJ STREAM
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'TOM TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preparando transmisión en alta definición...',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  displayTitle,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final streamInfo = await _apiService.autoResolveStream(
        widget.item,
        season: season,
        episode: episode,
      );

      if (!mounted) return;
      // Cerrar diálogo de carga
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _isPreparing = false);

      // Si hay una transmisión resuelta, reproducir directamente sin diálogos molestos
      final streamUrl = streamInfo?['streamUrl'] as String?;
      if (streamUrl != null && streamUrl.isNotEmpty) {
        final available = (streamInfo?['availableStreams'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        // Abrir inmediatamente el reproductor multimedia con la transmisión y opciones multicanal
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerView(
              videoUrl: streamUrl,
              title: displayTitle,
              mediaId: widget.item.id,
              posterUrl: widget.item.bestPosterUrl,
              backdropUrl: widget.item.bestBackdropUrl,
              mediaType: widget.item.mediaType,
              season: season,
              episode: episode,
              audioLanguage: streamInfo?['audioLanguage'] as String?,
              qualityLabel: streamInfo?['qualityLabel'] as String?,
              mediaItem: widget.item,
              availableStreams: available,
              subtitles: (streamInfo?['subtitles'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
            ),
          ),
        );
        return;
      }

      // Si no hay enlace de transmisión válido o el servidor reportó no disponibilidad en español
      _showStreamUnavailableModal(
        displayTitle,
        streamInfo,
        season: season,
        episode: episode,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _isPreparing = false);

      _showStreamUnavailableModal(
        displayTitle,
        null,
        season: season,
        episode: episode,
      );
    }
  }

  /// Muestra un diálogo VIP moderno y amigable cuando un título no tiene transmisión activa,
  /// evitando cuadros de error rojos y ofreciendo el tráiler oficial o recordatorio automático.
  void _showStreamUnavailableModal(
    String displayTitle,
    Map<String, dynamic>? streamInfo, {
    int season = 1,
    int episode = 1,
  }) {
    if (!mounted) return;
    final message = streamInfo?['message'] as String? ??
        'Esta película se encuentra actualmente en proceso de digitalización o en salas de cine. TOM TV protege tu experiencia evitando grabaciones de mala calidad o enlaces caídos.';

    showDialog(
      context: context,
      builder: (dContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x33F59E0B), width: 1.2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.movie_filter_rounded, color: Color(0xFFF59E0B), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Próximamente en Español',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayTitle,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'TOM TV solo ofrece contenidos en alta definición (1080p / 4K) verificados.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dContext),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white54)),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF59E0B),
              side: const BorderSide(color: Color(0xFFF59E0B), width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(_hasReminder ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 16),
            onPressed: () {
              Navigator.pop(dContext);
              _toggleReminder();
            },
            label: Text(_hasReminder ? 'Recordatorio Activo' : 'Avisarme (ESP)'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.movie_creation_rounded, size: 16),
            onPressed: () {
              Navigator.pop(dContext);
              _playTrailer();
            },
            label: const Text('Ver Tráiler Oficial', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Negro absoluto OLED
      body: CustomScrollView(
        slivers: [
          // AppBar con Backdrop
          SliverAppBar(
            backgroundColor: Colors.transparent,
            expandedHeight: isTv ? size.height * 0.55 : size.height * 0.40,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.item.bestBackdropUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0D0D0D)),
                  ),
                  // Gradiente inferior a negro OLED
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.45, 1.0],
                        colors: [
                          Colors.transparent,
                          Color(0x99000000),
                          Color(0xFF000000),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Contenido de detalles
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título principal
                  Text(
                    widget.item.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isTv ? 34 : 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Metadatos (Puntuación, año, calidad comercial, audio español o modo tráiler)
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_currentItem.rating > 0) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _currentItem.formattedRating,
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_currentItem.releaseYear.isNotEmpty) ...[
                        Text(
                          _currentItem.releaseYear,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                      if (_isTrailerOnly) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.movie_creation_rounded, color: Colors.black, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'SOLO TRÁILER',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1705),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isCheckingAvailability) ...[
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              const Text(
                                'PRÓXIMAMENTE EN ESPAÑOL',
                                style: TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            border: Border.all(color: Colors.white24, width: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ORIGINAL (CINE / INGLÉS)',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withValues(alpha: 0.2),
                            border: Border.all(color: const Color(0xFFE50914), width: 0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'CALIDAD 4K / 1080p',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            border: Border.all(color: Colors.greenAccent, width: 0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'ANTI-CAM CERTIFICADO',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            border: Border.all(color: Colors.white30, width: 0.6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'AUDIO ESPAÑOL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Botón principal de reproducción automática con D-Pad focus
                  _buildAutoPlayButton(),
                  const SizedBox(height: 12),

                  // Botones secundarios: Mi Lista y Ver Tráiler
                  _buildSecondaryActions(),
                  const SizedBox(height: 20),

                  // Géneros
                  if (widget.item.genres.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: widget.item.genres.map((genre) {
                        return Chip(
                          backgroundColor: const Color(0xFF161616),
                          label: Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),

                  // Sinopsis
                  const Text(
                    'Sinopsis',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.synopsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Selector de Temporadas y Capítulos (Solo para Series de TV)
                  if (widget.item.mediaType == 'tv') ...[
                    _buildEpisodesSection(),
                    const SizedBox(height: 24),
                  ],

                  // Características de transmisión VJ STREAM
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D0D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1F1F1F)),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureRow(
                          icon: Icons.high_quality_rounded,
                          title: 'Máxima Calidad Garantizada',
                          subtitle: 'Filtro Anti-CAM estricto. Fuentes en 4K UHD, HDR y 1080p BluRay / WEB-DL.',
                        ),
                        const Divider(color: Color(0xFF1E1E1E), height: 20),
                        _buildFeatureRow(
                          icon: Icons.language_rounded,
                          title: 'Prioridad de Audio en Español',
                          subtitle: 'Preferente en Español Latino y Castellano con subtítulos sincronizados.',
                        ),
                        const Divider(color: Color(0xFF1E1E1E), height: 20),
                        _buildFeatureRow(
                          icon: Icons.speed_rounded,
                          title: 'Servidores CDN Ultrarrápidos',
                          subtitle: 'Sin esperas ni buffering mediante desbridado en la nube de alta velocidad.',
                        ),
                      ],
                    ),
                  ),

                  // Margen inferior seguro
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPlayButton() {
    return Focus(
      focusNode: _playButtonFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (_isTrailerOnly) {
              _playTrailer();
            } else {
              _startPlayback();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (_isTrailerOnly) {
            _playTrailer();
          } else {
            _startPlayback();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isTrailerOnly
                  ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                  : const [Color(0xFFE50914), Color(0xFF990000)],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _playButtonFocus.hasFocus
                  ? (_isTrailerOnly ? Colors.amberAccent : Colors.white)
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isTrailerOnly ? const Color(0xFFF59E0B) : const Color(0xFFE50914))
                    .withValues(alpha: _playButtonFocus.hasFocus ? 0.6 : 0.25),
                blurRadius: _playButtonFocus.hasFocus ? 18 : 10,
                spreadRadius: _playButtonFocus.hasFocus ? 2 : 0,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isTrailerOnly ? Icons.movie_creation_rounded : Icons.play_arrow_rounded,
                color: _isTrailerOnly ? Colors.black : Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                _isTrailerOnly ? 'Ver Tráiler Oficial' : 'Reproducir en TOM TV',
                style: TextStyle(
                  color: _isTrailerOnly ? Colors.black : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Botón Mi Lista
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleFavorite,
                icon: Icon(
                  _isFavorite ? Icons.check_circle_rounded : Icons.add_rounded,
                  color: _isFavorite ? const Color(0xFF22C55E) : Colors.white,
                  size: 20,
                ),
                label: Text(
                  _isFavorite ? 'En Mi Lista' : 'Mi Lista',
                  style: TextStyle(
                    color: _isFavorite ? const Color(0xFF22C55E) : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: _isFavorite ? const Color(0xFF22C55E) : const Color(0xFF333333),
                    width: 1.5,
                  ),
                  backgroundColor: const Color(0xFF141414),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Si está en modo tráiler: Botón "Avisarme cuando esté en español"
            // Si está completa: Botón "Tráiler"
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTrailerOnly ? _toggleReminder : _playTrailer,
                icon: Icon(
                  _isTrailerOnly
                      ? (_hasReminder ? Icons.notifications_active_rounded : Icons.notification_add_rounded)
                      : Icons.movie_creation_outlined,
                  color: _isTrailerOnly
                      ? (_hasReminder ? const Color(0xFFF59E0B) : Colors.white)
                      : Colors.white,
                  size: 20,
                ),
                label: Text(
                  _isTrailerOnly
                      ? (_hasReminder ? 'Te avisaremos' : 'Avisarme (ESP)')
                      : 'Tráiler',
                  style: TextStyle(
                    color: _isTrailerOnly
                        ? (_hasReminder ? const Color(0xFFF59E0B) : Colors.white)
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: _isTrailerOnly && _hasReminder
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF333333),
                    width: 1.5,
                  ),
                  backgroundColor: const Color(0xFF141414),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ],
        ),

        // Banner informativo elegante si está en modo Solo Tráiler
        if (_isTrailerOnly) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161208),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Integración Automática al Salir en Español',
                        style: TextStyle(
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Esta película se encuentra en cines o en versión inglesa. En cuanto se detecte una copia de alta calidad con audio en Español Latino o Castellano, se habilitará la reproducción completa automáticamente.',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEpisodesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.tv_rounded, color: Color(0xFFE50914), size: 22),
            SizedBox(width: 8),
            Text(
              'Temporadas y Episodios',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Selector horizontal de temporadas (Temporada 1 a 6)
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final seasonNum = index + 1;
              final isSelected = _selectedSeason == seasonNum;
              return ChoiceChip(
                label: Text('Temporada $seasonNum'),
                selected: isSelected,
                selectedColor: const Color(0xFFE50914),
                backgroundColor: const Color(0xFF181818),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFFE50914) : const Color(0xFF333333),
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    _loadEpisodes(seasonNum);
                  }
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Lista de episodios
        if (_isLoadingEpisodes)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: CircularProgressIndicator(color: Color(0xFFE50914)),
            ),
          )
        else if (_episodes.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF222222)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white54, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No hay capítulos registrados para esta temporada o se cargarán al reproducir.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _episodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final ep = _episodes[index];
              final epNum = ep['episode_number'] ?? (index + 1);
              final epName = ep['name'] ?? 'Episodio $epNum';
              final overview = ep['overview'] ?? '';
              final stillPath = ep['still_path'];
              final runtime = ep['runtime'];
              final stillUrl = stillPath != null ? 'https://image.tmdb.org/t/p/w300$stillPath' : null;

              return InkWell(
                onTap: () {
                  _startPlayback(
                    season: _selectedSeason,
                    episode: epNum,
                    episodeTitle: 'T$_selectedSeason:E$epNum - $epName',
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF222222)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Miniatura del episodio
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 110,
                          height: 65,
                          color: const Color(0xFF222222),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (stillUrl != null)
                                Image.network(
                                  stillUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.movie_rounded, color: Colors.white24, size: 28),
                                  ),
                                )
                              else
                                const Center(
                                  child: Icon(Icons.movie_rounded, color: Colors.white24, size: 28),
                                ),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Datos del episodio
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$epNum. $epName',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (runtime != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '$runtime min',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ),
                            if (overview.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  overview,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFE50914), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
