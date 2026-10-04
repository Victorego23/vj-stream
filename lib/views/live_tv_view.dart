import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/live_channel.dart';
import '../services/api_service.dart';
import 'video_player_view.dart';

class LiveTvView extends StatefulWidget {
  final String? initialCategory;
  final VoidCallback? onBackToMovies;
  const LiveTvView({super.key, this.initialCategory, this.onBackToMovies});

  @override
  State<LiveTvView> createState() => _LiveTvViewState();
}

class _LiveTvViewState extends State<LiveTvView> {
  final ApiService _apiService = ApiService();

  static const String _favsKey = 'vj_stream_fav_channel_ids';
  static const String _recentsKey = 'vj_stream_recent_channel_ids';

  Set<String> _favoriteChannelIds = {};
  List<String> _recentChannelIds = [];

  List<LiveChannel> _allChannels = [];
  List<String> _categories = ['Favoritos', '🇵🇪 Canales Peruanos', 'Todos', 'Recientes'];
  late String _selectedCategory;
  bool _isLoading = true;
  String? _errorMessage;

  final ValueNotifier<LiveChannel?> _focusedChannelNotifier = ValueNotifier<LiveChannel?>(null);
  final FocusScopeNode _channelGridScopeNode = FocusScopeNode();
  final FocusScopeNode _sidebarScopeNode = FocusScopeNode();
  final FocusNode _returnToMoviesFocusNode = FocusNode();
  final FocusNode _backToMoviesSidebarFocusNode = FocusNode(debugLabel: 'TvCat_BackToMovies');
  final Map<String, FocusNode> _categoryFocusNodes = {};
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  FocusNode _getCategoryFocusNode(String cat) {
    return _categoryFocusNodes.putIfAbsent(cat, () => FocusNode(debugLabel: 'TvCat_$cat'));
  }

  static String getChannelCountry(LiveChannel channel) {
    final match = RegExp(r'_([a-z]{2})$', caseSensitive: false).firstMatch(channel.id);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return 'other';
  }

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Todos';
    _scrollController.addListener(_onScroll);
    _loadFavoritesAndRecents();
    _loadChannels();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 240;
    if (show != _showBackToTop) {
      if (mounted) {
        setState(() => _showBackToTop = show);
      }
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset > 1200) {
      _scrollController.jumpTo(300);
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
    if (_filteredChannels.isNotEmpty && mounted) {
      _focusedChannelNotifier.value = _filteredChannels.first;
    }
  }

  void _jumpToSidebar() {
    final catNode = _categoryFocusNodes[_selectedCategory];
    if (catNode != null && catNode.canRequestFocus) {
      catNode.requestFocus();
      return;
    }
    if (_backToMoviesSidebarFocusNode.canRequestFocus) {
      _backToMoviesSidebarFocusNode.requestFocus();
      return;
    }
    for (final node in _categoryFocusNodes.values) {
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
    _sidebarScopeNode.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _channelGridScopeNode.dispose();
    _sidebarScopeNode.dispose();
    _returnToMoviesFocusNode.dispose();
    _backToMoviesSidebarFocusNode.dispose();
    _focusedChannelNotifier.dispose();
    for (final node in _categoryFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFavoritesAndRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favList = prefs.getStringList(_favsKey) ?? [];
      final recList = prefs.getStringList(_recentsKey) ?? [];
      if (mounted) {
        setState(() {
          _favoriteChannelIds = favList.toSet();
          _recentChannelIds = recList;
        });
      }
    } catch (_) {}
  }

  Future<void> _recordRecentChannel(String channelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(_recentChannelIds);
      list.remove(channelId);
      list.insert(0, channelId);
      if (list.length > 25) {
        list.removeRange(25, list.length);
      }
      setState(() {
        _recentChannelIds = list;
      });
      await prefs.setStringList(_recentsKey, list);
    } catch (_) {}
  }

