import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../theme/tom_tokens.dart';

/// Fila horizontal de contenido (Content Carousel) según Sección 3.3
class TomContentRow extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final Function(MediaItem) onItemTap;
  final VoidCallback? onMoreTap;

  const TomContentRow({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera de fila: Título bold + botón '...' a la derecha
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TomTokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onMoreTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: const Icon(
                      Icons.more_horiz_rounded,
                      color: TomTokens.textSecondary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Carrusel de Posters (Aspect Ratio 2:3)
          SizedBox(
            height: 205,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildPosterCard(item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterCard(MediaItem item) {
    final posterUrl = item.posterMedium ?? item.posterThumbnail ?? item.posterOriginal ?? '';
    final isSeries = item.mediaType == 'tv';

    // Generar badge dinámico para series
    String badgeText = '';
    if (isSeries) {
      if (item.statusBadge != null && item.statusBadge!.isNotEmpty) {
        badgeText = item.statusBadge!;
      } else {
        badgeText = 'T1';
      }
    }

    return GestureDetector(
      onTap: () => onItemTap(item),
      child: SizedBox(
        width: 105,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster 2:3 con radio radius_md (12px)
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: TomTokens.borderMd,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl.isNotEmpty)
                      Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: TomTokens.surfaceCard,
                          child: const Icon(Icons.movie_outlined, color: Colors.white24),
                        ),
                      )
                    else
                      Container(
                        color: TomTokens.surfaceCard,
                        child: const Icon(Icons.movie_outlined, color: Colors.white24),
                      ),

                    // Gradiente inferior para legibilidad del badge
                    if (isSeries)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 32,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                        ),
                      ),

                    // Badge translúcido flotante inferior para serie
                    if (isSeries)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: TomTokens.borderSm,
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: Text(
                            badgeText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Título debajo de la tarjeta cortado a máximo 2 líneas con elipsis
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TomTokens.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner Publicitario Nativo según Sección 3.4
class TomNativeAdBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaText;
  final VoidCallback onTap;

  const TomNativeAdBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctaText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TomTokens.surfaceCard,
          borderRadius: TomTokens.borderLg,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1E2238),
              TomTokens.surfaceCard,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: TomTokens.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: TomTokens.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: TomTokens.primaryAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: TomTokens.borderMd,
                ),
              ),
              onPressed: onTap,
              child: Text(
                ctaText,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton Loading según Sección 3.5: claqueta con 3 puntos parpadeantes
class TomSkeletonCard extends StatefulWidget {
  const TomSkeletonCard({super.key});

  @override
  State<TomSkeletonCard> createState() => _TomSkeletonCardState();
}

class _TomSkeletonCardState extends State<TomSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 105,
      height: 155,
      decoration: BoxDecoration(
        color: TomTokens.surfaceCard,
        borderRadius: TomTokens.borderMd,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_outlined,
              color: TomTokens.primaryAccent,
              size: 28,
            ),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, _) {
                return Opacity(
                  opacity: 0.3 + (_animCtrl.value * 0.7),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Dot(),
                      SizedBox(width: 4),
                      _Dot(),
                      SizedBox(width: 4),
                      _Dot(),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        color: Colors.white70,
        shape: BoxShape.circle,
      ),
    );
  }
}
