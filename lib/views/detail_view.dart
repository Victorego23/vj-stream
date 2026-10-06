import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/playback_history_service.dart';
import '../services/trailer_service.dart';
import '../services/coming_soon_service.dart';
import '../widgets/stream_resolving_dialog.dart';
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
    _playButtonFocus.addListener(_handlePlayFocus);
    // Autoenfocar el botón de reproducir en Smart TV
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playButtonFocus.requestFocus();
    });
  }

  void _handlePlayFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _playButtonFocus.removeListener(_handlePlayFocus);
    _playButtonFocus.dispose();
    super.dispose();
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
  Future<void> _startPlayback({
    int season = 1,
    int episode = 1,
    String? episodeTitle,
    bool selectSourceManually = false,
  }) async {
    if (_isPreparing) return;

    setState(() => _isPreparing = true);

    final displayTitle = episodeTitle != null ? '${widget.item.title}: $episodeTitle' : widget.item.title;

    // Diálogo cinematográfico animado estilo TOM TV
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StreamResolvingDialog(
        title: displayTitle,
        posterUrl: widget.item.bestPosterUrl,
        backdropUrl: widget.item.bestBackdropUrl,
        mediaType: widget.item.mediaType,
        season: widget.item.isSeries ? season : null,
        episode: widget.item.isSeries ? episode : null,
        onCancel: () {
          setState(() => _isPreparing = false);
        },
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

      // Si hay una transmisión resuelta
      String? streamUrl = streamInfo?['streamUrl'] as String?;
      String audioLang = (streamInfo?['audioLanguage'] as String?) ?? 'Español Latino';
      String quality = (streamInfo?['qualityLabel'] as String?) ?? '1080p Full HD';

      if (streamUrl != null && streamUrl.isNotEmpty) {
        final available = (streamInfo?['availableStreams'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        // Si el usuario pidió seleccionar fuente manualmente y hay opciones
        if (selectSourceManually && available != null && available.length > 1) {
          _showManualSourceSelector(
            displayTitle: displayTitle,
            defaultStreamUrl: streamUrl,
            availableStreams: available,
            streamInfo: streamInfo!,
            season: season,
            episode: episode,
          );
          return;
        }

        // Abrir inmediatamente el reproductor multimedia con la transmisión y opciones multicanal
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerView(
              videoUrl: streamUrl!,
              title: displayTitle,
              mediaId: widget.item.id,
              posterUrl: widget.item.bestPosterUrl,
              backdropUrl: widget.item.bestBackdropUrl,
              mediaType: widget.item.mediaType,
              season: season,
              episode: episode,
              audioLanguage: audioLang,
              qualityLabel: quality,
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

      // Si no hay enlace de transmisión completo verificado, mostrar diálogo VIP informativo
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

      // En caso de error de red o sin conexión, mostrar modal informativo VIP
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

    final isTelenovela = displayTitle.toLowerCase().contains('cielos') ||
        displayTitle.toLowerCase().contains('telemundo') ||
        displayTitle.toLowerCase().contains('novela') ||
        widget.item.title.toLowerCase().contains('cielos');

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
          if (isTelenovela)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.live_tv_rounded, size: 16),
              onPressed: () {
                Navigator.pop(dContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const VideoPlayerView(
                      videoUrl: 'http://138.121.15.230:9002/TELEMUNDO/index.m3u8',
                      title: 'Telemundo Novelas (El Señor de los Cielos 24/7)',
                      audioLanguage: 'Español Latino (En Vivo)',
                      qualityLabel: '1080p FHD',
                    ),
                  ),
                );
              },
              label: const Text('Ver en TV en Vivo', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final isTv = size.width > 680 || (MediaQuery.of(context).orientation == Orientation.landscape && size.width > 520);

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
                  if (isTv)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTvPosterCard(),
                        const SizedBox(width: 36),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildMetadataBadges(),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 260,
                                    child: _buildAutoPlayButton(),
                                  ),
                                  const SizedBox(width: 14),
                                  SizedBox(
                                    width: 320,
                                    child: _buildSecondaryActions(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildGenresWrap(),
                              const SizedBox(height: 16),
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
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    // Título principal Móvil
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildMetadataBadges(),
                    const SizedBox(height: 20),
                    _buildAutoPlayButton(),
                    const SizedBox(height: 12),
                    _buildSecondaryActions(),
                    const SizedBox(height: 20),
                    _buildGenresWrap(),
                    const SizedBox(height: 16),
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
                  ],
                  const SizedBox(height: 24),

                  // Selector de Temporadas y Capítulos (Solo para Series de TV)
                  if (widget.item.mediaType == 'tv') ...[
                    _buildEpisodesSection(),
                    const SizedBox(height: 24),
                  ],

                  // Características de transmisión VJ STREAM
                  _buildFeaturesSection(),

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

  Widget _buildTvPosterCard() {
    return Container(
      width: 220,
      height: 330,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66E50914), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE50914).withValues(alpha: 0.3),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          widget.item.bestPosterUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF161616),
            child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 64),
          ),
        ),
      ),
    );
  }

  String _formatRuntime(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  Widget _buildMetadataBadges() {
    final List<Widget> items = [];

    // Calificación de estrellas (estilo Apple TV / IMDb)
    if (_currentItem.rating > 0) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
            const SizedBox(width: 3),
            Text(
              _currentItem.formattedRating,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    // Año de estreno
    if (_currentItem.releaseYear.isNotEmpty) {
      items.add(
        Text(
          _currentItem.releaseYear,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    // Duración o tipo de contenido
    final runtimeStr = _formatRuntime(_currentItem.runtime);
    if (runtimeStr.isNotEmpty) {
      items.add(
        Text(
          runtimeStr,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    } else if (_currentItem.mediaType == 'tv') {
      items.add(
        const Text(
          'Serie',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    // Clasificación de edad (Insignia sutil minimalista)
    items.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white24, width: 0.7),
        ),
        child: const Text(
          '16+',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    // Resolución 4K UHD
    items.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white24, width: 0.7),
        ),
        child: const Text(
          '4K UHD',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );

    // Audio 5.1
    items.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white24, width: 0.7),
        ),
        child: const Text(
          '5.1',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    // Solo tráiler si aplica
    if (_isTrailerOnly) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0x33F59E0B),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0x88F59E0B), width: 0.8),
          ),
          child: const Text(
            'PRÓXIMAMENTE',
            style: TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
      );
    }

    final List<Widget> ribbonChildren = [];
    for (int i = 0; i < items.length; i++) {
      ribbonChildren.add(items[i]);
      if (i < items.length - 1) {
        ribbonChildren.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '•',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: ribbonChildren,
    );
  }

  Widget _buildGenresWrap() {
    if (widget.item.genres.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: widget.item.genres.map((genre) {
        return Chip(
          backgroundColor: const Color(0xFF161616),
          label: Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }

  Widget _buildFeaturesSection() {
    return const SizedBox.shrink();
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
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final moved = node.focusInDirection(TraversalDirection.down);
            if (!moved) {
              node.nextFocus();
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
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _isTrailerOnly
                ? const Color(0xFFF59E0B)
                : const Color(0xFFE50914),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _playButtonFocus.hasFocus
                  ? Colors.white
                  : Colors.transparent,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isTrailerOnly ? Icons.movie_creation_rounded : Icons.play_arrow_rounded,
                color: _isTrailerOnly ? Colors.black : Colors.white,
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                _isTrailerOnly ? 'Ver Tráiler Oficial' : 'Reproducir',
                style: TextStyle(
                  color: _isTrailerOnly ? Colors.black : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualSourceSelector({
    required String displayTitle,
    required String defaultStreamUrl,
    required List<Map<String, dynamic>> availableStreams,
    required Map<String, dynamic> streamInfo,
    required int season,
    required int episode,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF10121A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0x33E50914), width: 1.5),
      ),
      builder: (bContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: Color(0xFFE50914), size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Seleccionar Calidad / Servidor',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(bContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: availableStreams.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final s = availableStreams[index];
                      final quality = s['quality'] ?? s['name'] ?? '1080p';
                      final audio = s['audioLanguage'] ?? 'Español Latino';
                      final isSelected = s['url'] == defaultStreamUrl;

                      return Container(
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0x22E50914) : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFE50914) : Colors.white12,
                            width: 1.2,
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            '$quality • $audio',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            s['provider'] ?? 'Servidor Satelital TOM TV Ultra Rápido',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 20)
                              : const Icon(Icons.play_circle_outline_rounded, color: Colors.white54, size: 20),
                          onTap: () {
                            Navigator.pop(bContext);
                            final targetUrl = (s['url'] as String?) ?? defaultStreamUrl;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoPlayerView(
                                  videoUrl: targetUrl,
                                  title: displayTitle,
                                  mediaId: widget.item.id,
                                  posterUrl: widget.item.bestPosterUrl,
                                  backdropUrl: widget.item.bestBackdropUrl,
                                  mediaType: widget.item.mediaType,
                                  season: season,
                                  episode: episode,
                                  audioLanguage: audio,
                                  qualityLabel: quality,
                                  mediaItem: widget.item,
                                  availableStreams: availableStreams,
                                  subtitles: (streamInfo['subtitles'] as List?)
                                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              child: _TvDetailActionButton(
                onPressed: _toggleFavorite,
                icon: _isFavorite ? Icons.check_circle_rounded : Icons.add_rounded,
                label: _isFavorite ? 'En Mi Lista' : 'Mi Lista',
                activeColor: const Color(0xFF22C55E),
                isActive: _isFavorite,
              ),
            ),
            const SizedBox(width: 12),
            // Si está en modo tráiler: Botón "Avisarme cuando esté en español"
            // Si está completa: Botón "Tráiler"
            Expanded(
              child: _TvDetailActionButton(
                onPressed: _isTrailerOnly ? _toggleReminder : _playTrailer,
                icon: _isTrailerOnly
                    ? (_hasReminder ? Icons.notifications_active_rounded : Icons.notification_add_rounded)
                    : Icons.movie_creation_outlined,
                label: _isTrailerOnly
                    ? (_hasReminder ? 'Te avisaremos' : 'Avisarme (ESP)')
                    : 'Tráiler',
                activeColor: const Color(0xFFF59E0B),
                isActive: _isTrailerOnly && _hasReminder,
              ),
            ),
          ],
        ),

        // Botón adicional para elegir calidad o fuente alternativa si no es solo tráiler
        if (!_isTrailerOnly) ...[
          const SizedBox(height: 12),
          _TvDetailActionButton(
            onPressed: () => _startPlayback(selectSourceManually: true),
            icon: Icons.tune_rounded,
            label: 'Elegir Calidad / Servidor Alternativo',
            activeColor: const Color(0xFF38BDF8),
            isActive: false,
          ),
        ],

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

              return _TvEpisodeCard(
                epNum: epNum,
                epName: epName,
                overview: overview,
                runtime: runtime is int ? runtime : null,
                stillUrl: stillUrl,
                onTap: () {
                  _startPlayback(
                    season: _selectedSeason,
                    episode: epNum,
                    episodeTitle: 'T$_selectedSeason:E$epNum - $epName',
                  );
                },
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

/// Botón de acción secundaria con enfoque nítido para Smart TV
class _TvDetailActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color activeColor;
  final bool isActive;

  const _TvDetailActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.activeColor,
    this.isActive = false,
  });

  @override
  State<_TvDetailActionButton> createState() => _TvDetailActionButtonState();
}

class _TvDetailActionButtonState extends State<_TvDetailActionButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final moved = node.focusInDirection(TraversalDirection.down);
            if (!moved) {
              node.nextFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final moved = node.focusInDirection(TraversalDirection.up);
            if (!moved) {
              node.previousFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onPressed();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _isFocused ? const Color(0xFF262626) : const Color(0xFF141414),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused ? Colors.white : (widget.isActive ? widget.activeColor : const Color(0xFF333333)),
                width: _isFocused ? 2.5 : 1.5,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  color: widget.isActive ? widget.activeColor : Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isActive ? widget.activeColor : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de episodio con soporte completo para control remoto D-Pad
class _TvEpisodeCard extends StatefulWidget {
  final int epNum;
  final String epName;
  final String overview;
  final int? runtime;
  final String? stillUrl;
  final VoidCallback onTap;

  const _TvEpisodeCard({
    required this.epNum,
    required this.epName,
    required this.overview,
    this.runtime,
    this.stillUrl,
    required this.onTap,
  });

  @override
  State<_TvEpisodeCard> createState() => _TvEpisodeCardState();
}

class _TvEpisodeCardState extends State<_TvEpisodeCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
      if (_focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.4,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final moved = node.focusInDirection(TraversalDirection.down);
            if (!moved) {
              node.nextFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final moved = node.focusInDirection(TraversalDirection.up);
            if (!moved) {
              node.previousFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isFocused ? const Color(0xFF1E1E1E) : const Color(0xFF141414),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? const Color(0xFFE50914) : const Color(0xFF222222),
                width: _isFocused ? 2.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.45),
                        blurRadius: 12,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
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
                        if (widget.stillUrl != null)
                          Image.network(
                            widget.stillUrl!,
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
                              color: _isFocused
                                  ? const Color(0xFFE50914)
                                  : Colors.black.withValues(alpha: 0.6),
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
                        '${widget.epNum}. ${widget.epName}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: _isFocused ? FontWeight.bold : FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.runtime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${widget.runtime} min',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      if (widget.overview.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.overview,
                            style: const TextStyle(
                              color: Colors.white60,
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
        ),
      ),
    );
  }
}
