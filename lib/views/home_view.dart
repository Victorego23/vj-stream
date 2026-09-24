import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/playback_history_service.dart';
import '../services/update_service.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_row.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_view.dart';
import 'search_view.dart';
import 'video_player_view.dart';

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
  List<MediaItem> _trendingItems = [];
  List<MediaItem> _nowPlayingItems = [];
  List<MediaItem> _actionItems = [];
  List<MediaItem> _scifiItems = [];
  List<MediaItem> _seriesItems = [];

  // Pestañas de categoría rápida
  String _activeTab = 'Todos'; // 'Todos', 'Películas', 'Series', 'Mi Lista'
  List<WatchHistoryItem> _continueWatching = [];
  List<MediaItem> _favorites = [];

  // Cartelera Infinita dinámica sin fin
  final List<Map<String, dynamic>> _extraCategories = [];
  int _infinitePage = 1;
  bool _isLoadingMore = false;
  bool _hasMore = true;

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

  Future<void> _initApp() async {
    // Autodescubrimiento y persistencia de IP en segundo plano
    await _apiService.initBaseUrl();

    // Cargar catálogo principal e historial/favoritos en paralelo
    await Future.wait([
      _loadCatalog(),
      _loadHistoryAndFavorites(),
    ]);

    // Comprobación automática de actualización OTA en segundo plano al iniciar
    if (mounted) {
      UpdateService.checkUpdate(context, silent: true);
    }
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
    } catch (_) {}
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
      final action = categories['action'] ?? [];
      final scifi = categories['scifi'] ?? [];
      final series = categories['series'] ?? [];

      setState(() {
        _trendingItems = trending;
        _nowPlayingItems = nowPlaying;
        _actionItems = action;
        _scifiItems = scifi;
        _seriesItems = series;

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
                  'VJ STREAM',
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
                  item.title,
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

    Map<String, dynamic>? streamInfo;
    try {
      streamInfo = await _apiService.autoResolveStream(item);
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    // Filtro Anti-CAM estricto
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
            streamInfo?['message'] ??
                'Esta película solo cuenta actualmente con grabaciones de sala de cine. VJ STREAM protege la calidad de tus clientes bloqueando grabaciones de baja calidad. Estará disponible en 4K/1080p en su lanzamiento digital oficial.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
              onPressed: () => Navigator.pop(dContext),
              child: const Text('Entendido', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    final streamUrl = streamInfo?['streamUrl'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se encontró una transmisión estable para "${item.title}". Intenta nuevamente.',
          ),
          backgroundColor: const Color(0xFFE50914),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerView(
          videoUrl: streamUrl,
          title: item.title,
          mediaId: item.id,
          posterUrl: item.bestPosterUrl,
          backdropUrl: item.bestBackdropUrl,
          mediaType: item.mediaType,
          audioLanguage: streamInfo?['audioLanguage'] as String?,
          qualityLabel: streamInfo?['qualityLabel'] as String?,
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
                  'VJ STREAM',
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

    if (streamInfo?['isCinemaOnly'] == true) {
      showDialog(
        context: context,
        builder: (dContext) => AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x33E50914)),
          ),
          title: const Text('Filtro Anti-CAM Activo', style: TextStyle(color: Colors.white)),
          content: Text(
            streamInfo?['message'] ?? 'Película bloqueada por ser grabación de sala.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final streamUrl = streamInfo?['streamUrl'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo reanudar "${historyItem.title}". Intenta nuevamente.'),
          backgroundColor: const Color(0xFFE50914),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
        ),
      ),
    ).then((_) => _loadHistoryAndFavorites());
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
              'Ajustes de VJ STREAM',
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

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Negro absoluto OLED
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFE50914),
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFFE50914),
              backgroundColor: const Color(0xFF0D0D0D),
              onRefresh: _loadCatalog,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // App Bar VJ STREAM flotante
                  SliverAppBar(
                    backgroundColor: const Color(0xFF000000).withValues(alpha: 0.94),
                    elevation: 0,
                    pinned: true,
                    floating: true,
                    expandedHeight: 60,
                    title: Row(
                      children: [
                        // Logo VJ STREAM
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
                            'VJ',
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
                          'STREAM',
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
                        tooltip: 'Buscar en VJ STREAM',
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
                      SizedBox(width: isTv ? 24 : 8),
                    ],
                  ),

                  // Pestañas de Navegación Rápida
                  SliverToBoxAdapter(
                    child: _buildTabBar(isTv),
                  ),

                  // Vista cuando la pestaña activa es "Mi Lista"
                  if (_activeTab == 'Mi Lista')
                    SliverToBoxAdapter(
                      child: _buildMyListTab(isTv),
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
                      child: _buildContinueWatchingRow(isTv),
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
                    if (_activeTab == 'Todos')
                      for (final cat in _extraCategories)
                        SliverToBoxAdapter(
                          child: MediaRow(
                            title: cat['title'] as String,
                            items: (cat['items'] as List<MediaItem>),
                            onItemTap: _openDetail,
                          ),
                        ),

                    // Indicador de carga infinita al desplazarse al fondo
                    if (_isLoadingMore && _activeTab == 'Todos')
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
            ),
    );
  }

  MediaItem? _getHeroItemForTab() {
    if (_activeTab == 'Series') {
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

  Widget _buildTabBar(bool isTv) {
    final tabs = [
      {'id': 'Todos', 'label': 'Todos', 'icon': Icons.grid_view_rounded},
      {'id': 'Películas', 'label': 'Películas', 'icon': Icons.movie_rounded},
      {'id': 'Series', 'label': 'Series', 'icon': Icons.tv_rounded},
      {'id': 'Mi Lista', 'label': 'Mi Lista', 'icon': Icons.star_rounded},
    ];

    return Container(
      height: 42,
      margin: EdgeInsets.symmetric(
        horizontal: isTv ? 48 : 16,
        vertical: 8,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final id = tab['id'] as String;
          final label = tab['label'] as String;
          final icon = tab['icon'] as IconData;
          final isSelected = _activeTab == id;

          return ChoiceChip(
            showCheckmark: false,
            avatar: Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            label: Text(label),
            selected: isSelected,
            selectedColor: const Color(0xFFE50914),
            backgroundColor: const Color(0xFF141414),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? const Color(0xFFE50914) : const Color(0xFF262626),
                width: 1.2,
              ),
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() => _activeTab = id);
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
            height: isTv ? 175 : 160,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = filtered[index];
                final cardWidth = isTv ? 240.0 : 210.0;
                final image = item.backdropUrl.isNotEmpty ? item.backdropUrl : item.posterUrl;

                return InkWell(
                  onTap: () => _resumePlayback(item),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: cardWidth,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF262626)),
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
                                    color: Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38),
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () async {
                                    await PlaybackHistoryService.removeFromHistory(item.id);
                                    _loadHistoryAndFavorites();
                                  },
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
                                  value: item.progressPercentage,
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
                                      item.season != null
                                          ? '${item.title} (T${item.season}:E${item.episode})'
                                          : item.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.formattedProgress,
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
}

