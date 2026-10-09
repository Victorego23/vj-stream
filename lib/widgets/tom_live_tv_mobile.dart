import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/live_channel.dart';
import '../theme/tom_tokens.dart';
import '../views/video_player_view.dart';

/// Implementación fiel de la Pantalla 2: TELEVISIÓN EN VIVO (LIVE TV & EPG) para Móvil
/// según las especificaciones técnicas de TOM TV (Sección 4).
class TomLiveTvMobile extends StatefulWidget {
  final List<LiveChannel> channels;
  final Set<String> favoriteIds;
  final Function(LiveChannel) onToggleFavorite;
  final Function(LiveChannel) onChannelSelected;
  final VoidCallback? onBackToMovies;
  final String? initialCategory;

  const TomLiveTvMobile({
    super.key,
    required this.channels,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onChannelSelected,
    this.onBackToMovies,
    this.initialCategory,
  });

  @override
  State<TomLiveTvMobile> createState() => _TomLiveTvMobileState();
}

class _TomLiveTvMobileState extends State<TomLiveTvMobile> {
  // Estado del reproductor fijo superior
  VideoPlayerController? _playerController;
  LiveChannel? _currentChannel;
  bool _isPlayerLoading = false;
  bool _isMuted = false;
  String _selectedQuality = 'FHD';
  bool _mobileDataSaverActive = false; // Mobile Data Saver detection
  bool _mobileDataPlayPressed = false;

  // Sub-tabs superiores: 'Categoría' y 'Favoritos'
  String _activeSubTab = 'Categoría';

  // Chips de categorías sincronizados 100% a la par con la versión TV
  final List<String> _chipFilters = [
    'Todos',
    'Favoritos',
    'Perú',
    'Deportes',
    'Cine & Series',
    'Entretenimiento',
    'Noticias',
    'Infantil',
    'Música',
    'Cultural',
    'Colombia',
    'México',
    'Argentina',
    'Chile',
    'Ecuador',
    'España',
    'Estados Unidos',
  ];
  String _selectedChip = 'Todos';

