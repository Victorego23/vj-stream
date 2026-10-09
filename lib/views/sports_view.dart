import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../models/live_channel.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../widgets/xuper_master_launcher.dart';
import 'detail_view.dart';
import 'video_player_view.dart';

/// Sección Exclusiva: ESTADIO TOM TV / FÚTBOL & DEPORTES EN VIVO
/// Arquitectura de Dos Paneles (10-foot UI):
/// - Panel Izquierdo (410px): Filtros superiores + Lista vertical de canales con logo, nombre y badge minimalista LIVE.
/// - Panel Derecho: Reproductor preview 16:9 + Ficha técnica (1080p/720p, 60 FPS, Audio Latino) + Botón Pantalla Completa + Cine Deportivo.
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

  // Filtros
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
  VideoPlayerController? _previewController;
  Timer? _previewDebounceTimer;
  bool _isPreviewLoading = false;
  bool _isPreviewError = false;
  bool _isMuted = true;

  final ValueNotifier<LiveChannel?> _focusedChannelNotifier = ValueNotifier<LiveChannel?>(null);

  final ScrollController _channelListScrollController = ScrollController();
  final ScrollController _filtersScrollController = ScrollController();
  final FocusScopeNode _sportsScopeNode = FocusScopeNode();

  final FocusNode _playButtonFocusNode = FocusNode(debugLabel: 'SportsFullscreenButton');
  final Map<String, FocusNode> _channelFocusNodes = {};
  final Map<String, FocusNode> _filterFocusNodes = {};

  // Animación suave de pulso para el badge "LIVE"
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
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
    _channelListScrollController.dispose();
    _filtersScrollController.dispose();
    _searchController.dispose();
    _playButtonFocusNode.dispose();
    _sportsScopeNode.dispose();
    _focusedChannelNotifier.dispose();
    for (final node in _channelFocusNodes.values) {
      node.dispose();
    }
    for (final node in _filterFocusNodes.values) {
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
                  isFav ? '★ ${channel.name} guardado en favoritos' : 'Eliminado de favoritos',
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
            _focusedChannelNotifier.value = _allSportsChannels.first;
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

  int _getFilterCount(String filter) {
    if (filter == 'Todos') return _allSportsChannels.length;
    if (filter == 'Favoritos') return _allSportsChannels.where((c) => _favoriteIds.contains(c.id)).length;
    if (filter == 'Fútbol Ligas') {
      return _allSportsChannels.where((c) {
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
      }).length;
    }
    if (filter == 'Combate & UFC') {
      return _allSportsChannels.where((c) {
        final name = c.name.toLowerCase();
        return name.contains('ufc') ||
            name.contains('box') ||
            name.contains('combate') ||
            name.contains('fight') ||
            name.contains('wwe');
      }).length;
    }
    if (filter == 'Motor & F1') {
      return _allSportsChannels.where((c) {
        final name = c.name.toLowerCase();
        return name.contains('red bull') ||
            name.contains('f1') ||
            name.contains('motor') ||
            name.contains('auto') ||
            name.contains('moto') ||
            name.contains('extremo');
      }).length;
    }
    return 0;
  }

  String _getFilterIcon(String filter) {
    switch (filter) {
      case 'Todos':
        return '🏆';
      case 'Fútbol Ligas':
        return '⚽';
      case 'Combate & UFC':
        return '🥊';
      case 'Motor & F1':
        return '🏎️';
      case 'Favoritos':
        return '⭐';
      default:
        return '🏅';
    }
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
      if (_focusedChannelNotifier.value?.id != channel.id) return;

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
        if (mounted && _focusedChannelNotifier.value?.id == channel.id) {
          await ctrl.setVolume(_isMuted ? 0.0 : 0.85);
          await ctrl.setLooping(true);
          await ctrl.play();
          setState(() {
            _isPreviewLoading = false;
            _isPreviewError = false;
          });
        }
      } catch (_) {
        if (mounted && _focusedChannelNotifier.value?.id == channel.id) {
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

  FocusNode _getChannelFocusNode(String id) {
    return _channelFocusNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'SportChannel_$id'));
  }

  FocusNode _getFilterFocusNode(String filter) {
    return _filterFocusNodes.putIfAbsent(filter, () => FocusNode(debugLabel: 'SportFilter_$filter'));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = screenWidth > 700;

    return FocusScope(
      node: _sportsScopeNode,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E10),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
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
            const Icon(Icons.sports_soccer_rounded, color: Color(0xFFE50914), size: 54),
            const SizedBox(height: 14),
            Text(
              _errorMessage ?? 'Error',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
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
  // DISEÑO PARA SMART TV (10-FOOT UI: ARQUITECTURA DE DOS PANELES)
  // ===========================================================================
  Widget _buildTvLayout() {
    final channels = _filteredChannels;

    return Column(
      children: [
        // Barra Superior Cinemática Unificada con Reloj y Botón Menú
        _buildTvTopBar(),

        // Contenido Principal de Dos Paneles
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PANEL IZQUIERDO: Pestañas de Sub-Filtros + Lista Vertical Estructurada (Width: 410)
              Container(
                width: 410,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0D14),
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Pestañas Horizontales de Sub-Filtros
                    _buildHorizontalSubFiltersBar(),
                    // Lista Vertical de Canales / Partidos Deportivos
                    Expanded(
                      child: _buildTvChannelsListColumn(channels),
                    ),
                  ],
                ),
              ),

              // PANEL DERECHO: Reproductor Panorámico 16:9 + Ficha Técnica & Controles
              Expanded(
                child: Container(
                  color: const Color(0xFF08090F),
                  child: _buildTvPreviewAndMetadataColumn(channels),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CABECERA SUPERIOR SMART TV
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
          const XuperTomLogo(scale: 0.78),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE50914), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _pulseAnimation,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE50914),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'ESTADIO TOM TV • EN VIVO',
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
          Text(
            '$_selectedSubFilter (${_filteredChannels.length} Señales)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
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

  // ---------------------------------------------------------------------------
  // PANEL IZQUIERDO: SUB-FILTROS HORIZONTALES
  // ---------------------------------------------------------------------------
  Widget _buildHorizontalSubFiltersBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: ListView.separated(
        controller: _filtersScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: _subFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _subFilters[index];
          final isSelected = _selectedSubFilter == filter;
          final count = _getFilterCount(filter);

          return Focus(
            focusNode: _getFilterFocusNode(filter),
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space) {
                  setState(() {
                    _selectedSubFilter = filter;
                  });
                  final channels = _filteredChannels;
                  if (channels.isNotEmpty) {
                    _focusedChannelNotifier.value = channels.first;
                    _triggerPreviewUpdate(channels.first);
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_filteredChannels.isNotEmpty) {
                    final target = _focusedChannelNotifier.value ?? _filteredChannels.first;
                    _getChannelFocusNode(target.id).requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index == 0) {
                  widget.onBackToMovies?.call();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(builder: (ctx) {
              final isFocused = Focus.of(ctx).hasFocus;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSubFilter = filter;
                  });
                  final channels = _filteredChannels;
                  if (channels.isNotEmpty) {
                    _focusedChannelNotifier.value = channels.first;
                    _triggerPreviewUpdate(channels.first);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFE50914)
                        : (isFocused ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isFocused
                          ? Colors.white
                          : (isSelected ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.1)),
                      width: isFocused ? 2.0 : 1.0,
                    ),
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE50914).withValues(alpha: 0.6),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getFilterIcon(filter),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        filter,
                        style: TextStyle(
                          color: isSelected || isFocused ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '($count)',
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PANEL IZQUIERDO: LISTA VERTICAL ESTRUCTURADA DE CANALES
  // ---------------------------------------------------------------------------
  Widget _buildTvChannelsListColumn(List<LiveChannel> channels) {
    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_soccer_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No hay eventos para "$_searchQuery"'
                  : 'No hay señales disponibles en esta sección.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.sports_rounded, color: Color(0xFFE50914), size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'SEÑALES DEPORTIVAS',
                  style: TextStyle(
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
              final isFav = _favoriteIds.contains(channel.id);

              return _TvSportsChannelRowItem(
                key: ValueKey('tv_sport_chan_${channel.id}'),
                channel: channel,
                channelNumber: channelNumber,
                isFavorite: isFav,
                focusNode: _getChannelFocusNode(channel.id),
                pulseAnimation: _pulseAnimation,
                onFocusChange: (focused) {
                  if (focused) {
                    _focusedChannelNotifier.value = channel;
                    _triggerPreviewUpdate(channel);
                  }
                },
                onTap: () => _playChannel(channel),
                onLongPress: () => _toggleFavorite(channel),
                onKeyLeft: () {
                  // Volver al menú colapsable de la app
                  widget.onBackToMovies?.call();
                },
                onKeyRight: () {
                  // Mover foco al botón de Pantalla Completa en el Panel Derecho
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
  // PANEL DERECHO: PREVIEW PANORÁMICO 16:9 + FICHA TÉCNICA + CONTROLES
  // ---------------------------------------------------------------------------
  Widget _buildTvPreviewAndMetadataColumn(List<LiveChannel> channels) {
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

        final isFav = _favoriteIds.contains(channel.id);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
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
                        // Superficie de Video o Fallback
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FadeTransition(
                                  opacity: _pulseAnimation,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
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
                                  setState(() => _isMuted = !_isMuted);
                                  _previewController?.setVolume(_isMuted ? 0.0 : 0.85);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Icon(
                                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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

              // 2. METADATOS TÉCNICOS & ENCABEZADO DEL CANAL ACTIVO
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Grande del Canal
                  Container(
                    width: 54,
                    height: 54,
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
                            errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer_rounded, color: Colors.white38),
                          )
                        : const Icon(Icons.sports_soccer_rounded, color: Colors.white38),
                  ),
                  const SizedBox(width: 14),

                  // Nombre e Información Técnica Exclusiva del Panel Derecho
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
                        const SizedBox(height: 6),
                        // Badges Técnicos: Resolución, 60 FPS, Audio Latino y Fuentes
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildTechBadge(
                              label: channel.quality.isNotEmpty ? channel.quality : '1080p FHD',
                              icon: Icons.hd_rounded,
                              highlight: true,
                            ),
                            _buildTechBadge(
                              label: '60 FPS Estable',
                              icon: Icons.speed_rounded,
                            ),
                            _buildTechBadge(
                              label: 'Audio Latino Oficial',
                              icon: Icons.language_rounded,
                            ),
                            _buildTechBadge(
                              label: '⚡ ${channel.sources.length} ${channel.sources.length == 1 ? "fuente" : "fuentes"}',
                              icon: null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Botón Rápido Favorito
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

              // 3. FICHA DEL EVENTO / PROGRAMA DEPORTIVO
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
                        const Icon(Icons.sports_soccer_rounded, color: Color(0xFFE50914), size: 15),
                        const SizedBox(width: 6),
                        const Text(
                          'EVENTO DEPORTIVO EN EMISIÓN',
                          style: TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'EN DIRECTO',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      channel.currentProgram ?? 'Transmisión Oficial de Fútbol & Ligas en Directo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Señal verificada con conmutación inteligente y balance de carga continuo.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4. BOTÓN PRINCIPAL DE ACCIÓN: VER EN PANTALLA COMPLETA
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
                        height: 50,
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
                              blurRadius: isFocused ? 18 : 8,
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

              const SizedBox(height: 10),
              const Center(
                child: Text(
                  '💡 Presiona OK o Flecha Derecha para pantalla completa con cambio rápido de señales.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),

              // 5. CINE Y DOCUMENTALES DEPORTIVOS (Si existen)
              if (_sportsMovies.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '🎬 CINE Y DOCUMENTALES DEPORTIVOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_sportsMovies.length} Películas',
                      style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sportsMovies.length,
                    itemBuilder: (context, idx) {
                      final movie = _sportsMovies[idx];
                      return _buildMovieCard(movie);
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTechBadge({required String label, IconData? icon, bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFE50914).withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: highlight ? const Color(0xFFE50914).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: highlight ? const Color(0xFFE50914) : Colors.white70),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
              errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer_rounded, color: Colors.white38, size: 48),
            )
          else
            const Icon(Icons.sports_soccer_rounded, color: Colors.white38, size: 48),
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

  Widget _buildMovieCard(MediaItem item) {
    return Container(
      width: 115,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          _previewController?.pause();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailView(item: item),
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

  // ===========================================================================
  // DISEÑO PARA MÓVIL (PANTALLA TÁCTIL, REPRODUCTOR SUPERIOR Y LISTA LIMPIA)
  // ===========================================================================
  Widget _buildMobileLayout() {
    final channels = _filteredChannels;

    return Column(
      children: [
        // Reproductor Superior Fijo (Estilo TV Móvil)
        _buildMobileTopPlayer(),

        // Sub-filtros táctiles limpios
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0C0D14),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            children: [
              // Barra de búsqueda rápida
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
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFE50914), size: 16),
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
                          selectedColor: const Color(0xFFE50914),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
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

        // Lista Táctil Limpia de Canales Deportivos (Sin etiquetas de resolución fijas)
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final ch = channels[idx];
              final isFav = _favoriteIds.contains(ch.id);

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _focusedChannelNotifier.value = ch;
                  _triggerPreviewUpdate(ch);
                  _playChannel(ch);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10121C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ch.logoUrl.isNotEmpty
                            ? Image.network(
                                ch.logoUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer_rounded, color: Colors.white38),
                              )
                            : const Icon(Icons.sports_soccer_rounded, color: Colors.white38),
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
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE50914),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'LIVE',
                                  style: TextStyle(color: Color(0xFFE50914), fontSize: 9, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  ch.category,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
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
                      const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914), size: 28),
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
    return ValueListenableBuilder<LiveChannel?>(
      valueListenable: _focusedChannelNotifier,
      builder: (context, ch, _) {
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
                  const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
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
                            icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFFE50914), size: 26),
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
      },
    );
  }
}

// =============================================================================
// ITEM DE FILA VERTICAL DE CANAL DEPORTIVO PARA SMART TV
// Logo + Nombre + Badge Minimalista LIVE (Sin etiquetas de resolución fijas)
// =============================================================================
class _TvSportsChannelRowItem extends StatefulWidget {
  final LiveChannel channel;
  final int channelNumber;
  final bool isFavorite;
  final FocusNode focusNode;
  final Animation<double> pulseAnimation;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onKeyLeft;
  final VoidCallback onKeyRight;

  const _TvSportsChannelRowItem({
    super.key,
    required this.channel,
    required this.channelNumber,
    required this.isFavorite,
    required this.focusNode,
    required this.pulseAnimation,
    required this.onFocusChange,
    required this.onTap,
    required this.onLongPress,
    required this.onKeyLeft,
    required this.onKeyRight,
  });

  @override
  State<_TvSportsChannelRowItem> createState() => _TvSportsChannelRowItemState();
}

class _TvSportsChannelRowItemState extends State<_TvSportsChannelRowItem> {
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
              // Número de Canal / Orden
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

              // Logo Nítido del Canal / Evento
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF07080C),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(4),
                child: widget.channel.logoUrl.isNotEmpty
                    ? Image.network(
                        widget.channel.logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer_rounded, color: Colors.white38, size: 16),
                      )
                    : const Icon(Icons.sports_soccer_rounded, color: Colors.white38, size: 16),
              ),
              const SizedBox(width: 10),

              // Nombre Claro del Canal / Partido
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

              // Indicador Minimalista LIVE (Punto Rojo sutil o Badge LIVE) + Favorito (Sin 720p/1080p)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isFocused ? Colors.black38 : const Color(0xFFE50914).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _isFocused ? Colors.white38 : const Color(0xFFE50914).withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeTransition(
                          opacity: widget.pulseAnimation,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE50914),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isFavorite) ...[
                    const SizedBox(width: 6),
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
