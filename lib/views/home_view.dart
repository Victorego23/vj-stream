import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_row.dart';
import 'detail_view.dart';
import 'search_view.dart';
import 'video_player_view.dart';
import '../services/update_service.dart';

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

    // Cargar catálogo principal
    await _loadCatalog();

    // Comprobación automática de actualización OTA en segundo plano al iniciar
    if (mounted) {
      UpdateService.checkUpdate(context, silent: true);
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
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailView(item: item),
      ),
    );
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

    String? streamUrl;
    try {
      final streamInfo = await _apiService.autoResolveStream(item);
      streamUrl = streamInfo?['streamUrl'] as String?;
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

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
          videoUrl: streamUrl!,
          title: item.title,
        ),
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

                // Sección Servidor y Backend
                const Text(
                  'Servidor Backend (Node.js)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '• Emulador Android: http://10.0.2.2:3000/api/streaming\n• Smart TV (LAN): http://IP_DE_TU_PC:3000/api/streaming\n• Web / PC: http://localhost:3000/api/streaming',
                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
                ),
                const SizedBox(height: 10),
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
                    labelText: 'Base URL',
                    labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    backgroundColor: const Color(0xFF000000).withValues(alpha: 0.92),
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

                  // Hero Banner destacado superior
                  if (_heroItem != null)
                    SliverToBoxAdapter(
                      child: HeroBanner(
                        item: _heroItem!,
                        onPlay: () => _playMedia(_heroItem!),
                        onDetails: () => _openDetail(_heroItem!),
                      ),
                    ),

                  // Espaciado antes de las filas
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 12),
                  ),

                  // Fila 1: Tendencias de la Semana
                  if (_trendingItems.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaRow(
                        title: '🔥 Tendencias de la Semana',
                        items: _trendingItems,
                        onItemTap: _openDetail,
                      ),
                    ),

                  // Fila 2: Estrenos de Cine (Sin CAM)
                  if (_nowPlayingItems.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaRow(
                        title: '🍿 Estrenos de Cine (Calidad Limpia)',
                        items: _nowPlayingItems,
                        onItemTap: _openDetail,
                      ),
                    ),

                  // Fila 3: Acción y Adrenalina
                  if (_actionItems.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaRow(
                        title: '💥 Acción y Adrenalina',
                        items: _actionItems,
                        onItemTap: _openDetail,
                      ),
                    ),

                  // Fila 4: Ciencia Ficción y Futuro
                  if (_scifiItems.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaRow(
                        title: '🚀 Ciencia Ficción y Fantasía',
                        items: _scifiItems,
                        onItemTap: _openDetail,
                      ),
                    ),

                  // Fila 5: Series Populares
                  if (_seriesItems.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaRow(
                        title: '📺 Series Populares (Latino / Castellano)',
                        items: _seriesItems,
                        onItemTap: _openDetail,
                      ),
                    ),

                  // Filas dinámicas infinitas de Cartelera sin fin
                  for (final cat in _extraCategories)
                    SliverToBoxAdapter(
                      child: MediaRow(
                        title: cat['title'] as String,
                        items: (cat['items'] as List<MediaItem>),
                        onItemTap: _openDetail,
                      ),
                    ),

                  // Indicador de carga infinita al desplazarse al fondo
                  if (_isLoadingMore)
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

                  // Margen inferior holgado para evitar recortes en TV y móvil
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 70),
                  ),
                ],
              ),
            ),
    );
  }
}

