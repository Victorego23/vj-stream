import 'dart:async';
import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../theme/tom_tokens.dart';

/// Hero Carousel panorámico (16:9 o 2:1) con auto-scroll (3s), gestos swipe e indicador de puntos
/// según la especificación técnica de TOM TV (Sección 3.2).
class TomHeroCarousel extends StatefulWidget {
  final List<MediaItem> items;
  final Function(MediaItem) onPlay;
  final Function(MediaItem) onDetails;

  const TomHeroCarousel({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onDetails,
  });

  @override
  State<TomHeroCarousel> createState() => _TomHeroCarouselState();
}

class _TomHeroCarouselState extends State<TomHeroCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(covariant TomHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (widget.items.length <= 1) return;

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % widget.items.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pauseAndRestartTimer() {
    _autoScrollTimer?.cancel();
    _startAutoScroll();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final displayItems = widget.items.take(8).toList();

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          // Slider de páginas
          GestureDetector(
            onPanDown: (_) => _autoScrollTimer?.cancel(),
            onPanEnd: (_) => _startAutoScroll(),
            onPanCancel: () => _startAutoScroll(),
            child: PageView.builder(
              controller: _pageController,
              itemCount: displayItems.length,
              onPageChanged: (idx) {
                setState(() => _currentPage = idx);
                _pauseAndRestartTimer();
              },
              itemBuilder: (context, index) {
                final item = displayItems[index];
                return _buildSlide(item);
              },
            ),
          ),

          // Indicador inferior de puntos (dots)
          Positioned(
            bottom: 12,
            right: 18,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(displayItems.length, (idx) {
                final isActive = idx == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(MediaItem item) {
    final bgUrl = item.backdropLarge ?? item.backdropMedium ?? item.posterOriginal ?? '';

    return GestureDetector(
      onTap: () => widget.onDetails(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen de fondo
          if (bgUrl.isNotEmpty)
            Image.network(
              bgUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: TomTokens.surfaceCard),
            )
          else
            Container(color: TomTokens.surfaceCard),

          // Gradiente cinematográfico superior e inferior
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 0.85, 1.0],
                colors: [
                  Colors.transparent,
                  Color(0x33101018),
                  Color(0xCC101018),
                  TomTokens.backgroundMain,
                ],
              ),
            ),
          ),

          // Gradiente lateral izquierdo
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, 0.65],
                colors: [
                  Color(0xDD101018),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Contenido textual y botón play
          Positioned(
            left: 18,
            right: 80,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge Tipo / Destacado
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: TomTokens.primaryAccent,
                        borderRadius: TomTokens.borderSm,
                      ),
                      child: Text(
                        item.mediaType == 'tv' ? 'SERIE VIP' : 'ESTRENO HD',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (item.rating > 0) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        item.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Título
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TomTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                if (item.synopsis.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.synopsis,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TomTokens.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