  Future<void> _toggleFavorite(LiveChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isNowFav = !_favoriteChannelIds.contains(channel.id);
      setState(() {
        if (isNowFav) {
          _favoriteChannelIds.add(channel.id);
        } else {
          _favoriteChannelIds.remove(channel.id);
        }
      });
      await prefs.setStringList(_favsKey, _favoriteChannelIds.toList());

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1F2A),
            duration: const Duration(seconds: 2),
            content: Row(
              children: [
                Icon(
                  isNowFav ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isNowFav ? Colors.amber : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isNowFav
                        ? '★ ${channel.name} agregado a Favoritos'
                        : 'Eliminado de Favoritos: ${channel.name}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.fetchLiveChannels();
      final channels = res['channels'] as List<LiveChannel>? ?? [];
      final categories = res['categories'] as List<String>? ?? [];

      if (mounted) {
        setState(() {
          _allChannels = channels;
          final cleanCats = categories
              .where((c) => c != 'Todos' && c != 'Favoritos' && c != 'Recientes')
              .toList();
          final otherCats = cleanCats
              .where((c) => !c.contains('Peruanos') && !c.contains('Perú'))
              .toList();
          _categories = ['Favoritos', '🇵🇪 Canales Peruanos', 'Todos', 'Recientes', ...otherCats];
          _isLoading = false;
          if (_filteredChannels.isNotEmpty) {
            _focusedChannelNotifier.value = _filteredChannels.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudieron cargar los canales de TV en vivo.';
          _isLoading = false;
        });
      }
    }
  }

  List<LiveChannel> get _filteredChannels {
    if (_selectedCategory == 'Recientes') {
      final map = {for (var c in _allChannels) c.id: c};
      final list = <LiveChannel>[];
      for (final id in _recentChannelIds) {
        if (map.containsKey(id)) {
          list.add(map[id]!);
        }
      }
      return list;
    }

    return _allChannels.where((channel) {
      final isPeruCat = _selectedCategory.contains('Peruanos') || _selectedCategory.contains('Perú');
      if (_selectedCategory == 'Todos') {
        return true;
      } else if (_selectedCategory == 'Favoritos') {
        return _favoriteChannelIds.contains(channel.id);
      } else if (isPeruCat) {
        return channel.category.contains('Perú') ||
            channel.category.contains('Peruanos') ||
            getChannelCountry(channel) == 'pe';
      } else {
        return channel.category.toLowerCase() == _selectedCategory.toLowerCase();
      }
    }).toList();
  }

  String _getCategoryIcon(String cat) {
    if (cat == 'Favoritos') return '⭐ ';
    if (cat == 'Recientes') return '🕒 ';
    if (cat.contains('Perú') || cat.contains('Peruanos')) return '🇵🇪 ';
    final lower = cat.toLowerCase();
    if (lower.contains('depor')) return '⚽ ';
    if (lower.contains('cine') || lower.contains('series')) return '🎬 ';
    if (lower.contains('infant') || lower.contains('kids')) return '👶 ';
    if (lower.contains('entreten') || lower.contains('cult')) return '🌍 ';
    if (lower.contains('nacion') || lower.contains('noti')) return '📰 ';
    if (lower.contains('music')) return '🎵 ';
    return '📺 ';
  }

  void _playChannel(LiveChannel channel) {
    _recordRecentChannel(channel.id);
    final currentList = _filteredChannels;
    final initialIndex = currentList.indexWhere((c) => c.id == channel.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerView(
          videoUrl: channel.streamUrl,
          title: channel.name,
          qualityLabel: channel.quality,
          liveSources: channel.sources,
          isLive: true,
          liveChannel: channel,
          liveChannelsList: currentList,
          initialChannelIndex: initialIndex >= 0 ? initialIndex : 0,
        ),
      ),
    ).then((_) {
      _loadFavoritesAndRecents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onBackToMovies?.call();
      },
      child: Focus(
        autofocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack) {
              if (widget.onBackToMovies != null) {
                widget.onBackToMovies!();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0C),
          body: isTv ? _buildTvLayout() : _buildMobileLayout(),
        ),
      ),
    );
  }

