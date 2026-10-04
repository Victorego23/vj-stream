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
                Container(
                  width: 4,
                  height: isTv ? 22 : 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66E50914),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTv ? 21 : 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFFE50914),
                  size: 13,
                ),
              ],
            ),
          ),

          // Carrusel horizontal con margen seguro para la escala de enfoque
          SizedBox(
            height: rowCardHeight + 46, // Espacio holgado para la escala (1.10) y halo de neón en foco
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 42.0 : 14.0),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 600,
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
