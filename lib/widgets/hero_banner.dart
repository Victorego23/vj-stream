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
          // Imagen de fondo (Backdrop)
          _buildBackdropImage(),

          // Gradiente vertical oscuro para fundir con la lista de contenidos
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.4, 0.75, 1.0],
                  colors: [
                    Colors.transparent,
                    Color(0x66000000),
                    Color(0xCC000000),
                    Color(0xFF000000),
                  ],
                ),
              ),
            ),
          ),

          // Gradiente lateral izquierdo para asegurar legibilidad de texto en pantallas anchas
          if (isTvOrDesktop)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.5, 1.0],
                    colors: [
                      Color(0xF0000000),
                      Color(0xAA000000),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          // Contenido textual y botones de acción
          Positioned(
            left: isTvOrDesktop ? 48 : 20,
            right: isTvOrDesktop ? size.width * 0.4 : 20,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Etiqueta destacada VJ STREAM
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE50914).withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Text(
                        'VJ STREAM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: const Text(
                        'CALIDAD COMERCIAL 4K',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Título de la película / serie
                Text(
                  item.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTvOrDesktop ? 38 : 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 2)),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                // Metadatos (Puntuación, Año, Calidad 4K, Audio Español)
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.rating > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${item.formattedRating} / 10',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    if (item.releaseYear.isNotEmpty)
                      Text(
                        item.releaseYear,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withValues(alpha: 0.2),
                        border: Border.all(color: const Color(0xFFE50914), width: 0.8),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '4K UHD HDR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: Colors.white38, width: 0.8),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'AUDIO ESPAÑOL DUAL',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Sinopsis
                Text(
                  item.synopsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                  maxLines: isTvOrDesktop ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),

                // Botones interactivos enfocables para Smart TV / Móvil
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
      errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF1B1B1B)),
    );
  }
}

/// Botón con soporte de foco de control remoto y toque táctil para el Hero Banner
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
    final primaryBg = widget.isPrimary ? Colors.white : const Color(0x99565656);
    final primaryTextColor = widget.isPrimary ? Colors.black : Colors.white;

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
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onPressed();
        },
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: BoxDecoration(
              color: _isFocused ? const Color(0xFFE50914) : primaryBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: _isFocused
                  ? [
                      const BoxShadow(
                        color: Color(0x80E50914),
                        blurRadius: 14,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 22,
                  color: _isFocused ? Colors.white : primaryTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : primaryTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