  // ===========================================================================
  // LAYOUT PROFESIONAL SMART TV (SIDEBAR + BANNER + GRID CON ENFOQUE D-PAD)
  // ===========================================================================
  Widget _buildTvLayout() {
    final channels = _filteredChannels;

    return Row(
      children: [
        // Sidebar lateral de Categorías y Países para Smart TV
        Container(
          width: 250,
          decoration: const BoxDecoration(
            color: Color(0xFF0F1017),
            border: Border(
              right: BorderSide(color: Color(0xFF1E202C), width: 1.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabecera Sidebar con Badge EN VIVO
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE50914), Color(0xFF990000)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66E50914),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TV EN VIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${_allChannels.length} canales 24/7',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF1A1C27), height: 1),

              const SizedBox(height: 4),

              // Botón destacado siempre visible: Regresar a Películas
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: _TvCategoryItem(
                  title: 'Volver a Películas',
                  icon: '🎬 ',
                  isSelected: false,
                  badgeCount: null,
                  focusNode: _backToMoviesSidebarFocusNode,
                  onSelect: () => widget.onBackToMovies?.call(),
                  onKeyRight: () {
                    _channelGridScopeNode.requestFocus();
                  },
                  onBackToMovies: widget.onBackToMovies,
                ),
              ),

              const Divider(color: Color(0xFF1E202C), height: 8),

              // Lista de Categorías navegable con Control Remoto (100% montadas en memoria para foco instantáneo)
              Expanded(
                child: FocusScope(
                  node: _sidebarScopeNode,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(
                      children: _categories.map((cat) {
                        final isSelected = cat.toLowerCase() == _selectedCategory.toLowerCase();
                        int? count;
                        if (cat == 'Favoritos') count = _favoriteChannelIds.length;
                        if (cat == 'Recientes') count = _recentChannelIds.length;
                        final catNode = _getCategoryFocusNode(cat);

                        return _TvCategoryItem(
                          key: ValueKey('cat_$cat'),
                          title: cat,
                          icon: _getCategoryIcon(cat),
                          isSelected: isSelected,
                          badgeCount: count,
                          focusNode: catNode,
                          onSelect: () {
                            setState(() {
                              _selectedCategory = cat;
                              if (_filteredChannels.isNotEmpty) {
                                _focusedChannelNotifier.value = _filteredChannels.first;
                              }
                            });
                          },
                          onKeyRight: () {
                            // Pasar foco a la cuadrícula de canales
                            _channelGridScopeNode.requestFocus();
                          },
                          onBackToMovies: widget.onBackToMovies,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              // Indicador inferior de ayuda para el control remoto
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF0B0C12),
                child: const Row(
                  children: [
                    Icon(Icons.settings_remote_rounded, color: Colors.white38, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Flecha Der: Ver Canales',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Área Principal: Banner de Información + Cuadrícula de Canales
        Expanded(
          child: Column(
            children: [
              // Panel Superior Dinámico del Canal Enfocado (TV Banner Preview)
              ValueListenableBuilder<LiveChannel?>(
                valueListenable: _focusedChannelNotifier,
                builder: (context, currentFocused, _) {
                  final channelToShow = currentFocused ?? (channels.isNotEmpty ? channels.first : null);
                  return _buildFocusedChannelBanner(channelToShow);
                },
              ),

              // Cuadrícula de Canales con Focus D-Pad y botón Subir Todo
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFFE50914)),
                      )
                    : _errorMessage != null
                        ? _buildErrorView()
                        : channels.isEmpty
                            ? _buildEmptyView()
                            : Stack(
                                children: [
                                  FocusScope(
                                    node: _channelGridScopeNode,
                                    child: GridView.builder(
                                      controller: _scrollController,
                                      cacheExtent: 1200,
                                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 240,
                                        mainAxisSpacing: 16,
                                        crossAxisSpacing: 16,
                                        childAspectRatio: 1.35,
                                      ),
                                      itemCount: channels.length,
                                      itemBuilder: (context, index) {
                                        final channel = channels[index];
                                        final channelNumber = index + 1;
                                        final isFirstRow = index < 5;
                                        return _TvFocusableChannelCard(
                                          key: ValueKey(channel.id),
                                          channel: channel,
                                          channelNumber: channelNumber,
                                          isFirstRow: isFirstRow,
                                          isFavorite: _favoriteChannelIds.contains(channel.id),
                                          onFocusChange: (focused) {
                                            if (focused) {
                                              _focusedChannelNotifier.value = channel;
                                            }
                                          },
                                          onTap: () => _playChannel(channel),
                                          onLongPress: () => _toggleFavorite(channel),
                                          onKeyLeft: (isFirstColumn) {
                                            _jumpToSidebar();
                                          },
                                          onKeyUp: () {
                                            _returnToMoviesFocusNode.requestFocus();
                                            if (_scrollController.hasClients) {
                                              _scrollController.animateTo(0, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
                                            }
                                          },
                                          onFastScrollTop: _scrollToTop,
                                          onBackToMovies: widget.onBackToMovies,
                                        );
                                      },
                                    ),
                                  ),
                                  if (_showBackToTop)
                                    Positioned(
                                      bottom: 24,
                                      right: 24,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _scrollToTop,
                                          borderRadius: BorderRadius.circular(30),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFFE50914), Color(0xFF990000)],
                                              ),
                                              borderRadius: BorderRadius.circular(30),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x88E50914),
                                                  blurRadius: 14,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.keyboard_double_arrow_up_rounded, color: Colors.white, size: 22),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Subir Todo',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 13,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Banner superior con información del canal enfocado (Estilo Smart TV)
  Widget _buildFocusedChannelBanner(LiveChannel? channel) {
    if (channel == null) {
      return Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: const Color(0xFF11121A),
        child: const Row(
          children: [
            Icon(Icons.tv_rounded, color: Colors.white24, size: 40),
            SizedBox(width: 16),
            Text(
              'Selecciona un canal con el control remoto',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final isFav = _favoriteChannelIds.contains(channel.id);
    final country = getChannelCountry(channel);

    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF2141522), Color(0xEB0A0B12)],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo del canal grande
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF07080D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33E50914),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: channel.logoUrl.isNotEmpty
                ? Image.network(
                    channel.logoUrl,
                    fit: BoxFit.contain,
                    cacheWidth: 200,
                    cacheHeight: 200,
                    errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 36),
                  )
                : const Icon(Icons.tv_rounded, color: Colors.white38, size: 36),
          ),
          const SizedBox(width: 18),

          // Metadatos del canal
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    // Badge EN VIVO
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                            'EN VIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Categoría
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        channel.category,
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Calidad
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Text(
                        channel.quality,
                        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),

                    if (isFav) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 6),

                // Nombre del canal
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),

                // Categoría y Fuentes
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE50914), width: 0.8),
                      ),
                      child: Text(
                        channel.category.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '⚡ ${channel.sources.length} ${channel.sources.length == 1 ? "señal" : "señales"} disponible${channel.sources.length == 1 ? "" : "s"}',
                      style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Leyenda de botones del control remoto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF181A25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF26293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Pantalla Completa', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '★ OK Largo',
                        style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFav ? 'Quitar Favorito' : 'Guardar Favorito',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '⬅ / ATRÁS',
                        style: TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Menú Lateral', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          // Botón directo a Películas con foco Smart TV
          const SizedBox(width: 12),
          Focus(
            focusNode: _returnToMoviesFocusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  widget.onBackToMovies?.call();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _channelGridScopeNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _jumpToSidebar();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final isFocused = Focus.of(ctx).hasFocus;
                return InkWell(
                  onTap: widget.onBackToMovies,
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isFocused
                          ? const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFF990000)],
                            )
                          : null,
                      color: isFocused ? null : const Color(0xFF1E202C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFocused ? Colors.white : const Color(0xFF33374C),
                        width: isFocused ? 2.0 : 1.0,
                      ),
                      boxShadow: isFocused
                          ? const [
                              BoxShadow(
                                color: Color(0x99E50914),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.movie_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Ver Películas',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isFocused ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Botón rápido Subir Todo en la cabecera cuando el usuario ha bajado
          if (_showBackToTop) ...[
            const SizedBox(width: 14),
            InkWell(
              onTap: _scrollToTop,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFF990000)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66E50914),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_double_arrow_up_rounded, color: Colors.white, size: 22),
                    SizedBox(height: 3),
                    Text(
                      'Subir Todo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
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

  // ===========================================================================
  // LAYOUT MÓVIL / PANTALLA ESTRECHA (LIMPIO, SIN BARRA DE BÚSQUEDA)
  // ===========================================================================
  Widget _buildMobileLayout() {
    final channels = _filteredChannels;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.extended(
              heroTag: 'mobile_live_tv_back_to_top',
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              elevation: 8,
              onPressed: _scrollToTop,
              icon: const Icon(Icons.keyboard_double_arrow_up_rounded, size: 20),
              label: const Text(
                'Subir Todo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            )
          : null,
      body: RefreshIndicator(
        color: const Color(0xFFE50914),
        backgroundColor: const Color(0xFF16171F),
        notificationPredicate: (notification) => notification.metrics.pixels <= 0,
        onRefresh: _loadChannels,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          // Cabecera Móvil
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  if (widget.onBackToMovies != null) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                      onPressed: widget.onBackToMovies,
                      tooltip: 'Volver a Películas',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFF990000)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66E50914),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TV en Vivo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${_allChannels.length} canales transmitiendo 24/7',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onBackToMovies != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF1E202C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.movie_rounded, color: Color(0xFFE50914), size: 16),
                      label: const Text('Películas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: widget.onBackToMovies,
                    ),
                ],
              ),
            ),
          ),

          // Categorías Móvil
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat.toLowerCase() == _selectedCategory.toLowerCase();
                  final icon = cat == 'Todos' ? '🌐 ' : _getCategoryIcon(cat);
                  int? count;
                  if (cat == 'Favoritos' && _favoriteChannelIds.isNotEmpty) count = _favoriteChannelIds.length;
                  if (cat == 'Recientes' && _recentChannelIds.isNotEmpty) count = _recentChannelIds.length;
                  final badgeCount = count != null ? ' ($count)' : '';

                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedCategory = cat);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFFE50914), Color(0xFF990000)],
                              )
                            : null,
                        color: isSelected ? null : const Color(0xFF16171F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFE50914) : const Color(0xFF232532),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$icon$cat$badgeCount',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Cuadrícula Móvil
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(child: _buildErrorView())
          else if (channels.isEmpty)
            SliverFillRemaining(child: _buildEmptyView())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.18,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final channel = channels[index];
                    final channelNumber = index + 1;
                    return _buildMobileChannelCard(channel, channelNumber);
                  },
                  childCount: channels.length,
                ),
              ),
            ),
        ],
      ),
    ),
  );
  }

  Widget _buildMobileChannelCard(LiveChannel channel, int channelNumber) {
    final isFav = _favoriteChannelIds.contains(channel.id);

    return InkWell(
      onTap: () => _playChannel(channel),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16171F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFav ? Colors.amber.withValues(alpha: 0.3) : const Color(0xFF232532),
            width: isFav ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isFav ? Colors.amber.withValues(alpha: 0.08) : Colors.black45,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera con número + badge vivo + favorito
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${channelNumber.toString().padLeft(2, "0")}',
                        style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'EN VIVO',
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => _toggleFavorite(channel),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isFav
                          ? Colors.amber.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFav ? Colors.amber : Colors.white54,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Logo central
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0E14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: channel.logoUrl.isNotEmpty
                      ? Image.network(
                          channel.logoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 32),
                        )
                      : const Icon(Icons.tv_rounded, color: Colors.white38, size: 32),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Nombre y categoría
            Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    channel.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  channel.quality,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFFE50914), size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Error desconocido',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
              ),
              onPressed: _loadChannels,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _selectedCategory == 'Favoritos'
                ? Icons.star_border_rounded
                : _selectedCategory == 'Recientes'
                    ? Icons.history_rounded
                    : Icons.tv_off_rounded,
            color: _selectedCategory == 'Favoritos'
                ? Colors.amber.withValues(alpha: 0.6)
                : Colors.white38,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            _selectedCategory == 'Favoritos'
                ? 'Aún no tienes canales favoritos\nMantén presionado OK en el control remoto para agregar'
                : _selectedCategory == 'Recientes'
                    ? 'Aún no has reproducido canales recientemente'
                    : 'No se encontraron canales en esta categoría',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedCategory = 'Todos';
              });
            },
            child: const Text('Ver todos los canales', style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// WIDGET ITEM CATEGORÍA FOCUSABLE PARA CONTROL REMOTO SMART TV
// =============================================================================
class _TvCategoryItem extends StatefulWidget {
  final String title;
  final String icon;
  final bool isSelected;
  final int? badgeCount;
  final VoidCallback onSelect;
  final VoidCallback onKeyRight;
  final VoidCallback? onBackToMovies;
  final FocusNode? focusNode;

  const _TvCategoryItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    this.badgeCount,
    required this.onSelect,
    required this.onKeyRight,
    this.onBackToMovies,
    this.focusNode,
  });

  @override
  State<_TvCategoryItem> createState() => _TvCategoryItemState();
}

