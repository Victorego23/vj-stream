import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../models/live_channel.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../theme/tom_tokens.dart';
import '../widgets/xuper_master_launcher.dart';
import 'detail_view.dart';
import 'video_player_view.dart';

/// Sección Exclusiva: FÚTBOL & DEPORTES de TOM TV (Edición Premium Stadium)
/// Muestra únicamente canales de deportes en vivo en calidad 4K/FHD
/// junto con buscador instantáneo, cartelera de cine deportivo y controles cinemáticos.
class SportsView extends StatefulWidget {
  final VoidCallback? onBackToMovies;

  const SportsView({super.key, this.onBackToMovies});

  @override
  State<SportsView> createState() => _SportsViewState();
}

class _SportsViewState extends State<SportsView> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  static const String _favsKey = 'tom_sports_fav_channel_ids';
  Set<String> _favoriteIds = {};

  List<LiveChannel> _allSportsChannels = [];
  List<MediaItem> _sportsMovies = [];

  // Filtros y Búsqueda
  String _selectedSubFilter = 'Todos';
  final List<String> _subFilters = [
    'Todos',
    'Fútbol Ligas',
    'Combate & UFC',
    'Motor & F1',
    'Favoritos',
  ];

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  // Mini-Reproductor para TV y móvil
  LiveChannel? _focusedChannel;
  VideoPlayerController? _previewController;
  Timer? _previewDebounceTimer;
  bool _isPreviewLoading = false;
  bool _isPreviewError = false;
  bool _isMuted = true;

  final ScrollController _scrollController = ScrollController();
  final FocusScopeNode _sportsScopeNode = FocusScopeNode();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'SportsSearch');
  final Map<String, FocusNode> _channelFocusNodes = {};

  // Animación de pulso para el badge "EN VIVO"
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vs.sync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadFavorites();
    _loadSportsData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _previewDebounceTimer?.cancel();
    _previewController?.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sportsScopeNode.dispose();
    for (final node in _channelFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favList = prefs.getStringList(_favsKey) ?? [];
      if (mounted) {
        setState(() => _favoriteIds = favList.toSet());
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite(LiveChannel channel) async {
    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final isFav = !_favoriteIds.contains(channel.id);
      setState(() {
        if (isFav) {
          _favoriteIds.add(channel.id);
        } else {
          _favoriteIds.remove(channel.id);
        }
      });
      await prefs.setStringList(_favsKey, _favoriteIds.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF13151F),
            duration: const Duration(seconds: 2),
            content: Row(
              children: [
                Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFav ? Colors.amber : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isFav ? '★ ${channel.name} guardado en tus favoritos' : 'Eliminado de favoritos',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadSportsData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Obtener todos los canales en vivo y filtrar únicamente Deportes
      final res = await _apiService.fetchLiveChannels();
      final allChannels = res['channels'] as List<LiveChannel>? ?? [];

      final sportsOnly = allChannels.where((c) {
        final cat = c.category.toLowerCase();
        final name = c.name.toLowerCase();
        final id = c.id.toLowerCase();
        return cat.contains('deport') ||
            cat.contains('sport') ||
            name.contains('espn') ||
            name.contains('fox') ||
            name.contains('tyc') ||
            name.contains('win') ||
            name.contains('gol') ||
            name.contains('liga') ||
            name.contains('directv') ||
            name.contains('dsports') ||
            name.contains('dazn') ||
            name.contains('deporte') ||
            name.contains('red bull') ||
            name.contains('azteca deportes') ||
            id.contains('deport') ||
            id.contains('sport');
      }).toList();

      // 2. Obtener películas / documentales de deportes
      List<MediaItem> sportsMoviesList = [];
      try {
        final catalog = await _apiService.fetchActionSportsCatalog();
        sportsMoviesList = catalog['sportsMovies'] ?? [];
      } catch (_) {}

      if (mounted) {
        setState(() {
          _allSportsChannels = sportsOnly;
          _sportsMovies = sportsMoviesList;
          _isLoading = false;
          if (_allSportsChannels.isNotEmpty) {
            _focusedChannel = _allSportsChannels.first;
            _triggerPreviewUpdate(_allSportsChannels.first);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudieron sintonizar las señales deportivas.';
          _isLoading = false;
        });
      }
    }
  }

  List<LiveChannel> get _filteredChannels {
    var list = _allSportsChannels;

    // Filtro por sub-categoría
    if (_selectedSubFilter == 'Favoritos') {
      list = list.where((c) => _favoriteIds.contains(c.id)).toList();
    } else if (_selectedSubFilter == 'Fútbol Ligas') {
      list = list.where((c) {
        final name = c.name.toLowerCase();
        return name.contains('espn') ||
            name.contains('fox') ||
            name.contains('tyc') ||
            name.contains('win') ||
            name.contains('gol') ||
            name.contains('liga') ||
            name.contains('directv') ||
            name.contains('dsports') ||
            name.contains('futbol') ||
            name.contains('fútbol');
      }).toList();
    } else if (_selectedSubFilter == 'Combate & UFC') {
      list = list.where((c) {
        final name = c.name.toLowerCase();
        return name.contains('ufc') ||
            name.contains('box') ||
            name.contains('combate') ||
            name.contains('fight') ||
            name.contains('wwe');
      }).toList();
    } else if (_selectedSubFilter == 'Motor & F1') {
      list = list.where((c) {
        final name = c.name.toLowerCase();
        return name.contains('red bull') ||
            name.contains('f1') ||
            name.contains('motor') ||
            name.contains('auto') ||
            name.contains('moto') ||
            name.contains('extremo');
      }).toList();
    }

    // Filtro por texto de búsqueda en vivo
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((c) => c.name.toLowerCase().contains(q) || c.id.toLowerCase().contains(q)).toList();
    }

    return list;
  }

  void _triggerPreviewUpdate(LiveChannel? channel) {
    _previewDebounceTimer?.cancel();
    if (channel == null || channel.streamUrl.isEmpty) {
      _previewController?.dispose();
      _previewController = null;
      return;
    }

    if (mounted) {
      setState(() {
        _isPreviewLoading = true;
        _isPreviewError = false;
      });
    }

    _previewDebounceTimer = Timer(const Duration(milliseconds: 320), () async {
      if (!mounted) return;
      if (_focusedChannel?.id != channel.id) return;

      try {
        final old = _previewController;
        _previewController = null;
        if (old != null) await old.dispose();

        final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(channel.streamUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _previewController = ctrl;
        await ctrl.initialize();
        if (mounted && _focusedChannel?.id == channel.id) {
          await ctrl.setVolume(_isMuted ? 0.0 : 0.85);
          await ctrl.setLooping(true);
          await ctrl.play();
          setState(() {
            _isPreviewLoading = false;
            _isPreviewError = false;
          });
        }
      } catch (_) {
        if (mounted && _focusedChannel?.id == channel.id) {
          setState(() {
            _isPreviewLoading = false;
            _isPreviewError = true;
          });
        }
      }
    });
  }

  void _playChannel(LiveChannel channel) {
    HapticFeedback.mediumImpact();
    _previewController?.pause();
    final list = _filteredChannels;
    final idx = list.indexWhere((c) => c.id == channel.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerView(
          videoUrl: channel.streamUrl,
          title: channel.name,
          isLive: true,
          liveChannel: channel,
          liveSources: channel.sources,
          liveChannelsList: list,
          initialChannelIndex: idx >= 0 ? idx : 0,
        ),
      ),
    ).then((_) {
      if (mounted && _previewController != null) {
        _previewController!.play();
      }
    });
  }

  FocusNode _getFocusNode(String id) {
    return _channelFocusNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'SportChannel_$id'));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = screenWidth > 700;

    return FocusScope(
      node: _sportsScopeNode,
      child: Scaffold(
        backgroundColor: const Color(0xFF06070B),
        body: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                      ),
                      child: const CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 3),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Sintonizando Estadio TOM TV en 4K...',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Cargando señales oficiales y audio latino',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
                ? _buildErrorView()
                : isTv
                    ? _buildTvLayout()
                    : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF10121C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_soccer_rounded, color: Color(0xFF00E676), size: 54),
            const SizedBox(height: 14),
            Text(
              _errorMessage ?? 'Error',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _loadSportsData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar Sintonización', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DISEÑO PARA SMART TV (10-FOOT UI, 2 COLUMNAS, MINI-PLAYER Y D-PAD)
  // ===========================================================================
  Widget _buildTvLayout() {
    final channels = _filteredChannels;

    return Column(
      children: [
        // Barra Superior Cinemática
        _buildTvTopBar(),

        // Contenido Principal
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Columna Izquierda: Banner Destacado, Buscador y Grilla (Flex 7)
              Expanded(
                flex: 7,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // Banner Hero: Partido / Transmisión Destacada de Hoy
                    SliverToBoxAdapter(
                      child: _buildTvHeroMatchBanner(),
                    ),

                    // Barra de Búsqueda y Sub-filtros
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                        child: Row(
                          children: [
                            // Buscador Rápido
                            Expanded(
                              flex: 4,
                              child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  onChanged: (val) {
                                    setState(() => _searchQuery = val);
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Buscar canal (ESPN, Fox, TyC, Win, Liga)...',
                                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E676), size: 18),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Sub-filtros tipo Chips
                            Expanded(
                              flex: 6,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _subFilters.map((filter) {
                                    final isSel = _selectedSubFilter == filter;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            _selectedSubFilter = filter;
                                            final currentList = _filteredChannels;
                                            if (currentList.isNotEmpty) {
                                              _focusedChannel = currentList.first;
                                              _triggerPreviewUpdate(currentList.first);
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 160),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: isSel ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: isSel ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.12),
                                            ),
                                          ),
                                          child: Text(
                                            filter,
                                            style: TextStyle(
                                              color: isSel ? Colors.black : Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Grilla de Canales Deportivos
                    if (channels.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.search_off_rounded, color: Colors.white24, size: 48),
                              const SizedBox(height: 10),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No se encontraron canales para "$_searchQuery"'
                                    : 'No hay canales disponibles en esta categoría.',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1.65,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, idx) {
                              final ch = channels[idx];
                              return _buildTvChannelCard(ch);
                            },
                            childCount: channels.length,
                          ),
                        ),
                      ),

                    // Cartelera de Películas y Documentales Deportivos
                    if (_sportsMovies.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E676).withValues(alpha: 0.6),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                '🎬 CINE Y DOCUMENTALES DEPORTIVOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_sportsMovies.length} Películas',
                                style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 195,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _sportsMovies.length,
                            itemBuilder: (context, idx) {
                              final movie = _sportsMovies[idx];
                              return _buildMovieCard(movie);
                            },
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 30)),
                    ],
                  ],
                ),
              ),

              // Columna Derecha: Mini-Reproductor y Ficha Deportiva (Flex 5)
              Container(
                width: 380,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0C13),
                  border: Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                ),
                child: _buildTvPreviewColumn(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTvTopBar() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF08090E),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          const XuperTomLogo(scale: 0.76),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00E676), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _pulseAnimation,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E676),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'ESTADIO TOM TV • DEPORTES EN VIVO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${_allSportsChannels.length} Señales Oficiales',
            style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          const XuperLiveClock(),
          if (widget.onBackToMovies != null) ...[
            const SizedBox(width: 16),
            InkWell(
              onTap: widget.onBackToMovies,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Menú Principal',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTvHeroMatchBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF002A16),
            Color(0xFF021B13),
            Color(0xFF081220),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              Icons.sports_soccer_rounded,
              size: 160,
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'COBERTURA EN VIVO',
                              style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'CALIDAD 4K UHD • AUDIO LATINO',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 9.5, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'FÚTBOL INTERNACIONAL & LIGAS EN DIRECTO',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'ESPN, Fox Sports, TyC, Win Sports, Liga 1 Max y señales exclusivas sin cortes.',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_focusedChannel != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 6,
                    ),
                    onPressed: () => _playChannel(_focusedChannel!),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                    label: const Text(
                      'SINTONIZAR',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvChannelCard(LiveChannel ch) {
    final isSelected = _focusedChannel?.id == ch.id;
    final isFav = _favoriteIds.contains(ch.id);
    final node = _getFocusNode(ch.id);

    return FocusableActionDetector(
      focusNode: node,
      onFocusChange: (focused) {
        if (focused && mounted) {
          setState(() {
            _focusedChannel = ch;
            _triggerPreviewUpdate(ch);
          });
        }
      },
      child: InkWell(
        onTap: () => _playChannel(ch),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF131A26) : const Color(0xFF0F111A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.07),
              width: isSelected ? 2.2 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Logo Oficial
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: ch.logoUrl.isNotEmpty
                    ? Image.network(
                        ch.logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer_rounded, color: Color(0xFF00E676), size: 28),
                      )
                    : const Icon(Icons.sports_soccer_rounded, color: Color(0xFF00E676), size: 28),
              ),
              const SizedBox(width: 12),
              // Datos del Canal
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ch.quality,
                          style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Botón Favorito
              IconButton(
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFav ? Colors.amber : Colors.white24,
                  size: 20,
                ),
                onPressed: () => _toggleFavorite(ch),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvPreviewColumn() {
    final ch = _focusedChannel;
    if (ch == null) {
      return const Center(
        child: Text('Selecciona un canal para sintonizar', style: TextStyle(color: Colors.white54)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mini-player Container (16:9)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.45), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.18),
                    blurRadius: 22,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_previewController != null && _previewController!.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _previewController!.value.size.width,
                        height: _previewController!.value.size.height,
                        child: VideoPlayer(_previewController!),
                      ),
                    ),
                  if (_isPreviewLoading)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00E676)),
                      ),
                    ),
                  if (_isPreviewError)
                    Container(
                      color: Colors.black87,
                      child: const Center(
                        child: Text(
                          'Transmisión lista al ingresar',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                  // Badges y Audio Toggle
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
                          SizedBox(width: 4),
                          Text(
                            'EN VIVO 4K',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.all(6),
                      ),
                      icon: Icon(
                        _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                          _previewController?.setVolume(_isMuted ? 0.0 : 0.85);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Título y Datos del Canal Deportivo
          Row(
            children: [
              Expanded(
                child: Text(
                  ch.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _favoriteIds.contains(ch.id) ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _favoriteIds.contains(ch.id) ? Colors.amber : Colors.white54,
                ),
                onPressed: () => _toggleFavorite(ch),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                ),
                child: Text(
                  ch.quality,
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Audio Latino Oficial', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 8),
              const Text('• 60 FPS Estable', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 20),

          // Botón Ver en Pantalla Completa
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 8,
              shadowColor: const Color(0xFF00E676).withValues(alpha: 0.5),
            ),
            onPressed: () => _playChannel(ch),
            icon: const Icon(Icons.fullscreen_rounded, size: 22, color: Colors.black),
            label: const Text(
              'VER EN PANTALLA COMPLETA',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '💡 Presiona OK en tu control remoto para pantalla completa con cambio rápido de canales (Flechas Arriba / Abajo).',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DISEÑO PARA MÓVIL (PANTALLA TÁCTIL, REPRODUCTOR SUPERIOR Y CHIPS)
  // ===========================================================================
  Widget _buildMobileLayout() {
    final channels = _filteredChannels;

    return Column(
      children: [
        // Reproductor Superior Fijo (Estilo TV Móvil)
        _buildMobileTopPlayer(),

        // Buscador y Sub-filtros
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0D14),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            children: [
              // Barra de búsqueda táctil
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar ESPN, Fox, Win, TyC, Liga...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E676), size: 16),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 14),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Chips de filtros horizontales
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _subFilters.map((filter) {
                    final isSel = _selectedSubFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Center(
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: isSel,
                          selectedColor: const Color(0xFF00E676),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedSubFilter = filter);
                            }
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // Lista Táctil de Canales Deportivos
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final ch = channels[idx];
              final isSelected = _focusedChannel?.id == ch.id;
              final isFav = _favoriteIds.contains(ch.id);

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _focusedChannel = ch;
                    _triggerPreviewUpdate(ch);
                  });
                  _playChannel(ch);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF131A26) : const Color(0xFF0F1118),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ch.logoUrl.isNotEmpty
                            ? Image.network(
                                ch.logoUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer_rounded, color: Color(0xFF00E676)),
                              )
                            : const Icon(Icons.sports_soccer_rounded, color: Color(0xFF00E676)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE50914),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('DIRECTO', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 6),
                                Text(ch.quality, style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.star_rounded : Icons.star_border_rounded,
                          color: isFav ? Colors.amber : Colors.white24,
                        ),
                        onPressed: () => _toggleFavorite(ch),
                      ),
                      const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E676), size: 30),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTopPlayer() {
    final ch = _focusedChannel;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_previewController != null && _previewController!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _previewController!.value.size.width,
                  height: _previewController!.value.size.height,
                  child: VideoPlayer(_previewController!),
                ),
              ),
            if (_isPreviewLoading)
              const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
            // Gradiente y Controles
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 24, 14, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ch?.name ?? 'Estadio TOM TV',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                          _previewController?.setVolume(_isMuted ? 0.0 : 0.85);
                        });
                      },
                    ),
                    if (ch != null)
                      IconButton(
                        icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFF00E676), size: 26),
                        onPressed: () => _playChannel(ch),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieCard(MediaItem item) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          _previewController?.pause();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailView(mediaItem: item),
            ),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  item.bestPosterUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.movie_rounded, color: Colors.white38),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
