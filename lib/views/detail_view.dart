import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import 'video_player_view.dart';

/// Pantalla de Detalles de Película / Serie (DetailView) para VJ STREAM.
/// Reproducción 100% automática, sin pantallas técnicas ni diálogos de magnets.
class DetailView extends StatefulWidget {
  final MediaItem item;

  const DetailView({super.key, required this.item});

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  final ApiService _apiService = ApiService();
  final FocusNode _playButtonFocus = FocusNode();
  bool _isPreparing = false;

  @override
  void initState() {
    super.initState();
    // Autoenfocar el botón de reproducir en Smart TV
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playButtonFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _playButtonFocus.dispose();
    super.dispose();
  }

  /// Inicia el flujo de reproducción 100% automático y transparente
  Future<void> _startPlayback() async {
    if (_isPreparing) return;

    setState(() => _isPreparing = true);

    // Diálogo minimalista de carga estilo Netflix / VJ STREAM
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'VJ STREAM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preparando transmisión en alta definición...',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.item.title,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final streamInfo = await _apiService.autoResolveStream(widget.item);

      if (!mounted) return;
      // Cerrar diálogo de carga
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _isPreparing = false);

      final streamUrl = streamInfo?['streamUrl'] as String?;
      if (streamUrl != null && streamUrl.isNotEmpty) {
        // Abrir inmediatamente el reproductor multimedia con la transmisión real
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerView(
              videoUrl: streamUrl,
              title: widget.item.title,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se encontró una transmisión activa para "${widget.item.title}". Intenta nuevamente.',
            ),
            backgroundColor: const Color(0xFFE50914),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _isPreparing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al conectar con la transmisión de "${widget.item.title}". Verifica tu red.',
          ),
          backgroundColor: const Color(0xFFE50914),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Negro absoluto OLED
      body: CustomScrollView(
        slivers: [
          // AppBar con Backdrop
          SliverAppBar(
            backgroundColor: Colors.transparent,
            expandedHeight: isTv ? size.height * 0.55 : size.height * 0.40,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.item.bestBackdropUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0D0D0D)),
                  ),
                  // Gradiente inferior a negro OLED
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.45, 1.0],
                        colors: [
                          Colors.transparent,
                          Color(0x99000000),
                          Color(0xFF000000),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Contenido de detalles
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título principal
                  Text(
                    widget.item.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isTv ? 34 : 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Metadatos (Puntuación, año, calidad comercial, audio español)
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.item.rating > 0) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              widget.item.formattedRating,
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.item.releaseYear.isNotEmpty) ...[
                        Text(
                          widget.item.releaseYear,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914).withValues(alpha: 0.2),
                          border: Border.all(color: const Color(0xFFE50914), width: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'CALIDAD 4K / 1080p',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          border: Border.all(color: Colors.greenAccent, width: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'ANTI-CAM CERTIFICADO',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          border: Border.all(color: Colors.white30, width: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'AUDIO ESPAÑOL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Botón principal de reproducción automática con D-Pad focus
                  _buildAutoPlayButton(),
                  const SizedBox(height: 24),

                  // Géneros
                  if (widget.item.genres.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: widget.item.genres.map((genre) {
                        return Chip(
                          backgroundColor: const Color(0xFF161616),
                          label: Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),

                  // Sinopsis
                  const Text(
                    'Sinopsis',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.synopsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Características de transmisión VJ STREAM
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D0D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1F1F1F)),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureRow(
                          icon: Icons.high_quality_rounded,
                          title: 'Máxima Calidad Garantizada',
                          subtitle: 'Filtro Anti-CAM estricto. Fuentes en 4K UHD, HDR y 1080p BluRay / WEB-DL.',
                        ),
                        const Divider(color: Color(0xFF1E1E1E), height: 20),
                        _buildFeatureRow(
                          icon: Icons.language_rounded,
                          title: 'Prioridad de Audio en Español',
                          subtitle: 'Preferente en Español Latino y Castellano con subtítulos sincronizados.',
                        ),
                        const Divider(color: Color(0xFF1E1E1E), height: 20),
                        _buildFeatureRow(
                          icon: Icons.speed_rounded,
                          title: 'Servidores CDN Ultrarrápidos',
                          subtitle: 'Sin esperas ni buffering mediante desbridado en la nube de alta velocidad.',
                        ),
                      ],
                    ),
                  ),

                  // Margen inferior seguro
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPlayButton() {
    return Focus(
      focusNode: _playButtonFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _startPlayback();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _startPlayback,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE50914), Color(0xFF990000)],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _playButtonFocus.hasFocus ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE50914).withValues(alpha: _playButtonFocus.hasFocus ? 0.6 : 0.25),
                blurRadius: _playButtonFocus.hasFocus ? 18 : 10,
                spreadRadius: _playButtonFocus.hasFocus ? 2 : 0,
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text(
                'Reproducir en VJ STREAM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFE50914), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
