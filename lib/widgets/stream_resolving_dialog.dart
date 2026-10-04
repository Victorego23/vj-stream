import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Modal cinematográfico de carga ultra-rápida y resolución de transmisiones de TOM TV.
/// Informa visualmente al usuario del proceso en tiempo real (Satélite -> 4K/1080p -> Audio Latino -> Desbridado).
class StreamResolvingDialog extends StatefulWidget {
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String? mediaType;
  final int? season;
  final int? episode;
  final VoidCallback? onCancel;

  const StreamResolvingDialog({
    super.key,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.mediaType,
    this.season,
    this.episode,
    this.onCancel,
  });

  @override
  State<StreamResolvingDialog> createState() => _StreamResolvingDialogState();
}

class _StreamResolvingDialogState extends State<StreamResolvingDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  int _currentStepIndex = 0;
  Timer? _stepTimer;

  static const List<Map<String, dynamic>> _resolutionSteps = [
    {
      'icon': Icons.satellite_alt_rounded,
      'title': 'Conectando con la red TOM TV',
      'subtitle': 'Estableciendo enlace seguro de baja latencia',
    },
    {
      'icon': Icons.high_quality_rounded,
      'title': 'Localizando fuentes 4K / 1080p',
      'subtitle': 'Filtrando grabaciones de cine y descartando CAM',
    },
    {
      'icon': Icons.language_rounded,
      'title': 'Priorizando audio en Español Latino',
      'subtitle': 'Verificando pistas de sonido y doblaje oficial',
    },
    {
      'icon': Icons.bolt_rounded,
      'title': 'Desbridando a máxima velocidad',
      'subtitle': 'Iniciando transmisión instantánea sin cortes',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Avanzar dinámicamente los pasos informativos cada 700ms
    _stepTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (mounted) {
        setState(() {
          if (_currentStepIndex < _resolutionSteps.length - 1) {
            _currentStepIndex++;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 700;
    final dialogWidth = isTv ? 440.0 : 340.0;

    String subtitleLabel = widget.title;
    if (widget.season != null && widget.episode != null) {
      subtitleLabel = 'Temporada ${widget.season} • Episodio ${widget.episode}';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onCancel != null) {
          widget.onCancel!();
        }
      },
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: dialogWidth,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
            decoration: BoxDecoration(
              color: const Color(0xFF10121A).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFE50914).withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.25),
                  blurRadius: 35,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.85),
                  blurRadius: 25,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabecera con Logo TOM TV y Efecto Pulso
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE50914).withValues(alpha: 0.45),
                                  blurRadius: 25,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFE50914), Color(0xFFB20710)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Título de la Aplicación y Película
                const Text(
                  'TOM TV PREMIER',
                  style: TextStyle(
                    color: Color(0xFFE50914),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 3.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.season != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitleLabel,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Lista de Pasos Dinámicos de Resolución
                Column(
                  children: List.generate(_resolutionSteps.length, (index) {
                    final step = _resolutionSteps[index];
                    final isDone = index < _currentStepIndex;
                    final isCurrent = index == _currentStepIndex;

                    Color iconBgColor = Colors.white.withValues(alpha: 0.05);
                    Color iconColor = Colors.white30;
                    Color titleColor = Colors.white38;

                    if (isDone) {
                      iconBgColor = const Color(0xFF22C55E).withValues(alpha: 0.18);
                      iconColor = const Color(0xFF22C55E);
                      titleColor = Colors.white70;
                    } else if (isCurrent) {
                      iconBgColor = const Color(0xFFE50914).withValues(alpha: 0.22);
                      iconColor = const Color(0xFFE50914);
                      titleColor = Colors.white;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5.0),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: iconBgColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFFE50914)
                                    : (isDone ? const Color(0xFF22C55E) : Colors.transparent),
                                width: 1.2,
                              ),
                            ),
                            child: isDone
                                ? const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 18)
                                : Icon(step['icon'] as IconData, color: iconColor, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step['title'] as String,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontSize: 13,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                if (isCurrent)
                                  Text(
                                    step['subtitle'] as String,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFE50914),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 22),

                // Barra de Progreso Continua con Gradiente
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 3.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: const Color(0xFFE50914),
                  ),
                ),
                const SizedBox(height: 14),

                // Botón discreto de cancelar
                TextButton(
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    if (widget.onCancel != null) widget.onCancel!();
                  },
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
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