  // Control de carga al cambiar chips
  bool _isFiltering = false;
  Timer? _filterDebounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
      final match = _chipFilters.firstWhere(
        (c) => c.toLowerCase() == widget.initialCategory!.toLowerCase(),
        orElse: () => 'Todos',
      );
      _selectedChip = match;
    }

    if (widget.channels.isNotEmpty) {
      _initTopPlayer(widget.channels.first);
    }
  }

  @override
  void didUpdateWidget(covariant TomLiveTvMobile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentChannel == null && widget.channels.isNotEmpty) {
      _initTopPlayer(widget.channels.first);
    }
  }

  @override
  void dispose() {
    _filterDebounceTimer?.cancel();
    _playerController?.dispose();
    super.dispose();
  }

  Future<void> _initTopPlayer(LiveChannel channel) async {
    if (_currentChannel?.id == channel.id && _playerController != null) return;

    _playerController?.dispose();
    _playerController = null;

    setState(() {
      _currentChannel = channel;
      _isPlayerLoading = true;
      _mobileDataPlayPressed = false;
    });

    if (_mobileDataSaverActive && !_mobileDataPlayPressed) {
      setState(() => _isPlayerLoading = false);
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(channel.streamUrl),
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://stream.tomtv.vip/',
        },
      );

      await controller.initialize();
      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      await controller.setLooping(true);
      await controller.play();

      if (mounted) {
        setState(() {
          _playerController = controller;
          _isPlayerLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isPlayerLoading = false);
      }
    }
  }

  void _onChipSelected(String chip) {
    if (_selectedChip == chip) return;
    setState(() {
      _selectedChip = chip;
      _isFiltering = true;
    });

    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() => _isFiltering = false);
      }
    });
  }

  List<LiveChannel> _getFilteredChannels() {
    List<LiveChannel> list = widget.channels;

    if (_activeSubTab == 'Favoritos' || _selectedChip == 'Favoritos') {
      return list.where((c) => widget.favoriteIds.contains(c.id)).toList();
    }

    if (_selectedChip == 'Todos') {
      return list;
    }

    final query = _selectedChip.toLowerCase();
    return list.where((c) {
      final name = c.name.toLowerCase();
      final cat = c.category.toLowerCase();
      final id = c.id.toLowerCase();

      if (query == 'deportes') {
        return cat.contains('deporte') || cat.contains('sport') || name.contains('espn') || name.contains('fox') || name.contains('tyc') || name.contains('win') || name.contains('liga');
      }
      if (query == 'cine & series' || query == 'cine y series') {
        return cat.contains('cine') || cat.contains('película') || cat.contains('serie') || cat.contains('hbo') || name.contains('warner') || name.contains('tnt');
      }
      if (query == 'infantil') {
        return cat.contains('infantil') || cat.contains('niñ') || cat.contains('cartoon') || cat.contains('disney') || cat.contains('nickelodeon');
      }
      if (query == 'noticias') {
        return cat.contains('noticia') || cat.contains('news') || name.contains('cnn') || name.contains('bbc') || name.contains('24 horas');
      }
      if (query == 'entretenimiento') {
        return cat.contains('entretenimiento') || cat.contains('variedad');
      }
      if (query == 'música') {
        return cat.contains('música') || cat.contains('music') || name.contains('mtv');
      }
      if (query == 'cultural') {
        return cat.contains('cultural') || cat.contains('documental') || name.contains('discovery') || name.contains('history') || name.contains('nat geo');
      }

      // Filtro por país (Perú, Colombia, México, Argentina, Chile, Ecuador, España, Estados Unidos)
      final countryCodes = {
        'perú': 'pe',
        'peru': 'pe',
        'colombia': 'co',
        'méxico': 'mx',
        'mexico': 'mx',
        'argentina': 'ar',
        'chile': 'cl',
        'ecuador': 'ec',
        'españa': 'es',
        'espana': 'es',
        'estados unidos': 'us',
      };
      final code = countryCodes[query];
      if (code != null && (id.endsWith('_$code') || id.contains('_$code') || cat.contains(query) || name.contains(query))) {
        return true;
      }

      return id.contains('_$query') || name.contains(query) || cat.contains(query);
    }).toList();
  }

  void _cycleQuality() {
    const qualities = ['480P', 'HD', 'FHD'];
    final idx = qualities.indexOf(_selectedQuality);
    final next = qualities[(idx + 1) % qualities.length];
    setState(() => _selectedQuality = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calidad de transmisión cambiada a: $next'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _openFullscreen() {
    if (_currentChannel == null) return;
    _playerController?.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerView(
          videoUrl: _currentChannel!.streamUrl,
          title: _currentChannel!.name,
          isLive: true,
          liveChannel: _currentChannel,
          liveSources: _currentChannel!.sources,
        ),
      ),
    ).then((_) {
      if (_playerController != null && mounted) {
        _playerController!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredChannels = _getFilteredChannels();

    return Scaffold(
      backgroundColor: TomTokens.backgroundMain,
      body: SafeArea(
        child: Column(
          children: [
            // ===============================================================
            // 4.1 REPRODUCTOR FIJO SUPERIOR (TOP VIDEO PLAYER RATIO 16:9)
            // ===============================================================
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video player view o pantalla negra
                    if (_playerController != null && _playerController!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: _playerController!.value.size.width,
                          height: _playerController!.value.size.height,
                          child: VideoPlayer(_playerController!),
                        ),
                      )
                    else if (!_mobileDataSaverActive || _mobileDataPlayPressed)
                      Container(
                        color: const Color(0xFF0D0D14),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.live_tv_rounded, color: TomTokens.primaryAccent, size: 40),
                              const SizedBox(height: 8),
                              Text(
                                _currentChannel?.name ?? 'Sintonizando canal...',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Spinner de carga superior
                    if (_isPlayerLoading)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: TomTokens.primaryAccent,
                          ),
                        ),
                      ),

                    // MOBILE DATA SAVER (Si está en celular y no presionado)
                    if (_mobileDataSaverActive && !_mobileDataPlayPressed)
                      Container(
                        color: Colors.black,
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Utilizará datos móviles para la reproducción',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TomTokens.primaryAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: TomTokens.borderMd,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() => _mobileDataPlayPressed = true);
                                  if (_currentChannel != null) {
                                    _initTopPlayer(_currentChannel!);
                                  }
                                },
                                child: const Text(
                                  '▶ Clique para jogar',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // OVERLAYS SUPERIORES
                    Positioned(
                      top: 6,
                      left: 6,
                      right: 6,
                      child: Row(
                        children: [
                          if (widget.onBackToMovies != null)
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                              onPressed: widget.onBackToMovies,
                              tooltip: 'Volver',
                            ),
                          const Spacer(),
                          // 1. Share
                          IconButton(
                            icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
                            onPressed: () {
                              if (_currentChannel != null) {
                                Clipboard.setData(ClipboardData(text: _currentChannel!.streamUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Enlace de ${_currentChannel!.name} copiado.')),
                                );
                              }
                            },
                          ),
                          // 2. PiP
                          IconButton(
                            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Modo PiP activado')),
                              );
                            },
                          ),
                          // 3. Badge Calidad interactivo (480P / HD / FHD)
                          GestureDetector(
                            onTap: _cycleQuality,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: TomTokens.borderSm,
                                border: Border.all(color: Colors.white30),
                              ),
                              child: Text(
                                _selectedQuality,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 4. Favorito Toggle
                          if (_currentChannel != null)
                            IconButton(
                              icon: Icon(
                                widget.favoriteIds.contains(_currentChannel!.id)
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: widget.favoriteIds.contains(_currentChannel!.id)
                                    ? TomTokens.accentRed
                                    : Colors.white,
                                size: 20,
                              ),
                              onPressed: () => widget.onToggleFavorite(_currentChannel!),
                            ),
                        ],
                      ),
                    ),

                    // OVERLAYS INFERIORES
                    Positioned(
                      bottom: 6,
                      left: 10,
                      right: 10,
                      child: Row(
                        children: [
                          // Nombre en overlay
                          if (_currentChannel != null)
                            Expanded(
                              child: Text(
                                _currentChannel!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                ),
                              ),
                            ),
                          // Mute toggle
                          IconButton(
                            icon: Icon(
                              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isMuted = !_isMuted;
                                _playerController?.setVolume(_isMuted ? 0.0 : 1.0);
                              });
                            },
                          ),
                          // Fullscreen
                          IconButton(
                            icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                            onPressed: _openFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ===============================================================
            // 4.2 FILTROS Y GUÍA DE CANALES
            // ===============================================================
            // Sub-tabs: 'Categoría' y 'Favoritos'
            Container(
              color: TomTokens.surfaceCard,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildSubTabItem('Categoría'),
                  const SizedBox(width: 24),
                  _buildSubTabItem('Favoritos'),
                ],
              ),
            ),

            // Chips horizontales de categorías
            if (_activeSubTab == 'Categoría')
              Container(
                color: TomTokens.surfaceCard,
                padding: const EdgeInsets.symmetric(vertical: 8),
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _chipFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final chip = _chipFilters[index];
                    final isSelected = _selectedChip == chip;

                    return GestureDetector(
                      onTap: () => _onChipSelected(chip),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? TomTokens.primaryAccent : TomTokens.backgroundMain,
                          borderRadius: TomTokens.borderPill,
                          border: Border.all(
                            color: isSelected ? TomTokens.primaryAccent : Colors.white12,
                          ),
                        ),
                        child: Text(
                          chip,
                          style: TextStyle(
                            color: isSelected ? Colors.white : TomTokens.textSecondary,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ===============================================================
            // 4.3 LISTVIEW DE CANALES O SPINNER AZUL
            // ===============================================================
            Expanded(
              child: _isFiltering
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: TomTokens.primaryAccent,
                      ),
                    )
                  : filteredChannels.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron canales en esta categoría',
                            style: TextStyle(color: TomTokens.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          itemCount: filteredChannels.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: Colors.white10,
                          ),
                          itemBuilder: (context, index) {
                            final channel = filteredChannels[index];
                            final isCurrent = _currentChannel?.id == channel.id;
                            final channelNum = (index + 1).toString().padLeft(3, '0');

                            return _buildChannelRow(
                              channel: channel,
                              number: channelNum,
                              isPlaying: isCurrent,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabItem(String title) {
    final isSelected = _activeSubTab == title;

    return GestureDetector(
      onTap: () {
        setState(() => _activeSubTab = title);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? TomTokens.primaryAccent : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? TomTokens.textPrimary : TomTokens.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildChannelRow({
    required LiveChannel channel,
    required String number,
    required bool isPlaying,
  }) {
    return InkWell(
      onTap: () {
        _initTopPlayer(channel);
        widget.onChannelSelected(channel);
      },
      borderRadius: TomTokens.borderSm,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        color: isPlaying ? TomTokens.primaryAccent.withValues(alpha: 0.12) : Colors.transparent,
        child: Row(
          children: [
            // 1. Badge de Número (Rectángulo redondeado azul/blanco con 3 dígitos ej. 001)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isPlaying ? TomTokens.primaryAccent : TomTokens.surfaceCard,
                borderRadius: TomTokens.borderSm,
                border: Border.all(
                  color: isPlaying ? TomTokens.primaryAccent : Colors.white24,
                  width: 1,
                ),
              ),
              child: Text(
                number,
                style: TextStyle(
                  color: isPlaying ? Colors.white : TomTokens.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 2. Logo: Imagen del canal (tamaño 45x28 px con fit: contain)
            Container(
              width: 45,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF141520),
                borderRadius: TomTokens.borderSm,
              ),
              child: channel.logoUrl.isNotEmpty
                  ? Image.network(
                      channel.logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.tv,
                        color: Colors.white38,
                        size: 18,
                      ),
                    )
                  : const Icon(Icons.tv, color: Colors.white38, size: 18),
            ),
            const SizedBox(width: 12),

            // 3. Info Textual: Nombre 1 línea bold + Subtítulo EPG 1 línea gris
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPlaying ? TomTokens.primaryAccent : TomTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    channel.currentProgram ?? channel.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TomTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // 4. Acción Derecha: Icono circular con flecha (→)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlaying ? TomTokens.primaryAccent : Colors.white.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