class _TvCategoryItemState extends State<_TvCategoryItem> {
  late final FocusNode _focusNode;
  late final bool _internalFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      _internalFocusNode = false;
    } else {
      _focusNode = FocusNode(debugLabel: 'TvCat_${widget.title}');
      _internalFocusNode = true;
    }
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
      if (_focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    if (_internalFocusNode) {
      _focusNode.dispose();
    }
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
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onKeyRight();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            widget.onBackToMovies?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onSelect();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: (_isFocused || widget.isSelected)
                  ? LinearGradient(
                      colors: _isFocused
                          ? [const Color(0xFFE50914), const Color(0xFFB0060E)]
                          : [const Color(0xFF26293A), const Color(0xFF1B1D29)],
                    )
                  : null,
              color: (_isFocused || widget.isSelected) ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : widget.isSelected
                        ? const Color(0xFFE50914).withValues(alpha: 0.5)
                        : Colors.transparent,
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                if (widget.isSelected && !_isFocused)
                  Container(
                    width: 3.5,
                    height: 14,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [
                        BoxShadow(color: Color(0xAAE50914), blurRadius: 4),
                      ],
                    ),
                  ),
                Text(widget.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isFocused
                          ? Colors.white
                          : widget.isSelected
                              ? Colors.white
                              : Colors.white70,
                      fontWeight: (_isFocused || widget.isSelected) ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (widget.badgeCount != null && widget.badgeCount! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isFocused
                          ? Colors.black.withValues(alpha: 0.3)
                          : const Color(0xFFE50914).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.badgeCount}',
                      style: TextStyle(
                        color: _isFocused ? Colors.white : const Color(0xFFFF5252),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
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

// =============================================================================
// TARJETA DE CANAL FOCUSABLE CON ZOOM, GLOW Y MANEJO D-PAD PARA SMART TV
// =============================================================================
class _TvFocusableChannelCard extends StatefulWidget {
  final LiveChannel channel;
  final int channelNumber;
  final bool isFavorite;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onKeyLeft;
  final bool isFirstRow;
  final VoidCallback? onKeyUp;
  final VoidCallback? onFastScrollTop;
  final VoidCallback? onBackToMovies;

  const _TvFocusableChannelCard({
    super.key,
    required this.channel,
    required this.channelNumber,
    required this.isFavorite,
    required this.onFocusChange,
    required this.onTap,
    required this.onLongPress,
    required this.onKeyLeft,
    this.isFirstRow = false,
    this.onKeyUp,
    this.onFastScrollTop,
    this.onBackToMovies,
  });

  @override
  State<_TvFocusableChannelCard> createState() => _TvFocusableChannelCardState();
}

class _TvFocusableChannelCardState extends State<_TvFocusableChannelCard> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  DateTime? _keyDownTime;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      final focused = _focusNode.hasFocus;
      setState(() => _isFocused = focused);
      widget.onFocusChange(focused);

      if (focused) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.2,
          duration: const Duration(milliseconds: 60),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
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
            _keyDownTime = DateTime.now();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            // Presionar Atrás/Retroceso en la cuadrícula regresa al menú lateral de categorías
            widget.onKeyLeft(true);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final moved = node.focusInDirection(TraversalDirection.left);
            if (moved) {
              return KeyEventResult.handled;
            }
            // Si no se puede mover a la izquierda dentro de la cuadrícula, estamos en la primera columna: regresar al sidebar
            widget.onKeyLeft(true);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            final moved = node.focusInDirection(TraversalDirection.right);
            if (moved) {
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (widget.isFirstRow) {
              widget.onKeyUp?.call();
              return KeyEventResult.handled;
            }
            final moved = node.focusInDirection(TraversalDirection.up);
            if (moved) {
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final moved = node.focusInDirection(TraversalDirection.down);
            if (moved) {
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.pageUp ||
              event.logicalKey == LogicalKeyboardKey.channelUp) {
            widget.onFastScrollTop?.call();
            return KeyEventResult.handled;
          }
        } else if (event is KeyUpEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (_keyDownTime != null) {
              final elapsed = DateTime.now().difference(_keyDownTime!).inMilliseconds;
              _keyDownTime = null;
              if (elapsed >= 600) {
                // Pulsación larga: Favorito
                widget.onLongPress();
              } else {
                // Pulsación corta: Reproducir
                widget.onTap();
              }
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onTap();
        },
        onLongPress: () {
          _focusNode.requestFocus();
          widget.onLongPress();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: _isFocused ? const Color(0xFF1F2232) : const Color(0xFF14151E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isFocused
                    ? const Color(0xFFE50914)
                    : widget.isFavorite
                        ? Colors.amber.withValues(alpha: 0.4)
                        : const Color(0xFF222432),
                width: _isFocused ? 3.0 : 1.0,
              ),
              boxShadow: [
                if (_isFocused)
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.8),
                    blurRadius: 14,
                    spreadRadius: 2,
                  )
                else
                  const BoxShadow(
                    color: Colors.black45,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera de la tarjeta: Número de canal + Bandera + Indicador de Favorito
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isFocused
                            ? const Color(0xFFE50914)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${widget.channelNumber.toString().padLeft(2, "0")}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFE50914), width: 0.6),
                          ),
                          child: const Text(
                            'EN VIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (widget.isFavorite) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                        ],
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Logo central del canal
                Expanded(
                  child: Center(
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0B10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: widget.channel.logoUrl.isNotEmpty
                          ? Image.network(
                              widget.channel.logoUrl,
                              fit: BoxFit.contain,
                              cacheWidth: 160,
                              cacheHeight: 160,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.tv_rounded,
                                color: Colors.white30,
                                size: 34,
                              ),
                            )
                          : const Icon(
                              Icons.tv_rounded,
                              color: Colors.white30,
                              size: 34,
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Nombre del canal
                Text(
                  widget.channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),

                const SizedBox(height: 2),

                // Categoría y Calidad
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.channel.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isFocused ? Colors.white70 : Colors.white38,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        widget.channel.quality,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
}
