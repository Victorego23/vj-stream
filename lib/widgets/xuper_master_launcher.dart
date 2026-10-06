import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reloj digital en vivo estilo Xuper TV / Magis TV
/// Muestra hora exacta (HH:mm:ss), fecha en español y badge de estado VIP.
class XuperLiveClock extends StatefulWidget {
  final bool compact;
  const XuperLiveClock({super.key, this.compact = false});

  @override
  State<XuperLiveClock> createState() => _XuperLiveClockState();
}

class _XuperLiveClockState extends State<XuperLiveClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTwo(int n) => n.toString().padLeft(2, '0');

  String _getSpanishDay(int weekday) {
    switch (weekday) {
      case 1:
        return 'Lun';
      case 2:
        return 'Mar';
      case 3:
        return 'Mié';
      case 4:
        return 'Jue';
      case 5:
        return 'Vie';
      case 6:
        return 'Sáb';
      case 7:
        return 'Dom';
      default:
        return '';
    }
  }

  String _getSpanishMonth(int month) {
    switch (month) {
      case 1:
        return 'Ene';
      case 2:
        return 'Feb';
      case 3:
        return 'Mar';
      case 4:
        return 'Abr';
      case 5:
        return 'May';
      case 6:
        return 'Jun';
      case 7:
        return 'Jul';
      case 8:
        return 'Ago';
      case 9:
        return 'Sep';
      case 10:
        return 'Oct';
      case 11:
        return 'Nov';
      case 12:
        return 'Dic';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = _formatTwo(_now.hour);
    final minutes = _formatTwo(_now.minute);
    final seconds = _formatTwo(_now.second);
    final dayName = _getSpanishDay(_now.weekday);
    final monthName = _getSpanishMonth(_now.month);
    final dayNum = _now.day;

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_filled_rounded, color: Color(0xFF00E676), size: 14),
            const SizedBox(width: 6),
            Text(
              '$hours:$minutes',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC11131E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Punto indicador online neón
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF00E676),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Hora digital
          Text(
            '$hours:$minutes:$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 10),

          // Separador sutil
          Container(
            width: 1,
            height: 14,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 10),

          // Fecha en español
          Text(
            '$dayName, $dayNum $monthName',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra Superior Xuper TV para Launcher de Inicio
class XuperTopHeaderBar extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onRefresh;

  const XuperTopHeaderBar({
    super.key,
    required this.onSearch,
    required this.onSettings,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF07080D).withValues(alpha: 0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Logo TOM TV estilizado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE50914), Color(0xFF990000)],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66E50914),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TOM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  'TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    fontSize: 18,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Badge VIP Premium
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.4), width: 0.8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700), size: 14),
                SizedBox(width: 4),
                Text(
                  'VIP ILIMITADO',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Reloj digital en vivo
          const XuperLiveClock(),
          const SizedBox(width: 16),

          // Botón Buscar
          _TvHeaderIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Buscar',
            onTap: onSearch,
          ),
          const SizedBox(width: 8),

          // Botón Ajustes
          _TvHeaderIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'Ajustes',
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class _TvHeaderIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TvHeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_TvHeaderIconButton> createState() => _TvHeaderIconButtonState();
}

