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

/// Sección Exclusiva: FÚTBOL & DEPORTES de TOM TV
/// Muestra únicamente canales de deportes (ESPN, Fox Sports, TyC, Liga 1, etc.)
/// junto con la cartelera cinematográfica deportiva oficial, sin mezclar canales generales de TV.
class SportsView extends StatefulWidget {
  final VoidCallback? onBackToMovies;

  const SportsView({super.key, this.onBackToMovies});

  @override
  State<SportsView> createState() => _SportsViewState();
}

class _SportsViewState extends State<SportsView> {
  final ApiService _apiService = ApiService();

  static const String _favsKey = 'tom_sports_fav_channel_ids';
  Set<String> _favoriteIds = {};

  List<LiveChannel> _allSportsChannels = [];
  List<MediaItem> _sportsMovies = [];

  String _selectedSubFilter = 'Todos'; // 'Todos', 'Fútbol', 'Motor & Extremos', 'Favoritos'
  final List<String> _subFilters = ['Todos', 'Fútbol', 'Motor & Extremos', 'Favoritos'];

  bool _isLoading = true;
  String? _errorMessage;

  // Mini-Reproductor para TV y cabecera móvil
  LiveChannel? _focusedChannel;
  VideoPlayerController? _previewController;
  Timer? _previewDebounceTimer;
  bool _isPreviewLoading = false;
  bool _isPreviewError = false;
  bool _isMuted = true;

  final ScrollController _scrollController = ScrollController();
  final FocusScopeNode _sportsScopeNode = FocusScopeNode();
  final Map<String, FocusNode> _channelFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadSportsData();
  }

  @override
  void dispose() {
    _previewDebounceTimer?.cancel();
    _previewController?.dispose();
    _scrollController.dispose();
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
            content: Text(
              isFav ? '★ ${channel.name} añadido a Favoritos Deportivos' : 'Eliminado de Favoritos',
              style: const TextStyle(color: Colors.white),
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
          _errorMessage = 'No se pudo cargar la sección deportiva.';
          _isLoading = false;
        });
      }
    }
  }

  List<LiveChannel> get _filteredChannels {
    if (_selectedSubFilter == 'Favoritos') {
      return _allSportsChannels.where((c) => _favoriteIds.contains(c.id)).toList();
    }
    if (_selectedSubFilter == 'Fútbol') {
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
            name.contains('fútbol') ||
            name.contains('futbol');
      }).toList();
    }
    if (_selectedSubFilter == 'Motor & Extremos') {
      return _allSportsChannels.where((c) {
        final name = c.name.toLowerCase();
        return name.contains('red bull') ||
            name.contains('f1') ||
            name.contains('motor') ||
            name.contains('auto') ||
            name.contains('moto') ||
            name.contains('extremo');
      }).toList();
    }
    return _allSportsChannels;
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

    _previewDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
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
        backgroundColor: const Color(0xFF07080D),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00E676)),
                    SizedBox(height: 16),
                    Text(
                      'Sintonizando transmisiones deportivas...',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sports_soccer_rounded, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'Error', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
            onPressed: _loadSportsData,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
        // Barra Superior Deportiva con Reloj y Volver
        _buildTvTopBar(),

        // Contenido Principal
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Columna Izquierda: Filtros y Grilla de Canales Deportivos
              Expanded(
                flex: 7,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // Sub-filtros
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                        child: Row(
                          children: _subFilters.map((filter) {
                            final isSel = _selectedSubFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: InkWell(
                                onTap: () {
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
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.08),
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
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    // Grilla de Canales de Deportes
                    if (channels.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'No hay canales en este filtro.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1.7,
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

                    // Fila Opcional: Películas y Especiales Deportivos
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
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 190,
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

              // Columna Derecha: Mini-Reproductor en Tiempo Real & Ficha Deportiva (Flex 5)
              Container(
                width: 380,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0D14),
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
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF00E676), width: 0.9),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_soccer_rounded, color: Color(0xFF00E676), size: 12),
                SizedBox(width: 5),
                Text(
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
            '${_allSportsChannels.length} Canales Deportivos Activos',
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
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF131926) : const Color(0xFF0F111A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.07),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    )
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
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
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
                    const SizedBox(height: 4),
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
                          style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
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
        child: Text('Selecciona un canal', style: TextStyle(color: Colors.white54)),
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
                border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    blurRadius: 20,
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
                  // Overlay: Badges y Audio Toggle
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'EN VIVO 4K',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
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

          // Título del Canal Deportivo
          Text(
            ch.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ch.quality,
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Audio Latino Oficial', style: TextStyle(color: Colors.white54, fontSize: 11)),
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
              elevation: 6,
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

        // Barra de Sub-Filtros Rápidos
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0D14),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _subFilters.map((filter) {
              final isSel = _selectedSubFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: isSel,
                    selectedColor: const Color(0xFF00E676),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    labelStyle: TextStyle(
                      color: isSel ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedSubFilter = filter);
                      }
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Lista de Canales Deportivos + Películas
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final ch = channels[idx];
              final isSelected = _focusedChannel?.id == ch.id;
              final isFav = _favoriteIds.contains(ch.id);

              return InkWell(
                onTap: () {
                  setState(() {
                    _focusedChannel = ch;
                    _triggerPreviewUpdate(ch);
                  });
                  _playChannel(ch);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
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
                        width: 48,
                        height: 48,
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
                      const SizedBox(width: 12),
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
                                Text(ch.quality, style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
                        ch?.name ?? 'Deportes TOM TV',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ch != null)
                      IconButton(
                        icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
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
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
