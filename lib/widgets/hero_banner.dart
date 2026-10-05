import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';

/// Banner superior flotante destacado (Hero Section) estilo Netflix.
/// Totalmente compatible con D-Pad de Smart TV y dispositivos táctiles.
class HeroBanner extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  const HeroBanner({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTvOrDesktop = size.width > 700;
    final bannerHeight = isTvOrDesktop ? size.height * 0.65 : size.height * 0.55;

    return SizedBox(
      height: bannerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen de fondo con transición suave de cross-fade (Backdrop)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            child: KeyedSubtree(
              key: ValueKey('hero_bg_${item.id}'),
              child: SizedBox.expand(child: _buildBackdropImage()),
            ),
          ),

          // Gradiente vertical oscuro con fundido teatral profundo
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.35, 0.65, 0.90, 1.0],
                  colors: [
                    Colors.transparent,
                    Color(0x3307080B),
                    Color(0x8807080B),
                    Color(0xEE07080B),
                    Color(0xFF07080B),
                  ],
                ),
              ),
            ),
          ),

          // Gradiente lateral izquierdo para asegurar legibilidad cinematográfica
          if (isTvOrDesktop)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.45, 0.85],
                    colors: [
                      Color(0xFA07080B),
                      Color(0xBB07080B),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          // Contenido textual y botones de acción
          Positioned(
            left: isTvOrDesktop ? 48 : 20,
            right: isTvOrDesktop ? size.width * 0.38 : 20,
            bottom: isTvOrDesktop ? 34 : 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey('hero_text_${item.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Insignia Exclusiva TOM TV
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFF990000)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withValues(alpha: 0.6),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'TOM TV EXCLUSIVO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x2238BDF8),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x6638BDF8), width: 0.8),
                          ),
                          child: const Text(
                            'ESTRENO',
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Título de la película / serie con sombra cinematográfica
                    Text(
                      item.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTvOrDesktop ? 40 : 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        height: 1.15,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 16, offset: Offset(0, 3)),
                          Shadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 8)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

                    // Metadatos (Puntuación dorada, Año, 4K UHD, Audio Latino)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.rating > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x33F59E0B),
                              border: Border.all(color: const Color(0x80F59E0B), width: 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${item.formattedRating} / 10',
                                  style: const TextStyle(
                                    color: Color(0xFFFBBF24),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (item.releaseYear.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              border: Border.all(color: Colors.white24, width: 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.releaseYear,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x26E50914),
                            border: Border.all(color: const Color(0x80E50914), width: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '4K ULTRA HD',
                            style: TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x2210B981),
                            border: Border.all(color: const Color(0x6610B981), width: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'AUDIO LATINO 5.1',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Sinopsis
                    Text(
                      item.synopsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: isTvOrDesktop ? 14 : 13,
                        height: 1.45,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 6),
                        ],
                      ),
                      maxLines: isTvOrDesktop ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),

                    // Botones interactivos modernos estilo cine
                    Row(
                      children: [
                        _TvHeroButton(
                          label: 'Reproducir',
                          icon: Icons.play_arrow_rounded,
                          isPrimary: true,
                          onPressed: onPlay,
                        ),
                        const SizedBox(width: 14),
                        _TvHeroButton(
                          label: 'Más información',
                          icon: Icons.info_outline_rounded,
                          isPrimary: false,
                          onPressed: onDetails,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropImage() {
    final backdropUrl = item.bestBackdropUrl;
    if (backdropUrl.isEmpty) {
      return Container(color: const Color(0xFF1B1B1B));
    }

    return Image.network(
      backdropUrl,
      fit: BoxFit.cover,
      cacheWidth: 1280,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF1B1B1B)),
    );
  }
}

/// Botón con soporte de foco de control remoto y toque táctil estilo cine moderno
class _TvHeroButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _TvHeroButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  State<_TvHeroButton> createState() => _TvHeroButtonState();
}

class _TvHeroButtonState extends State<_TvHeroButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Colores según estado y tipo de botón (primario con gradiente carmesí o secundario de cristal)
    final isPrimary = widget.isPrimary;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onPressed();
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
            if (moved) return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final moved = node.focusInDirection(TraversalDirection.left);
            if (moved) return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            final moved = node.focusInDirection(TraversalDirection.right);
            if (moved) return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onPressed();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.09 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            decoration: BoxDecoration(
              gradient: isPrimary
                  ? (_isFocused
                      ? const LinearGradient(colors: [Color(0xFFFF1E27), Color(0xFFE50914)])
                      : const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB20710)]))
                  : null,
              color: isPrimary
                  ? null
                  : (_isFocused ? Colors.white : const Color(0x38FFFFFF)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : (isPrimary ? Colors.transparent : const Color(0x40FFFFFF)),
                width: _isFocused ? 2.2 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: isPrimary
                            ? const Color(0xFFE50914).withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.6),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: isPrimary
                            ? const Color(0x55E50914)
                            : Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 22,
                  color: isPrimary
                      ? Colors.white
                      : (_isFocused ? Colors.black : Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: isPrimary
                        ? Colors.white
                        : (_isFocused ? Colors.black : Colors.white),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.4,
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