class _TvHeaderIconButtonState extends State<_TvHeaderIconButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isFocused
                  ? const Color(0xFFE50914)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.15),
                width: _isFocused ? 1.5 : 1.0,
              ),
              boxShadow: _isFocused
                  ? const [
                      BoxShadow(
                        color: Color(0x88E50914),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: _isFocused ? Colors.white : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// Los 4 Bloques Maestros Gigantes estilo Xuper TV / Magis TV Launcher
class XuperMasterCardsRow extends StatelessWidget {
  final VoidCallback onOpenLiveTv;
  final VoidCallback onOpenMovies;
  final VoidCallback onOpenSeries;
  final VoidCallback onOpenSports;

  const XuperMasterCardsRow({
    super.key,
    required this.onOpenLiveTv,
    required this.onOpenMovies,
    required this.onOpenSeries,
    required this.onOpenSports,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = screenWidth > 700;

    if (!isTv) {
      // Diseño móvil / vertical: Grid 2x2 responsivo o carrusel
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ACCESO PRINCIPAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _XuperMasterCard(
                  title: 'TV EN VIVO',
                  subtitle: '585 Canales HD',
                  badge: 'DIRECTO',
                  icon: Icons.live_tv_rounded,
                  gradientColors: const [Color(0xFF0F2027), Color(0xFF1B3B52), Color(0xFF2C5364)],
                  glowColor: const Color(0xFF00E5FF),
                  badgeColor: const Color(0xFFE50914),
                  onTap: onOpenLiveTv,
                ),
                _XuperMasterCard(
                  title: 'PELÍCULAS',
                  subtitle: 'Estrenos 4K',
                  badge: 'CINEMA',
                  icon: Icons.movie_filter_rounded,
                  gradientColors: const [Color(0xFF330006), Color(0xFF6B0F1A), Color(0xFF990000)],
                  glowColor: const Color(0xFFE50914),
                  badgeColor: const Color(0xFFE50914),
                  onTap: onOpenMovies,
                ),
                _XuperMasterCard(
                  title: 'SERIES',
                  subtitle: 'Temporadas Completas',
                  badge: 'VOD',
                  icon: Icons.video_library_rounded,
                  gradientColors: const [Color(0xFF140D36), Color(0xFF2A166A), Color(0xFF4A148C)],
                  glowColor: const Color(0xFF7C4DFF),
                  badgeColor: const Color(0xFF7C4DFF),
                  onTap: onOpenSeries,
                ),
                _XuperMasterCard(
                  title: 'FÚTBOL & DEPORTES',
                  subtitle: 'Partidos en Directo',
                  badge: 'LIVE',
                  icon: Icons.sports_soccer_rounded,
                  gradientColors: const [Color(0xFF002211), Color(0xFF004D25), Color(0xFF007E33)],
                  glowColor: const Color(0xFF00E676),
                  badgeColor: const Color(0xFF00C853),
                  onTap: onOpenSports,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Diseño Pantalla Completa Smart TV (Fila horizontal de 4 tarjetas gigantes)
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: const [
                    BoxShadow(color: Color(0xFFE50914), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'SERVICIOS MAESTROS TOM TV',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              const Text(
                'Navega con el control remoto y pulsa OK',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 136,
            child: Row(
              children: [
                Expanded(
                  child: _XuperMasterCard(
                    title: 'TV EN VIVO',
                    subtitle: '585 Canales HD/FHD',
                    badge: 'DIRECTO',
                    icon: Icons.live_tv_rounded,
                    gradientColors: const [Color(0xFF0B1926), Color(0xFF143048), Color(0xFF1B4965)],
                    glowColor: const Color(0xFF00B4D8),
                    badgeColor: const Color(0xFFE50914),
                    onTap: onOpenLiveTv,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _XuperMasterCard(
                    title: 'PELÍCULAS',
                    subtitle: 'Estrenos 4K & Cartelera',
                    badge: 'CINEMA',
                    icon: Icons.movie_filter_rounded,
                    gradientColors: const [Color(0xFF2E0207), Color(0xFF5C0813), Color(0xFF8B0000)],
                    glowColor: const Color(0xFFE50914),
                    badgeColor: const Color(0xFFE50914),
                    onTap: onOpenMovies,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _XuperMasterCard(
                    title: 'SERIES',
                    subtitle: 'Temporadas Completas',
                    badge: 'VOD',
                    icon: Icons.video_library_rounded,
                    gradientColors: const [Color(0xFF150A2B), Color(0xFF281351), Color(0xFF3F197A)],
                    glowColor: const Color(0xFF9D4EDD),
                    badgeColor: const Color(0xFF7B2CBF),
                    onTap: onOpenSeries,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _XuperMasterCard(
                    title: 'FÚTBOL & DEPORTES',
                    subtitle: 'Partidos en Directo',
                    badge: 'LIVE',
                    icon: Icons.sports_soccer_rounded,
                    gradientColors: const [Color(0xFF031E0D), Color(0xFF063D1A), Color(0xFF0B5D28)],
                    glowColor: const Color(0xFF00F5D4),
                    badgeColor: const Color(0xFF00C853),
                    onTap: onOpenSports,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta individual maestra interactiva con soporte D-Pad TV
class _XuperMasterCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final List<Color> gradientColors;
  final Color glowColor;
  final Color badgeColor;
  final VoidCallback onTap;

  const _XuperMasterCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.gradientColors,
    required this.glowColor,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  State<_XuperMasterCard> createState() => _XuperMasterCardState();
}

class _XuperMasterCardState extends State<_XuperMasterCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedScale(
          scale: _isFocused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.gradientColors,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.14),
                width: _isFocused ? 2.2 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isFocused
                      ? widget.glowColor.withValues(alpha: 0.6)
                      : Colors.black.withValues(alpha: 0.5),
                  blurRadius: _isFocused ? 22 : 10,
                  spreadRadius: _isFocused ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Ícono gigante traslúcido decorativo en la esquina inferior derecha
                Positioned(
                  right: -10,
                  bottom: -12,
                  child: Icon(
                    widget.icon,
                    size: 80,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),

                // Contenido principal
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Fila superior: Ícono y Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.badgeColor,
                            borderRadius: BorderRadius.circular(5),
                            boxShadow: [
                              BoxShadow(
                                color: widget.badgeColor.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Text(
                            widget.badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Fila inferior: Título y Subtítulo
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            shadows: _isFocused
                                ? [
                                    Shadow(
                                      color: widget.glowColor,
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
