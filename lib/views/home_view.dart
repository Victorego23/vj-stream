import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/playback_history_service.dart';
import '../services/coming_soon_service.dart';
import '../services/trailer_service.dart';
import '../services/update_service.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_row.dart';
import '../widgets/tv_focusable_card.dart';
import '../widgets/tv_navigation_sidebar.dart';
import '../widgets/stream_resolving_dialog.dart';
import 'detail_view.dart';
import 'search_view.dart';
import 'video_player_view.dart';
import 'live_tv_view.dart';

/// Pantalla Principal (HomeView) estilo Netflix para VJ STREAM.
/// Soporta Smart TV (Android TV D-Pad) y dispositivos móviles.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  MediaItem? _heroItem;
  MediaItem? _hoveredItem;
  List<MediaItem> _trendingItems = [];
  List<MediaItem> _nowPlayingItems = [];
  List<MediaItem> _upcomingItems = [];
  List<MediaItem> _actionItems = [];
  List<MediaItem> _scifiItems = [];
  List<MediaItem> _seriesItems = [];

  // Pestañas de categoría rápida
  String _activeTab = 'Todos'; // 'Todos', 'Fútbol & Deportes', 'Niños', 'Telenovelas', 'Canales Perú', 'Películas', 'Series', 'TV en Vivo', 'Próximamente', 'Mi Lista'
  List<WatchHistoryItem> _continueWatching = [];
  List<MediaItem> _favorites = [];

  // Categorías especializadas para Niños y Telenovelas
  List<MediaItem> _kidsMovies = [];
  List<MediaItem> _kidsCartoons = [];
  List<MediaItem> _kidsAnime = [];
  List<MediaItem> _kidsClassics = [];
  bool _isLoadingKids = false;

  List<MediaItem> _latamNovelas = [];
  List<MediaItem> _turkishNovelas = [];
  List<MediaItem> _kdramas = [];
  bool _isLoadingTelenovelas = false;

  // Cartelera Infinita dinámica sin fin
  final List<Map<String, dynamic>> _extraCategories = [];
  int _infinitePage = 1;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Explorador exhaustivo de Cartelera por Años (2000 a 2026) con actualización automática
  int? _selectedMovieYear;
  final List<MediaItem> _yearMovies = [];
  bool _isLoadingYearMovies = false;
  int _yearMoviesPage = 1;
  bool _hasMoreYearMovies = true;
  final List<int> _availableYears = List.generate(27, (i) => 2026 - i);
  Map<String, dynamic>? _activeAnnouncement;
  final GlobalKey<TvNavigationSidebarState> _tvSidebarKey = GlobalKey<TvNavigationSidebarState>();

  void _returnFocusToTvSidebar(String tabId) {
    if (_tvSidebarKey.currentState != null) {
      _tvSidebarKey.currentState!.requestFocus(tabId);
    } else {
      setState(() => _activeTab = 'Todos');
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initApp();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 500 && !_isLoadingMore && _hasMore) {
      _loadMoreCategories();
    }
  }

  Future<void> _loadMoreCategories() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final newRows = await _apiService.fetchInfiniteCategories(_infinitePage);
      if (mounted) {
        setState(() {
          if (newRows.isNotEmpty) {
            _extraCategories.addAll(newRows);
          }
          _infinitePage++;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _loadMoviesByYear(int? year, {bool loadMore = false}) async {
    if (year == null) {
      setState(() {
        _selectedMovieYear = null;
        _yearMovies.clear();
      });
      return;
    }

    if (loadMore) {
      if (_isLoadingYearMovies || !_hasMoreYearMovies) return;
      setState(() => _isLoadingYearMovies = true);
      try {
        final nextMovies = await _apiService.fetchMoviesByYear(year, page: _yearMoviesPage + 1);
        if (mounted) {
          setState(() {
            if (nextMovies.isNotEmpty) {
              _yearMovies.addAll(nextMovies);
              _yearMoviesPage++;
            } else {
              _hasMoreYearMovies = false;
            }
            _isLoadingYearMovies = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingYearMovies = false);
      }
    } else {
      setState(() {
        _selectedMovieYear = year;
        _yearMovies.clear();
        _yearMoviesPage = 1;
        _hasMoreYearMovies = true;
        _isLoadingYearMovies = true;
      });
      try {
        final movies = await _apiService.fetchMoviesByYear(year, page: 1);
        if (mounted) {
          setState(() {
            _yearMovies.addAll(movies);
            _isLoadingYearMovies = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingYearMovies = false);
      }
    }
  }

  Future<void> _initApp() async {
    // Autodescubrimiento y persistencia de IP en segundo plano
    await _apiService.initBaseUrl();

    // Cargar catálogo principal, historial/favoritos y categorías especializadas en paralelo
    await Future.wait([
      _loadCatalog(),
      _loadHistoryAndFavorites(),
      _loadKidsCatalog(),
      _loadTelenovelasCatalog(),
    ]);

    // Comprobación automática de actualización OTA en segundo plano al iniciar
    if (mounted) {
      UpdateService.checkUpdate(context, silent: true);
      _checkComingSoonReleases();
      _checkServerAnnouncement();
    }
  }

  Future<void> _checkServerAnnouncement() async {
    try {
      final origin = _apiService.serverOrigin;
      final uri = Uri.parse('$origin/api/streaming/announcement');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['success'] == true && data['announcement'] != null) {
          final ann = data['announcement'] as Map<String, dynamic>;
          if (mounted && ann['active'] == true && (ann['message'] ?? '').toString().isNotEmpty) {
            setState(() {
              _activeAnnouncement = ann;
            });
          }
        }
      }
    } catch (_) {}
  }

  /// Comprueba silenciosamente si alguna película guardada en espera de audio en español
  /// ya cuenta con versión doblada y notifica alegremente al usuario para verla de inmediato.
  Future<void> _checkComingSoonReleases() async {
    try {
      final newlyAvailable = await ComingSoonService.checkNewReleasesInSpanish(_apiService);
      if (newlyAvailable.isNotEmpty && mounted) {
        final title = newlyAvailable.first.title;
        final extra = newlyAvailable.length - 1;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.celebration_rounded, color: Colors.amberAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    extra > 0
                        ? '🎉 ¡"$title" y $extra estrenos más ya están disponibles en Español!'
                        : '🎉 ¡"$title" ya está disponible en Español Latino/Castellano!',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VER AHORA',
              textColor: Colors.white,
              onPressed: () => _openDetail(newlyAvailable.first),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadHistoryAndFavorites() async {
    try {
      final history = await PlaybackHistoryService.getWatchHistory();
      final favs = await PlaybackHistoryService.getFavorites();
      if (mounted) {
        setState(() {
          _continueWatching = history;
          _favorites = favs;
        });
      }
      // Sincronización transparente con la nube
      PlaybackHistoryService.syncWithCloud().then((_) async {
        if (!mounted) return;
        final updatedH = await PlaybackHistoryService.getWatchHistory();
        final updatedF = await PlaybackHistoryService.getFavorites();
        if (mounted) {
          setState(() {
            _continueWatching = updatedH;
            _favorites = updatedF;
          });
        }
      });
    } catch (_) {}
  }

  Future<void> _loadKidsCatalog() async {
    if (_kidsMovies.isNotEmpty && _kidsCartoons.isNotEmpty) return;
    setState(() => _isLoadingKids = true);
    try {
      final res = await _apiService.fetchKidsCatalog();
      if (mounted) {
        setState(() {
          _kidsMovies = res['movies'] ?? [];
          _kidsCartoons = res['cartoons'] ?? [];
          _kidsAnime = res['anime'] ?? [];
          _kidsClassics = res['classics'] ?? [];
          _isLoadingKids = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingKids = false);
    }
  }

  Future<void> _loadTelenovelasCatalog() async {
    if (_latamNovelas.isNotEmpty && _turkishNovelas.isNotEmpty) return;
    setState(() => _isLoadingTelenovelas = true);
    try {
      final res = await _apiService.fetchTelenovelasCatalog();
      if (mounted) {
        setState(() {
          _latamNovelas = res['latamNovelas'] ?? [];
          _turkishNovelas = res['turkishNovelas'] ?? [];
          _kdramas = res['kdramas'] ?? [];
          _isLoadingTelenovelas = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTelenovelas = false);
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _extraCategories.clear();
      _infinitePage = 1;
      _hasMore = true;
      _isLoadingMore = false;
    });
    try {
      final categories = await _apiService.fetchFullCatalog();

      final trending = categories['trending'] ?? [];
      final nowPlaying = categories['nowPlaying'] ?? [];
      final upcoming = categories['upcoming'] ?? [];
      final action = categories['action'] ?? [];
      final comedy = categories['comedy'] ?? [];
      final horror = categories['horror'] ?? [];
      final animation = categories['animation'] ?? [];
      final scifi = categories['scifi'] ?? [];
      final adventure = categories['adventure'] ?? [];
      final classics = categories['classics'] ?? [];
      final series = categories['series'] ?? [];

      final extraFromCatalog = <Map<String, dynamic>>[];
      if (comedy.isNotEmpty) extraFromCatalog.add({'title': '😂 Comedias y Risas Aseguradas', 'items': comedy});
      if (horror.isNotEmpty) extraFromCatalog.add({'title': '😱 Terror, Horror y Suspenso', 'items': horror});
      if (animation.isNotEmpty) extraFromCatalog.add({'title': '🎨 Animación y Éxitos Familiares', 'items': animation});
      if (adventure.isNotEmpty) extraFromCatalog.add({'title': '🗺️ Aventuras Épicas y Fantasía', 'items': adventure});
      if (classics.isNotEmpty) extraFromCatalog.add({'title': '👑 Grandes Éxitos y Clásicos (2000-2015)', 'items': classics});

      setState(() {
        _trendingItems = trending;
        _nowPlayingItems = nowPlaying;
        _upcomingItems = upcoming;
        _actionItems = action;
        _scifiItems = scifi;
        _seriesItems = series;
        _extraCategories.addAll(extraFromCatalog);

        // Seleccionamos la primera película con buen backdrop para el Banner Hero
        if (trending.isNotEmpty) {
          _heroItem = trending.first;
        } else if (nowPlaying.isNotEmpty) {
          _heroItem = nowPlaying.first;
        }
        _isLoading = false;
      });
      _loadHistoryAndFavorites();
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailView(item: item),
      ),
    ).then((_) => _loadHistoryAndFavorites());
  }

  Future<void> _playMedia(MediaItem item) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StreamResolvingDialog(
        title: item.title,
        posterUrl: item.bestPosterUrl,
        backdropUrl: item.bestBackdropUrl,
        mediaType: item.mediaType,
      ),
    );

    Map<String, dynamic>? streamInfo;
    try {
      streamInfo = await _apiService.autoResolveStream(item);
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    String? streamUrl = streamInfo?['streamUrl'] as String?;
    String audioLang = (streamInfo?['audioLanguage'] as String?) ?? 'Español Latino';
    String quality = (streamInfo?['qualityLabel'] as String?) ?? '1080p Full HD';
    if (streamUrl == null || streamUrl.isEmpty) {
      _openDetail(item);
      return;
    }

    final available = (streamInfo?['availableStreams'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerView(
          videoUrl: streamUrl!,
          title: item.title,
          mediaId: item.id,
          posterUrl: item.bestPosterUrl,
          backdropUrl: item.bestBackdropUrl,
          mediaType: item.mediaType,
          audioLanguage: audioLang,
          qualityLabel: quality,
          mediaItem: item,
          availableStreams: available,
          subtitles: (streamInfo?['subtitles'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        ),
      ),
    ).then((_) => _loadHistoryAndFavorites());
  }

  Future<void> _resumePlayback(WatchHistoryItem historyItem) async {
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
                Text(
                  'Reanudando ${historyItem.title}...',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Map<String, dynamic>? streamInfo;
    try {
      streamInfo = await _apiService.autoResolveStream(
        historyItem.toMediaItem(),
        season: historyItem.season ?? 1,
        episode: historyItem.episode ?? 1,
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final streamUrl = streamInfo?['streamUrl'] as String?;
    if (streamUrl != null && streamUrl.isNotEmpty) {
      final available = (streamInfo?['availableStreams'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerView(
            videoUrl: streamUrl,
            title: historyItem.title,
            mediaId: historyItem.id,
            posterUrl: historyItem.posterUrl,
            backdropUrl: historyItem.backdropUrl,
            mediaType: historyItem.mediaType,
            season: historyItem.season,
            episode: historyItem.episode,
            startPositionSeconds: historyItem.positionSeconds,
            audioLanguage: streamInfo?['audioLanguage'] as String?,
            qualityLabel: streamInfo?['qualityLabel'] as String?,
            mediaItem: MediaItem(
              id: historyItem.id,
              title: historyItem.title,
              mediaType: historyItem.mediaType,
              posterMedium: historyItem.posterUrl,
              backdropLarge: historyItem.backdropUrl,
            ),
            availableStreams: available,
            subtitles: (streamInfo?['subtitles'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        ),
      ).then((_) => _loadHistoryAndFavorites());
      return;
    }

    if (streamInfo?['isCinemaOnly'] == true) {
      showDialog(
        context: context,
        builder: (dContext) => AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x33E50914)),
          ),
          title: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: Colors.amber, size: 22),
              SizedBox(width: 8),
              Text(
                'Filtro Anti-CAM Activo',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            streamInfo?['message'] ?? 'Película disponible solo en grabación de cine.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudo reanudar "${historyItem.title}". Intenta nuevamente.'),
        backgroundColor: const Color(0xFFE50914),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SearchView(),
      ),
    );
  }

  void _showConfigDialog() {
    final controller = TextEditingController(text: _apiService.baseUrl);
    final homeContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x14FFFFFF)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0x26E50914),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.settings_rounded,
                color: Color(0xFFE50914),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Ajustes de TOM TV',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Panel / Tarjeta de Información de Versión y Actualizaciones OTA
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0x1AFFFFFF),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFE50914),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Información del Sistema',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x2622C55E),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0x4D22C55E),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: Color(0xFF22C55E), size: 6),
                                SizedBox(width: 4),
                                Text(
                                  'Oficial',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Versión actual: v${UpdateService.currentVersion} (Build ${UpdateService.currentVersionCode})',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sistema In-App OTA y reproductor de alta velocidad.',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF262626),
                            side: const BorderSide(color: Color(0xFFE50914), width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(
                            Icons.system_update_rounded,
                            color: Color(0xFFE50914),
                            size: 18,
                          ),
                          label: const Text(
                            'Buscar actualizaciones',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            UpdateService.checkUpdate(homeContext, silent: false);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Sección Servidor y Backend en la Nube
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1A22C55E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x4D22C55E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_done_rounded, color: Color(0xFF22C55E), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Servidor en la Nube 24/7',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x3322C55E),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'EN LÍNEA',
                              style: TextStyle(color: Color(0xFF22C55E), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Conectado a Render Cloud sin necesidad de ingresar IPs ni encender la PC.',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _apiService.baseUrl,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Opciones avanzadas de red (opcional)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Opciones avanzadas de servidor',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    children: [
                      const SizedBox(height: 6),
                      TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.dns_rounded, color: Colors.white54, size: 18),
                          filled: true,
                          fillColor: const Color(0xFF0F0F0F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE50914), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          labelText: 'URL personalizada del Backend',
                          labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.restore_rounded, size: 14, color: Colors.white70),
                          label: const Text('Restablecer a Nube 24/7', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          onPressed: () {
                            controller.text = ApiService.defaultCloudUrl;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.save_rounded, size: 16),
            onPressed: () {
              _apiService.setBaseUrl(controller.text.trim());
              Navigator.pop(dialogContext);
              _loadCatalog();
            },
            label: const Text('Guardar y Recargar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Si el usuario está en una subvista de TV en vivo, regresar a su pestaña principal
        if (_activeTab == 'TV Infantil') {
          setState(() => _activeTab = 'Niños');
          return;
        }
        if (_activeTab == 'TV Telenovelas') {
          setState(() => _activeTab = 'Telenovelas');
          return;
        }
        // Si el usuario está en cualquier otra pestaña, regresar a Todos
        if (_activeTab != 'Películas' && _activeTab != 'Todos') {
          setState(() {
            _activeTab = 'Todos';
          });
          if (_scrollController.hasClients) {
            _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
          return;
        }
        final shouldExit = await _showExitConfirmDialog();
        if (shouldExit == true) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000), // Negro absoluto OLED
        bottomNavigationBar: isTv ? null : _buildMobileBottomBar(),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE50914),
                ),
              )
            : (isTv ? _buildTvLayout() : _buildMobileLayout()),
      ),
    );
  }

  // ===========================================================================
  // BARRA DE NAVEGACIÓN INFERIOR FLOTANTE DE CRISTAL (MÓVIL / TABLET)
  // ===========================================================================
  Widget _buildMobileBottomBar() {
    final navItems = [
      {'id': 'Todos', 'label': 'Inicio', 'icon': Icons.home_rounded},
      {'id': 'TV en Vivo', 'label': 'TV & Deportes', 'icon': Icons.live_tv_rounded},
      {'id': 'Niños', 'label': 'Niños', 'icon': Icons.child_care_rounded},
      {'id': 'Telenovelas', 'label': 'Novelas', 'icon': Icons.favorite_rounded},
      {'id': 'Mi Lista', 'label': 'Mi Lista', 'icon': Icons.star_rounded},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF5141724), Color(0xF5080A12)],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0x3DFFFFFF), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 28,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFFE50914).withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: navItems.map((item) {
              final id = item['id'] as String;
              final label = item['label'] as String;
              final icon = item['icon'] as IconData;
              final isSelected = _activeTab == id;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _activeTab = id;
                    _hoveredItem = null;
                  });
                  if (id == 'Niños') _loadKidsCatalog();
                  if (id == 'Telenovelas') _loadTelenovelasCatalog();
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [Color(0xFFE50914), Color(0xFFB80610)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE50914).withValues(alpha: 0.65),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: isSelected ? Colors.white : const Color(0x9EFFFFFF),
                        size: 21,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0x9EFFFFFF),
                          fontSize: 10.5,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          letterSpacing: isSelected ? 0.2 : 0.0,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // LAYOUT PROFESIONAL SMART TV (SIDEBAR LATERAL + CONTENIDO EXPANDIDO 4K)
  // ===========================================================================
  Widget _buildTvLayout() {
    return Row(
      children: [
        // Sidebar lateral colapsable estilo Netflix / Android TV
        TvNavigationSidebar(
          key: _tvSidebarKey,
          activeTabId: _activeTab,
          onSelectTab: (tabId) {
            setState(() {
              _activeTab = tabId;
              _hoveredItem = null;
            });
            if (tabId == 'Niños') _loadKidsCatalog();
            if (tabId == 'Telenovelas') _loadTelenovelasCatalog();
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          },
          onSearch: _openSearch,
          onSettings: _showConfigDialog,
          onRefresh: _loadCatalog,
        ),

        // Área de contenido a pantalla completa
        Expanded(
          child: _buildTvContentArea(),
        ),
      ],
    );
  }

  Widget _buildTvContentArea() {
    // Si la pestaña seleccionada es TV en vivo, ocupar 100% del área con la grilla optimizada
    if (_activeTab == 'Fútbol & Deportes') {
      return LiveTvView(
        initialCategory: 'Deportes',
        onBackToMovies: () => _returnFocusToTvSidebar('Fútbol & Deportes'),
      );
    }
    if (_activeTab == 'Canales Perú') {
      return LiveTvView(
        initialCategory: '🇵🇪 Canales Peruanos',
        onBackToMovies: () => _returnFocusToTvSidebar('Canales Perú'),
      );
    }
    if (_activeTab == 'TV en Vivo') {
      return LiveTvView(
        onBackToMovies: () => _returnFocusToTvSidebar('TV en Vivo'),
      );
    }
    if (_activeTab == 'TV Infantil') {
      return LiveTvView(
        initialCategory: 'Infantil',
        onBackToMovies: () => _returnFocusToTvSidebar('Niños'),
      );
    }
    if (_activeTab == 'TV Telenovelas') {
      return LiveTvView(
        initialCategory: 'Telenovelas',
        onBackToMovies: () => _returnFocusToTvSidebar('Telenovelas'),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFE50914),
      backgroundColor: const Color(0xFF0D0D0D),
      onRefresh: _loadCatalog,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Banner de Aviso / Notificación enviado desde el Panel Administrativo
          if (_activeAnnouncement != null)
            SliverToBoxAdapter(
              child: _buildAnnouncementBanner(true),
            ),

          // Selector horizontal de Años 2000 - 2026 cuando está en la pestaña "Películas"
          if (_activeTab == 'Películas')
            SliverToBoxAdapter(
              child: _buildYearSelectorBar(true),
            ),

          if (_activeTab == 'Películas' && _selectedMovieYear != null)
            SliverToBoxAdapter(
              child: _buildYearMoviesGrid(true),
            )
          else if (_activeTab == 'Niños')
            SliverToBoxAdapter(
              child: _buildKidsTab(true),
            )
          else if (_activeTab == 'Telenovelas')
            SliverToBoxAdapter(
              child: _buildTelenovelasTab(true),
            )
          else if (_activeTab == 'Mi Lista')
            SliverToBoxAdapter(
              child: _buildMyListTab(true),
            )
          else if (_activeTab == 'Próximamente')
            SliverToBoxAdapter(
              child: _buildComingSoonTab(true),
            )
          else ...[
            // Hero Banner destacado superior dinámico
            if (_getHeroItemForTab() != null)
              SliverToBoxAdapter(
                child: HeroBanner(
                  item: _hoveredItem ?? _getHeroItemForTab()!,
                  onPlay: () => _playMedia(_hoveredItem ?? _getHeroItemForTab()!),
                  onDetails: () => _openDetail(_hoveredItem ?? _getHeroItemForTab()!),
                ),
              ),

            // Fila: Continuar Viendo
            SliverToBoxAdapter(
              child: _buildContinueWatchingRow(true),
            ),

            // Fila: Mi Lista (solo en tab Todos si hay favoritos)
            if (_activeTab == 'Todos' && _favorites.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: '⭐ Mi Lista Guardada',
                  items: _favorites,
                  onItemTap: _openDetail,
                  onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                ),
              ),

            // Fila destacada: Próximamente en Español (Solo Tráiler)
            if (_upcomingItems.isNotEmpty && (_activeTab == 'Todos' || _activeTab == 'Películas'))
              SliverToBoxAdapter(
                child: MediaRow(
                  title: '🍿 Próximamente en Español (Solo Tráiler)',
                  items: _upcomingItems,
                  onItemTap: _openDetail,
                  onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                ),
              ),

            // Filas según la pestaña activa
            if (_activeTab == 'Todos' || _activeTab == 'Películas') ...[
              if (_nowPlayingItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '🍿 Estrenos de Cine (Calidad Limpia)',
                    items: _nowPlayingItems,
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),
              if (_trendingItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: _activeTab == 'Películas'
                        ? '🔥 Películas en Tendencia'
                        : '🔥 Tendencias de la Semana',
                    items: _activeTab == 'Películas'
                        ? _trendingItems.where((i) => i.mediaType == 'movie').toList()
                        : _trendingItems,
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),
              if (_actionItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '💥 Acción y Adrenalina',
                    items: _actionItems,
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),
              if (_scifiItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '🚀 Ciencia Ficción y Fantasía',
                    items: _scifiItems,
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),
            ],

            if (_activeTab == 'Todos' || _activeTab == 'Series') ...[
              if (_seriesItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '📺 Series Populares (Latino / Castellano)',
                    items: _seriesItems,
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),
              if (_activeTab == 'Series' && _trendingItems.any((i) => i.mediaType == 'tv'))
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '🔥 Series en Tendencia',
                    items: _trendingItems.where((i) => i.mediaType == 'tv').toList(),
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),
            ],

            // Filas dinámicas infinitas de Cartelera sin fin
            if (_activeTab == 'Todos' || (_activeTab == 'Películas' && _selectedMovieYear == null))
              for (final cat in _extraCategories)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: cat['title'] as String,
                    items: (cat['items'] as List<MediaItem>),
                    onItemTap: _openDetail,
                    onItemFocus: (focused) => setState(() => _hoveredItem = focused),
                  ),
                ),

            // Indicador de carga infinita al desplazarse al fondo
            if (_isLoadingMore && (_activeTab == 'Todos' || _activeTab == 'Películas'))
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                      ),
                    ),
                  ),
                ),
              ),
          ],

          const SliverToBoxAdapter(
            child: SizedBox(height: 70),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LAYOUT MÓVIL (APP BAR FLOTANTE + PESTAÑAS HORIZONTALES TÁCTILES)
  // ===========================================================================
  Widget _buildMobileLayout() {
    return RefreshIndicator(
      color: const Color(0xFFE50914),
      backgroundColor: const Color(0xFF0D0D0D),
      onRefresh: _loadCatalog,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App Bar TOM TV flotante para móvil
          SliverAppBar(
            backgroundColor: const Color(0xFF000000).withValues(alpha: 0.94),
            elevation: 0,
            pinned: true,
            floating: true,
            expandedHeight: 60,
            title: Row(
              children: [
                // Logo TOM TV
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE50914), Color(0xFF990000)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Text(
                    'TOM',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Buscar en TOM TV',
                icon: const Icon(Icons.search, color: Colors.white, size: 24),
                onPressed: _openSearch,
              ),
              IconButton(
                tooltip: 'Recargar catálogo',
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _loadCatalog,
              ),
              IconButton(
                tooltip: 'Configurar servidor',
                icon: const Icon(Icons.settings, color: Colors.white70),
                onPressed: _showConfigDialog,
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Banner de Aviso / Notificación enviado desde el Panel Administrativo
          if (_activeAnnouncement != null)
            SliverToBoxAdapter(
              child: _buildAnnouncementBanner(false),
            ),

          // Pestañas de Navegación Rápida
          SliverToBoxAdapter(
            child: _buildTabBar(false),
          ),

          // Selector horizontal de Años 2000 - 2026 cuando está en la pestaña "Películas"
          if (_activeTab == 'Películas')
            SliverToBoxAdapter(
              child: _buildYearSelectorBar(false),
            ),

          // Vista cuando la pestaña activa es "Fútbol & Deportes"
          if (_activeTab == 'Fútbol & Deportes')
            SliverFillRemaining(
              hasScrollBody: true,
              child: LiveTvView(
                initialCategory: 'Deportes',
                onBackToMovies: () {
                  setState(() => _activeTab = 'Todos');
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  }
                },
              ),
            )
          // Vista cuando la pestaña activa es "Canales Perú"
          else if (_activeTab == 'Canales Perú')
            SliverFillRemaining(
              hasScrollBody: true,
              child: LiveTvView(
                initialCategory: '🇵🇪 Canales Peruanos',
                onBackToMovies: () {
                  setState(() => _activeTab = 'Todos');
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  }
                },
              ),
            )
          // Vista cuando la pestaña activa es "TV en Vivo"
          else if (_activeTab == 'TV en Vivo')
            SliverFillRemaining(
              hasScrollBody: true,
              child: LiveTvView(
                onBackToMovies: () {
                  setState(() => _activeTab = 'Todos');
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  }
                },
              ),
            )
          // Vista cuando la pestaña activa es "TV Infantil"
          else if (_activeTab == 'TV Infantil')
            SliverFillRemaining(
              hasScrollBody: true,
              child: LiveTvView(
                initialCategory: 'Infantil',
                onBackToMovies: () {
                  setState(() => _activeTab = 'Niños');
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  }
                },
              ),
            )
          // Vista cuando la pestaña activa es "TV Telenovelas"
          else if (_activeTab == 'TV Telenovelas')
            SliverFillRemaining(
              hasScrollBody: true,
              child: LiveTvView(
                initialCategory: 'Telenovelas',
                onBackToMovies: () {
                  setState(() => _activeTab = 'Telenovelas');
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  }
                },
              ),
            )
          // Vista cuando la pestaña activa es "Niños"
          else if (_activeTab == 'Niños')
            SliverToBoxAdapter(
              child: _buildKidsTab(false),
            )
          // Vista cuando la pestaña activa es "Telenovelas"
          else if (_activeTab == 'Telenovelas')
            SliverToBoxAdapter(
              child: _buildTelenovelasTab(false),
            )
          // Vista cuando la pestaña activa es "Mi Lista"
          else if (_activeTab == 'Mi Lista')
            SliverToBoxAdapter(
              child: _buildMyListTab(false),
            )
          // Vista cuando la pestaña activa es "Próximamente"
          else if (_activeTab == 'Próximamente')
            SliverToBoxAdapter(
              child: _buildComingSoonTab(false),
            )
          // Vista cuando seleccionó un año específico en Películas
          else if (_activeTab == 'Películas' && _selectedMovieYear != null)
            SliverToBoxAdapter(
              child: _buildYearMoviesGrid(false),
            )
          else ...[
            // Hero Banner destacado superior
            if (_getHeroItemForTab() != null)
              SliverToBoxAdapter(
                child: HeroBanner(
                  item: _getHeroItemForTab()!,
                  onPlay: () => _playMedia(_getHeroItemForTab()!),
                  onDetails: () => _openDetail(_getHeroItemForTab()!),
                ),
              ),

            // Fila: Continuar Viendo
            SliverToBoxAdapter(
              child: _buildContinueWatchingRow(false),
            ),

            // Fila: Mi Lista (solo en tab Todos si hay favoritos)
            if (_activeTab == 'Todos' && _favorites.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: '⭐ Mi Lista Guardada',
                  items: _favorites,
                  onItemTap: _openDetail,
                ),
              ),

            // Fila destacada: Próximamente en Español (Solo Tráiler)
            if (_upcomingItems.isNotEmpty && (_activeTab == 'Todos' || _activeTab == 'Películas'))
              SliverToBoxAdapter(
                child: MediaRow(
                  title: '🍿 Próximamente en Español (Solo Tráiler)',
                  items: _upcomingItems,
                  onItemTap: _openDetail,
                ),
              ),

            // Filas según la pestaña activa
            if (_activeTab == 'Todos' || _activeTab == 'Películas') ...[
              if (_nowPlayingItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '🍿 Estrenos de Cine (Calidad Limpia)',
                    items: _nowPlayingItems,
                    onItemTap: _openDetail,
                  ),
                ),
              if (_trendingItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: _activeTab == 'Películas'
                        ? '🔥 Películas en Tendencia'
                        : '🔥 Tendencias de la Semana',
                    items: _activeTab == 'Películas'
                        ? _trendingItems.where((i) => i.mediaType == 'movie').toList()
                        : _trendingItems,
                    onItemTap: _openDetail,
                  ),
                ),
              if (_actionItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '💥 Acción y Adrenalina',
                    items: _actionItems,
                    onItemTap: _openDetail,
                  ),
                ),
              if (_scifiItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '🚀 Ciencia Ficción y Fantasía',
                    items: _scifiItems,
                    onItemTap: _openDetail,
                  ),
                ),
            ],

            if (_activeTab == 'Todos' || _activeTab == 'Series') ...[
              if (_seriesItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '📺 Series Populares (Latino / Castellano)',
                    items: _seriesItems,
                    onItemTap: _openDetail,
                  ),
                ),
              if (_activeTab == 'Series' && _trendingItems.any((i) => i.mediaType == 'tv'))
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: '🔥 Series en Tendencia',
                    items: _trendingItems.where((i) => i.mediaType == 'tv').toList(),
                    onItemTap: _openDetail,
                  ),
                ),
            ],

            // Filas dinámicas infinitas de Cartelera sin fin
            if (_activeTab == 'Todos' || (_activeTab == 'Películas' && _selectedMovieYear == null))
              for (final cat in _extraCategories)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: cat['title'] as String,
                    items: (cat['items'] as List<MediaItem>),
                    onItemTap: _openDetail,
                  ),
                ),

            // Indicador de carga infinita al desplazarse al fondo
            if (_isLoadingMore && (_activeTab == 'Todos' || _activeTab == 'Películas'))
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                      ),
                    ),
                  ),
                ),
              ),
          ],

          // Margen inferior holgado para evitar recortes en TV y móvil
          const SliverToBoxAdapter(
            child: SizedBox(height: 70),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showExitConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dContext) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0x26E50914),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFE50914), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              '¿Salir de TOM TV?',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas salir de la aplicación?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dContext, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dContext, true),
            child: const Text('Salir', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  MediaItem? _getHeroItemForTab() {
    if (_activeTab == 'Niños') {
      if (_kidsMovies.isNotEmpty) return _kidsMovies.first;
      if (_kidsCartoons.isNotEmpty) return _kidsCartoons.first;
    } else if (_activeTab == 'Telenovelas') {
      if (_latamNovelas.isNotEmpty) return _latamNovelas.first;
      if (_turkishNovelas.isNotEmpty) return _turkishNovelas.first;
    } else if (_activeTab == 'Series') {
      if (_seriesItems.isNotEmpty) return _seriesItems.first;
      final seriesInTrending = _trendingItems.where((i) => i.mediaType == 'tv');
      if (seriesInTrending.isNotEmpty) return seriesInTrending.first;
    } else if (_activeTab == 'Películas') {
      if (_nowPlayingItems.isNotEmpty) return _nowPlayingItems.first;
      final movieInTrending = _trendingItems.where((i) => i.mediaType == 'movie');
      if (movieInTrending.isNotEmpty) return movieInTrending.first;
    }
    return _heroItem;
  }

  Widget _buildAnnouncementBanner(bool isTv) {
    if (_activeAnnouncement == null) return const SizedBox.shrink();

    final title = (_activeAnnouncement!['title'] ?? 'Aviso de TOM TV').toString();
    final message = (_activeAnnouncement!['message'] ?? '').toString();
    final type = (_activeAnnouncement!['type'] ?? 'info').toString();

    Color bgColor1 = const Color(0xFFE50914);
    Color bgColor2 = const Color(0xFF990000);
    IconData iconData = Icons.campaign_rounded;

    if (type == 'warning') {
      bgColor1 = const Color(0xFFD97706);
      bgColor2 = const Color(0xFF92400E);
      iconData = Icons.warning_amber_rounded;
    } else if (type == 'urgent') {
      bgColor1 = const Color(0xFFDC2626);
      bgColor2 = const Color(0xFF7F1D1D);
      iconData = Icons.report_problem_rounded;
    }

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isTv ? 48 : 16,
        vertical: 8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [bgColor1, bgColor2]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: bgColor1.withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(iconData, color: Colors.white, size: isTv ? 28 : 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: isTv ? 14 : 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: isTv ? 13 : 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
            onPressed: () {
              setState(() => _activeAnnouncement = null);
            },
            tooltip: 'Cerrar aviso',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isTv) {
    final tabs = [
      {'id': 'Todos', 'label': 'Todos', 'icon': Icons.grid_view_rounded},
      {'id': 'Fútbol & Deportes', 'label': '⚽ Fútbol & Deportes', 'icon': Icons.sports_soccer_rounded},
      {'id': 'Niños', 'label': '👶 Niños & Dibujos', 'icon': Icons.child_care_rounded},
      {'id': 'Telenovelas', 'label': '🌹 Telenovelas', 'icon': Icons.favorite_rounded},
      {'id': 'Canales Perú', 'label': '🇵🇪 Canales Perú', 'icon': Icons.live_tv_rounded},
      {'id': 'Películas', 'label': 'Películas', 'icon': Icons.movie_rounded},
      {'id': 'Series', 'label': 'Series', 'icon': Icons.tv_rounded},
      {'id': 'TV en Vivo', 'label': 'TV en Vivo (1300+)', 'icon': Icons.public_rounded},
      {'id': 'Próximamente', 'label': 'Próximamente', 'icon': Icons.upcoming_rounded},
      {'id': 'Mi Lista', 'label': 'Mi Lista', 'icon': Icons.star_rounded},
    ];

    return Container(
      height: 44,
      margin: EdgeInsets.symmetric(
        horizontal: isTv ? 48 : 16,
        vertical: 8,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        cacheExtent: 500,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final id = tab['id'] as String;
          final label = tab['label'] as String;
          final icon = tab['icon'] as IconData;
          final isSelected = _activeTab == id;

          return _TvTabChip(
            label: label,
            icon: icon,
            isSelected: isSelected,
            onSelected: () {
              setState(() => _activeTab = id);
              if (id == 'Niños') _loadKidsCatalog();
              if (id == 'Telenovelas') _loadTelenovelasCatalog();
              if (_scrollController.hasClients && _scrollController.offset > 0) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildContinueWatchingRow(bool isTv) {
    if (_continueWatching.isEmpty) return const SizedBox.shrink();

    final filtered = _continueWatching.where((item) {
      if (_activeTab == 'Películas') return item.mediaType == 'movie';
      if (_activeTab == 'Series') return item.mediaType == 'tv';
      return true;
    }).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0, vertical: 8.0),
            child: const Row(
              children: [
                Icon(Icons.history_rounded, color: Color(0xFFE50914), size: 20),
                SizedBox(width: 8),
                Text(
                  'Continuar Viendo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: isTv ? 180 : 165,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 600,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = filtered[index];
                final cardWidth = isTv ? 240.0 : 210.0;

                return _TvContinueWatchingCard(
                  item: item,
                  width: cardWidth,
                  onTap: () => _resumePlayback(item),
                  onRemove: () async {
                    await PlaybackHistoryService.removeFromHistory(item.id);
                    _loadHistoryAndFavorites();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyListTab(bool isTv) {
    if (_favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_border_rounded,
                  color: Color(0xFFE50914),
                  size: 54,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Tu lista está vacía',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Presiona "+ Mi Lista" en cualquier película o serie para tenerla a mano aquí.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final cardWidth = isTv ? 160.0 : 130.0;
    final cardHeight = isTv ? 240.0 : 195.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                'Películas y Series Guardadas (${_favorites.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: _favorites.map((item) {
              return TvFocusableCard(
                item: item,
                width: cardWidth,
                height: cardHeight,
                onTap: () => _openDetail(item),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildComingSoonTab(bool isTv) {
    if (_upcomingItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.movie_creation_rounded,
                  color: Color(0xFFF59E0B),
                  size: 54,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Cargando cartelera de próximos estrenos...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cardWidth = isTv ? 160.0 : 130.0;
    final cardHeight = isTv ? 240.0 : 195.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner informativo superior de la pestaña
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF261D07), Color(0xFF141109)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.upcoming_rounded, color: Color(0xFFF59E0B), size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Próximamente en Español • Tráilers Oficiales',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Títulos actualmente en cines o en idioma original (inglés). Mira el tráiler oficial y activa recordatorios: al detectarse audio en español se integrarán automáticamente para reproducir.',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Título de conteo
          Row(
            children: [
              const Icon(Icons.movie_creation_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              Text(
                'Cartelera y Estrenos en Tráiler (${_upcomingItems.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid de películas en trailer
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: _upcomingItems.map((item) {
              return SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: TvFocusableCard(
                  item: item,
                  width: cardWidth,
                  height: cardHeight,
                  onTap: () => _openDetail(item),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLiveTvShortcutBanner({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onTap,
    required bool isTv,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTv ? 48.0 : 16.0,
        vertical: 12.0,
      ),
      child: _TvActionCard(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isTv ? 24.0 : 16.0,
            vertical: isTv ? 18.0 : 14.0,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: isTv ? 32 : 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTv ? 18 : 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isTv ? 13 : 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'VER EN VIVO',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: isTv ? 12 : 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKidsTab(bool isTv) {
    if (_isLoadingKids && _kidsMovies.isEmpty && _kidsCartoons.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveTvShortcutBanner(
          title: 'Canales Infantiles en Vivo 24/7',
          subtitle: 'Cartoon Network, Nickelodeon, Disney, Bob Esponja, Hey Arnold, Rugrats...',
          badgeText: 'EN VIVO',
          icon: Icons.tv_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
          ),
          onTap: () {
            setState(() => _activeTab = 'TV Infantil');
          },
          isTv: isTv,
        ),
        if (_kidsMovies.isNotEmpty)
          MediaRow(
            title: '🎨 Películas Animadas y Familiares (Disney, Pixar, DreamWorks)',
            items: _kidsMovies,
            onItemTap: _openDetail,
          ),
        if (_kidsCartoons.isNotEmpty)
          MediaRow(
            title: '📺 Dibujos Animados y Caricaturas Populares',
            items: _kidsCartoons,
            onItemTap: _openDetail,
          ),
        if (_kidsAnime.isNotEmpty)
          MediaRow(
            title: '⚡ Anime Infantil y Aventuras',
            items: _kidsAnime,
            onItemTap: _openDetail,
          ),
        if (_kidsClassics.isNotEmpty)
          MediaRow(
            title: '👑 Grandes Clásicos de la Animación',
            items: _kidsClassics,
            onItemTap: _openDetail,
          ),
      ],
    );
  }

  Widget _buildTelenovelasTab(bool isTv) {
    if (_isLoadingTelenovelas && _latamNovelas.isEmpty && _turkishNovelas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveTvShortcutBanner(
          title: 'Canales de Telenovelas 24/7 en Vivo',
          subtitle: 'Kanal D Drama, RCN Novelas, TNT Novelas, Pluto TV Novelas...',
          badgeText: 'EN VIVO',
          icon: Icons.favorite_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFFBE185D), Color(0xFF881337)],
          ),
          onTap: () {
            setState(() => _activeTab = 'TV Telenovelas');
          },
          isTv: isTv,
        ),
        if (_latamNovelas.isNotEmpty)
          MediaRow(
            title: '🌹 Grandes Telenovelas Latinoamericanas',
            items: _latamNovelas,
            onItemTap: _openDetail,
          ),
        if (_turkishNovelas.isNotEmpty)
          MediaRow(
            title: '🇹🇷 Novelas Turcas en Español (Dobladas)',
            items: _turkishNovelas,
            onItemTap: _openDetail,
          ),
        if (_kdramas.isNotEmpty)
          MediaRow(
            title: '💖 Dramas Románticos y K-Dramas',
            items: _kdramas,
            onItemTap: _openDetail,
          ),
      ],
    );
  }

  Widget _buildYearSelectorBar(bool isTv) {
    return Container(
      height: 42,
      margin: EdgeInsets.symmetric(
        horizontal: isTv ? 48 : 16,
        vertical: 6,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _availableYears.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _selectedMovieYear == null;
            return ChoiceChip(
              showCheckmark: false,
              label: const Text('✨ Todas las Colecciones (2000 - 2026)'),
              selected: isSelected,
              selectedColor: const Color(0xFFE50914),
              backgroundColor: const Color(0xFF141414),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? const Color(0xFFE50914) : const Color(0xFF333333),
                  width: 1.1,
                ),
              ),
              onSelected: (_) => _loadMoviesByYear(null),
            );
          }

          final year = _availableYears[index - 1];
          final isSelected = _selectedMovieYear == year;
          final isNew = year >= 2025;

          return ChoiceChip(
            showCheckmark: false,
            avatar: isNew ? const Icon(Icons.star_rounded, size: 16, color: Colors.amber) : null,
            label: Text(year.toString()),
            selected: isSelected,
            selectedColor: const Color(0xFFE50914),
            backgroundColor: const Color(0xFF141414),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : (isNew ? Colors.amber : Colors.white70),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected ? const Color(0xFFE50914) : (isNew ? const Color(0x66FFC107) : const Color(0xFF262626)),
                width: 1.1,
              ),
            ),
            onSelected: (selected) {
              if (selected) {
                _loadMoviesByYear(year);
              } else {
                _loadMoviesByYear(null);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildYearMoviesGrid(bool isTv) {
    if (_isLoadingYearMovies && _yearMovies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
        ),
      );
    }

    if (_yearMovies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            'No se encontraron películas para el año $_selectedMovieYear.',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ),
      );
    }

    final cardWidth = isTv ? 160.0 : 130.0;
    final cardHeight = isTv ? 240.0 : 195.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 16.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'AÑO $_selectedMovieYear',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Cartelera Completa de Películas ($_selectedMovieYear)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${_yearMovies.length} títulos',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: _yearMovies.map((movie) {
              return TvFocusableCard(
                item: movie,
                width: cardWidth,
                height: cardHeight,
                onTap: () => _openDetail(movie),
              );
            }).toList(),
          ),
          if (_hasMoreYearMovies)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _isLoadingYearMovies
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.5),
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E1E1E),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF333333)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                        label: Text('Cargar más películas de $_selectedMovieYear'),
                        onPressed: () => _loadMoviesByYear(_selectedMovieYear, loadMore: true),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip de pestaña con enfoque y navegación D-Pad para Smart TV
class _TvTabChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onSelected;

  const _TvTabChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  State<_TvTabChip> createState() => _TvTabChipState();
}

class _TvTabChipState extends State<_TvTabChip> {
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
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
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
            widget.onSelected();
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
          _focusNode.requestFocus();
          widget.onSelected();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: widget.isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFFE50914), Color(0xFFB80610)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : (_isFocused
                      ? const LinearGradient(
                          colors: [Color(0xFF2A2E3D), Color(0xFF1E212B)],
                        )
                      : null),
              color: !widget.isSelected && !_isFocused ? const Color(0x1FFFFFFF) : null,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : (widget.isSelected ? const Color(0xFFFF4D4D) : const Color(0x26FFFFFF)),
                width: _isFocused ? 2.0 : 1.1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.isSelected
                            ? const Color(0xFFE50914).withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : (widget.isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFE50914).withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.isSelected || _isFocused ? Colors.white : const Color(0xB3FFFFFF),
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isSelected || _isFocused ? Colors.white : const Color(0xB3FFFFFF),
                    fontWeight: widget.isSelected || _isFocused ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 13,
                    letterSpacing: widget.isSelected ? 0.2 : 0.0,
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

/// Tarjeta de historial "Continuar Viendo" con soporte completo para control remoto de TV
class _TvContinueWatchingCard extends StatefulWidget {
  final WatchHistoryItem item;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _TvContinueWatchingCard({
    required this.item,
    required this.width,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_TvContinueWatchingCard> createState() => _TvContinueWatchingCardState();
}

class _TvContinueWatchingCardState extends State<_TvContinueWatchingCard> {
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
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
        final inner = Scrollable.maybeOf(context);
        if (inner != null) {
          final outer = Scrollable.maybeOf(inner.context);
          if (outer != null) {
            Scrollable.ensureVisible(
              inner.context,
              alignment: 0.35,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
            );
          }
        }
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
    final image = widget.item.backdropUrl.isNotEmpty ? widget.item.backdropUrl : widget.item.posterUrl;

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
          scale: _isFocused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.width,
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? const Color(0xFFE50914) : const Color(0xFF262626),
                width: _isFocused ? 3 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (image.isNotEmpty)
                        Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF222222),
                            child: const Center(
                              child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
                            ),
                          ),
                        )
                      else
                        Container(
                          color: const Color(0xFF222222),
                          child: const Center(
                            child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
                          ),
                        ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xB3000000)],
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isFocused
                                ? const Color(0xFFE50914)
                                : Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: widget.onRemove,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: widget.item.progressPercentage,
                          minHeight: 4,
                          backgroundColor: const Color(0x66333333),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.season != null
                                  ? '${widget.item.title} (T${widget.item.season}:E${widget.item.episode})'
                                  : widget.item.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: _isFocused ? FontWeight.bold : FontWeight.w600,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.item.formattedProgress,
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.replay_rounded, color: Colors.white54, size: 16),
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

/// Tarjeta de acción interactiva enfocable en Android TV y táctil en móviles
class _TvActionCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _TvActionCard({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_TvActionCard> createState() => _TvActionCardState();
}

class _TvActionCardState extends State<_TvActionCard> {
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
          alignment: 0.35,
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
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}


