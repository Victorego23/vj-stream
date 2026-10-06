import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../models/live_channel.dart';
import '../services/api_service.dart';
import '../widgets/xuper_master_launcher.dart';
import '../widgets/tom_live_tv_mobile.dart';
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
  List<String> _categories = ['Todos', 'Favoritos', 'Recientes'];
  late String _selectedCategory;
  bool _isLoading = true;
  String? _errorMessage;

  // Mini-Reproductor en tiempo real para Smart TV (Columna 3 Xuper TV)
  VideoPlayerController? _previewController;
  Timer? _previewDebounceTimer;
  bool _isPreviewLoading = false;
  bool _isPreviewError = false;
  bool _isMiniPlayerMuted = true;

  final ValueNotifier<LiveChannel?> _focusedChannelNotifier = ValueNotifier<LiveChannel?>(null);
  final FocusScopeNode _channelGridScopeNode = FocusScopeNode();
  final FocusScopeNode _sidebarScopeNode = FocusScopeNode();
  final FocusNode _returnToMoviesFocusNode = FocusNode(debugLabel: 'TvReturnToMovies');
  final FocusNode _playButtonFocusNode = FocusNode(debugLabel: 'TvPlayButton');
  final FocusNode _favButtonFocusNode = FocusNode(debugLabel: 'TvFavButton');
  final FocusNode _backToMoviesSidebarFocusNode = FocusNode(debugLabel: 'TvCat_BackToMovies');
  final Map<String, FocusNode> _categoryFocusNodes = {};
  final Map<String, FocusNode> _channelFocusNodes = {};
  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();
  final ScrollController _channelListScrollController = ScrollController();
  bool _showBackToTop = false;

  FocusNode _getCategoryFocusNode(String cat) {
    return _categoryFocusNodes.putIfAbsent(cat, () => FocusNode(debugLabel: 'TvCat_$cat'));
  }

  FocusNode _getChannelFocusNode(String id) {
    return _channelFocusNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'TvChan_$id'));
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _channelGridScopeNode.requestFocus();
      }
    });
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
      _triggerPreviewUpdate(_filteredChannels.first);
    }
  }

  void _jumpToSidebar() {
    widget.onBackToMovies?.call();
  }

  @override
  void dispose() {
    _disposePreviewPlayer();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _categoriesScrollController.dispose();
    _channelListScrollController.dispose();
    _channelGridScopeNode.dispose();
    _sidebarScopeNode.dispose();
    _returnToMoviesFocusNode.dispose();
    _playButtonFocusNode.dispose();
    _favButtonFocusNode.dispose();
    _backToMoviesSidebarFocusNode.dispose();
    _focusedChannelNotifier.dispose();
    for (final node in _categoryFocusNodes.values) {
      node.dispose();
    }
    for (final node in _channelFocusNodes.values) {
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
              .where((c) => c != 'Todos' && c != 'Favoritos' && c != 'Recientes' && !c.contains('Peruanos') && !c.contains('Perú'))
              .toList();
          _categories = ['Todos', 'Favoritos', 'Recientes', ...cleanCats];
          _isLoading = false;
          if (_filteredChannels.isNotEmpty) {
            _focusedChannelNotifier.value = _filteredChannels.first;
            _triggerPreviewUpdate(_filteredChannels.first);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _channelGridScopeNode.requestFocus();
              }
            });
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

  void _triggerPreviewUpdate(LiveChannel? channel) {
    _previewDebounceTimer?.cancel();
    if (channel == null || channel.streamUrl.isEmpty) {
      _disposePreviewPlayer();
      return;
    }

    if (mounted) {
      setState(() {
        _isPreviewLoading = true;
        _isPreviewError = false;
      });
    }

    _previewDebounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      if (_focusedChannelNotifier.value?.id != channel.id) return;

      try {
        final oldController = _previewController;
        _previewController = null;
        if (oldController != null) {
          await oldController.dispose();
        }

        final controller = VideoPlayerController.networkUrl(
          Uri.parse(channel.streamUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _previewController = controller;
        await controller.initialize();
        if (mounted && _focusedChannelNotifier.value?.id == channel.id) {
          await controller.setVolume(_isMiniPlayerMuted ? 0.0 : 0.8);
          await controller.setLooping(true);
          await controller.play();
          setState(() {
            _isPreviewLoading = false;
            _isPreviewError = false;
          });
        }
      } catch (e) {
        if (mounted && _focusedChannelNotifier.value?.id == channel.id) {
          setState(() {
            _isPreviewLoading = false;
            _isPreviewError = true;
          });
        }
      }
    });
  }

  void _disposePreviewPlayer() {
    _previewDebounceTimer?.cancel();
    _previewController?.dispose();
    _previewController = null;
  }

  int _getCategoryCount(String cat) {
    if (cat == 'Todos') return _allChannels.length;
    if (cat == 'Favoritos') return _favoriteChannelIds.length;
    if (cat == 'Recientes') return _recentChannelIds.length;
    return _allChannels.where((c) => c.category.toLowerCase() == cat.toLowerCase()).length;
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
      if (_selectedCategory == 'Todos') {
        return true;
      } else if (_selectedCategory == 'Favoritos') {
        return _favoriteChannelIds.contains(channel.id);
      } else {
        return channel.category.toLowerCase() == _selectedCategory.toLowerCase();
      }
    }).toList();
  }

  String _getCategoryIcon(String cat) {
    if (cat == 'Todos') return '🌐 ';
    if (cat == 'Favoritos') return '⭐ ';
    if (cat == 'Recientes') return '🕒 ';
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
    _previewController?.pause();
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
      if (mounted) {
        _loadFavoritesAndRecents();
        _triggerPreviewUpdate(_focusedChannelNotifier.value ?? channel);
      }
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
  // LAYOUT XUPER TV / MAGIS TV: GUÍA DE 3 COLUMNAS CON MINI-PLAYER EN TIEMPO REAL
  // [ COLUMNA 1: CATEGORÍAS | COLUMNA 2: CANALES | COLUMNA 3: PREVIEW & EPG ]
  // ===========================================================================
  Widget _buildTvLayout() {
    final channels = _filteredChannels;

    return Column(
      children: [
        // 1. Barra Superior Xuper TV (Status, Categoría, Reloj Digital en Vivo y Volver)
        _buildTvTopBar(),

        // 2. Guía Principal de 3 Columnas
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                )
              : _errorMessage != null
                  ? _buildErrorView()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Columna 1: Panel de Categorías Verticales (~215px)
                        Container(
                          width: 215,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C0D14),
                            border: Border(
                              right: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: _buildTvCategoriesColumn(),
                        ),

                        // Columna 2: Lista Vertical de Canales (~330px)
                        Container(
                          width: 330,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1018),
                            border: Border(
                              right: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: _buildTvChannelsListColumn(channels),
                        ),

                        // Columna 3: Mini-Player en Vivo + Ficha Técnica EPG (Flex 1)
                        Expanded(
                          child: Container(
                            color: const Color(0xFF08090F),
                            child: _buildTvPreviewAndEpgColumn(channels),
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CABECERA SUPERIOR XUPER TV
  // ---------------------------------------------------------------------------
  Widget _buildTvTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF090A10),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo TOM TV oficial estilo Xuper TV
          const XuperTomLogo(scale: 0.78),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE50914), width: 0.8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fiber_manual_record, color: Color(0xFFE50914), size: 8),
                SizedBox(width: 5),
                Text(
                  'GUÍA TV EN VIVO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Conteo de la categoría activa
          Text(
            '$_selectedCategory (${_filteredChannels.length} Canales)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Reloj digital en vivo Xuper TV con segundero
          const XuperLiveClock(),
          const SizedBox(width: 16),
          // Botón Regresar a Películas
          if (widget.onBackToMovies != null)
            _TvTopBarBackButton(onTap: widget.onBackToMovies!),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COLUMNA 1: PANEL VERTICAL DE CATEGORÍAS
  // ---------------------------------------------------------------------------
  Widget _buildTvCategoriesColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFFE50914), size: 16),
              const SizedBox(width: 8),
              const Text(
                'CATEGORÍAS',
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_allChannels.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView.builder(
            controller: _categoriesScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategory.toLowerCase() == cat.toLowerCase();
              final count = _getCategoryCount(cat);

              return _TvCategoryItem(
                key: ValueKey('TvCat_$cat'),
                title: cat,
                icon: _getCategoryIcon(cat),
                isSelected: isSelected,
                badgeCount: count,
                focusNode: _getCategoryFocusNode(cat),
                onSelect: () {
                  setState(() {
                    _selectedCategory = cat;
                  });
                  final channels = _filteredChannels;
                  if (channels.isNotEmpty) {
                    _focusedChannelNotifier.value = channels.first;
                    _triggerPreviewUpdate(channels.first);
                  }
                },
                onKeyRight: () {
                  // Mover foco a la lista de canales (Columna 2)
                  if (_filteredChannels.isNotEmpty) {
                    final targetChan = _focusedChannelNotifier.value ?? _filteredChannels.first;
                    _getChannelFocusNode(targetChan.id).requestFocus();
                  }
                },
                onBackToMovies: widget.onBackToMovies,
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COLUMNA 2: LISTA VERTICAL DE CANALES
  // ---------------------------------------------------------------------------
  Widget _buildTvChannelsListColumn(List<LiveChannel> channels) {
    if (channels.isEmpty) {
      return _buildEmptyView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.format_list_bulleted_rounded, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CANALES EN VIVO',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Text(
                '${channels.length}',
                style: const TextStyle(
                  color: Color(0xFFE50914),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView.builder(
            controller: _channelListScrollController,
            cacheExtent: 1000,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              final channelNumber = index + 1;
              final isFav = _favoriteChannelIds.contains(channel.id);

              return _TvChannelListRowItem(
                key: ValueKey('tv_chan_${channel.id}'),
                channel: channel,
                channelNumber: channelNumber,
                isFavorite: isFav,
                focusNode: _getChannelFocusNode(channel.id),
                onFocusChange: (focused) {
                  if (focused) {
                    _focusedChannelNotifier.value = channel;
                    _triggerPreviewUpdate(channel);
                  }
                },
                onTap: () => _playChannel(channel),
                onLongPress: () => _toggleFavorite(channel),
                onKeyLeft: () {
                  // Mover foco a la categoría seleccionada en Columna 1
                  _getCategoryFocusNode(_selectedCategory).requestFocus();
                },
                onKeyRight: () {
                  // Mover foco al botón de Pantalla Completa en Columna 3
                  _playButtonFocusNode.requestFocus();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COLUMNA 3: PREVIEW MINI-PLAYER EN TIEMPO REAL & FICHA TÉCNICA EPG
  // ---------------------------------------------------------------------------
  Widget _buildTvPreviewAndEpgColumn(List<LiveChannel> channels) {
    return ValueListenableBuilder<LiveChannel?>(
      valueListenable: _focusedChannelNotifier,
      builder: (context, currentFocused, _) {
        final channel = currentFocused ?? (channels.isNotEmpty ? channels.first : null);
        if (channel == null) {
          return const Center(
            child: Text(
              'Selecciona un canal para sintonizar',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          );
        }

        final isFav = _favoriteChannelIds.contains(channel.id);
        final currentMinutes = DateTime.now().minute;
        final progress = (currentMinutes / 60.0).clamp(0.1, 0.95);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. MINI-PLAYER EN TIEMPO REAL (16:9)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF05060A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Superficie de Video o Fallback de Sintonización
                        if (_previewController != null &&
                            _previewController!.value.isInitialized &&
                            !_isPreviewLoading)
                          VideoPlayer(_previewController!)
                        else
                          _buildMiniPlayerFallback(channel),

                        // Overlay con click para Pantalla Completa
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _playChannel(channel),
                            child: Container(),
                          ),
                        ),

                        // Badge EN DIRECTO en la esquina superior izquierda
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x88E50914),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
                                SizedBox(width: 4),
                                Text(
                                  'EN DIRECTO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Botón de audio y badge de calidad en la esquina superior derecha
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() => _isMiniPlayerMuted = !_isMiniPlayerMuted);
                                  _previewController?.setVolume(_isMiniPlayerMuted ? 0.0 : 0.8);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Icon(
                                    _isMiniPlayerMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                    color: Colors.white70,
                                    size: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.white24, width: 0.8),
                                ),
                                child: Text(
                                  channel.quality,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Icono central sutil para pantalla completa
                        Center(
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30, width: 1.5),
                              ),
                              child: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // 2. METADATOS DEL CANAL
              Row(
                children: [
                  // Logo del canal grande
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F101A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: channel.logoUrl.isNotEmpty
                        ? Image.network(
                            channel.logoUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38),
                          )
                        : const Icon(Icons.tv_rounded, color: Colors.white38),
                  ),
                  const SizedBox(width: 14),

                  // Nombre e info del canal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                channel.category,
                                style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '⚡ ${channel.sources.length} ${channel.sources.length == 1 ? "fuente" : "fuentes"}',
                              style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Botón rápido Favorito
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFav ? Colors.amber : Colors.white38,
                      size: 28,
                    ),
                    tooltip: isFav ? 'Quitar de Favoritos' : 'Añadir a Favoritos',
                    onPressed: () => _toggleFavorite(channel),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 3. GUÍA DE PROGRAMACIÓN ACTUAL (EPG SIMULADO)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10121D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, color: Colors.amber, size: 15),
                        const SizedBox(width: 6),
                        const Text(
                          'PROGRAMA EN EMISIÓN',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${DateTime.now().hour}:00 - ${(DateTime.now().hour + 1) % 24}:00',
                          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      channel.currentProgram ?? 'Transmisión Oficial en Vivo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progress * 100).toInt()}% transcurrido',
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        const Text(
                          'A continuación: Programación Regular',
                          style: TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4. BOTÓN GIGANTE ACCIÓN: VER EN PANTALLA COMPLETA
              Focus(
                focusNode: _playButtonFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.space) {
                      _playChannel(channel);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      _getChannelFocusNode(channel.id).requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (ctx) {
                    final isFocused = Focus.of(ctx).hasFocus;
                    return InkWell(
                      onTap: () => _playChannel(channel),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE50914), Color(0xFF990000)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFocused ? Colors.white : Colors.transparent,
                            width: isFocused ? 2.5 : 0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE50914).withValues(alpha: isFocused ? 0.8 : 0.4),
                              blurRadius: isFocused ? 16 : 8,
                              spreadRadius: isFocused ? 2 : 0,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'VER EN PANTALLA COMPLETA (OK)',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 0.8,
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
      },
    );
  }

  Widget _buildMiniPlayerFallback(LiveChannel channel) {
    if (_isPreviewLoading) {
      return Container(
        color: const Color(0xFF08090F),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 3),
            ),
            const SizedBox(height: 12),
            Text(
              'Sintonizando ${channel.name}...',
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF08090F),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (channel.logoUrl.isNotEmpty)
            Image.network(
              channel.logoUrl,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 48),
            )
          else
            const Icon(Icons.tv_rounded, color: Colors.white38, size: 48),
          const SizedBox(height: 10),
          Text(
            channel.name,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Presiona OK para ver en pantalla completa',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LAYOUT MÓVIL / PANTALLA ESTRECHA (LIMPIO, SIN BARRA DE BÚSQUEDA)
  // ===========================================================================
  Widget _buildMobileLayout() {
    return TomLiveTvMobile(
      channels: _allChannels,
      favoriteIds: _favoriteChannelIds,
      initialCategory: widget.initialCategory ?? _selectedCategory,
      onToggleFavorite: _toggleFavorite,
      onChannelSelected: (channel) {
        _recordRecentChannel(channel.id);
      },
      onBackToMovies: widget.onBackToMovies,
    );
  }

  Widget _buildLegacyMobileLayout() {
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
            if (channel.currentProgram != null && channel.currentProgram!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '🔴 ${channel.currentProgram!}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
    super.key,
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
// WIDGET ITEM CANAL VERTICAL FOCUSABLE PARA SMART TV (COLUMNA 2 XUPER TV)
// =============================================================================
class _TvChannelListRowItem extends StatefulWidget {
  final LiveChannel channel;
  final int channelNumber;
  final bool isFavorite;
  final FocusNode focusNode;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onKeyLeft;
  final VoidCallback onKeyRight;

  const _TvChannelListRowItem({
    super.key,
    required this.channel,
    required this.channelNumber,
    required this.isFavorite,
    required this.focusNode,
    required this.onFocusChange,
    required this.onTap,
    required this.onLongPress,
    required this.onKeyLeft,
    required this.onKeyRight,
  });

  @override
  State<_TvChannelListRowItem> createState() => _TvChannelListRowItemState();
}

class _TvChannelListRowItemState extends State<_TvChannelListRowItem> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      final f = widget.focusNode.hasFocus;
      setState(() => _isFocused = f);
      widget.onFocusChange(f);
      if (f) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 60),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onKeyLeft();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onKeyRight();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onTap();
        },
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: _isFocused
                ? const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFF990000)],
                  )
                : null,
            color: _isFocused ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? const [
                    BoxShadow(
                      color: Color(0x66E50914),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Número de canal
              Container(
                width: 34,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isFocused ? Colors.black38 : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '#${widget.channelNumber.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Logo miniatura
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF07080C),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(4),
                child: widget.channel.logoUrl.isNotEmpty
                    ? Image.network(
                        widget.channel.logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 16),
                      )
                    : const Icon(Icons.tv_rounded, color: Colors.white38, size: 16),
              ),
              const SizedBox(width: 10),

              // Nombre y programa/categoría
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: _isFocused ? FontWeight.w900 : FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.channel.currentProgram ?? widget.channel.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isFocused ? Colors.white70 : Colors.white38,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Calidad y Favorito
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: _isFocused ? Colors.black26 : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.channel.quality,
                      style: TextStyle(
                        color: _isFocused ? Colors.white : Colors.white60,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.isFavorite) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BOTÓN DE VOLVER FOCUSABLE PARA CABECERA TV
// =============================================================================
class _TvTopBarBackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TvTopBarBackButton({required this.onTap});

  @override
  State<_TvTopBarBackButton> createState() => _TvTopBarBackButtonState();
}

class _TvTopBarBackButtonState extends State<_TvTopBarBackButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isFocused ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _isFocused ? Colors.white : Colors.white12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                'Volver',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
