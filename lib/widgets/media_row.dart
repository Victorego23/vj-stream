import 'package:flutter/material.dart';
import '../models/media_item.dart';
import 'tv_focusable_card.dart';

/// Fila horizontal deslizable de películas o series (Estilo carrusel Netflix).
/// Soporta navegación con D-Pad de Smart TV y gestos de desplazamiento táctil.
class MediaRow extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final Function(MediaItem) onItemTap;
  final double cardWidth;
  final double cardHeight;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
    this.cardWidth = 140,
    this.cardHeight = 210,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final isTv = MediaQuery.of(context).size.width > 700;
    final rowCardWidth = isTv ? 160.0 : cardWidth;
    final rowCardHeight = isTv ? 240.0 : cardHeight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título de la fila / categoría
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0, vertical: 8.0),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: isTv ? 20 : 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFFE50914),
                  size: 14,
                ),
              ],
            ),
          ),

          // Carrusel horizontal con margen seguro para la escala de enfoque
          SizedBox(
            height: rowCardHeight + 36, // Espacio holgado para el efecto de escala (1.08) y márgenes en foco
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 42.0 : 14.0),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return TvFocusableCard(
                  item: item,
                  width: rowCardWidth,
                  height: rowCardHeight,
                  onTap: () => onItemTap(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
