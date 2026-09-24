import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'home_view.dart';

/// Pantalla de Activación por Código (Smart TV y Móvil) para VJ STREAM.
/// Muestra un código de 6 dígitos (ej: VJ-8421) y escucha en tiempo real
/// hasta que el Administrador lo aprueba desde su Panel Web.
class ActivationView extends StatefulWidget {
  final bool isExpired;

  const ActivationView({super.key, this.isExpired = false});

  @override
  State<ActivationView> createState() => _ActivationViewState();
}

class _ActivationViewState extends State<ActivationView> {
  bool _isLoading = true;
  String? _code;
  String? _errorMessage;
  String? _whatsappNumber;
  Timer? _pollingTimer;
  bool _isSuccess = false;
  String? _clientName;

  @override
  void initState() {
    super.initState();
    _startDeviceRegistration();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startDeviceRegistration() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final info = await AuthService.registerOrCheckDevice();

    if (!mounted) return;

    if (info.isActive) {
      // Dispositivo ya activado previamente, entrar directo
      _navigateToHome();
      return;
    }

    setState(() {
      _isLoading = false;
      _code = info.code ?? 'VJ-....';
      _whatsappNumber = info.whatsappNumber;
      if (info.isExpired) {
        _errorMessage = 'Tu membresía ha vencido. Contacta a tu proveedor para renovar.';
      } else if (info.isSuspended) {
        _errorMessage = 'Tu cuenta está suspendida temporalmente. Contacta a tu proveedor.';
      } else if (info.status == 'error') {
        _errorMessage = 'No se pudo conectar con el servidor. Verifica tu conexión a internet.';
      }
    });

    // Iniciar sondeo automático cada 3 segundos si hay código pendiente
    if (info.isPending && _code != null) {
      _startPolling(_code!);
    }
  }

  void _startPolling(String code) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final info = await AuthService.pollActivationStatus(code);
      if (info.isActive && mounted) {
        timer.cancel();
        setState(() {
          _isSuccess = true;
          _clientName = info.clientName ?? 'Cliente';
        });

        // Esperar 1.5 segundos para mostrar la confirmación visual y navegar
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          _navigateToHome();
        }
      }
    });
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Container(
              padding: EdgeInsets.all(isTv ? 40 : 28),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isSuccess ? const Color(0xFF22C55E) : const Color(0xFF262626),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isSuccess
                        ? const Color(0xFF22C55E).withValues(alpha: 0.25)
                        : const Color(0xFFE50914).withValues(alpha: 0.15),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo VJ STREAM
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFF990000)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66E50914),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Text(
                      'VJ STREAM',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_isSuccess) ...[
                    // Pantalla de Éxito al recibir activación del Administrador
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 72),
                    const SizedBox(height: 16),
                    Text(
                      '¡Pantalla Activada con Éxito!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTv ? 24 : 20,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bienvenido ${_clientName ?? ""}. Tu suscripción está lista.\nIniciando VJ STREAM...',
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(color: Color(0xFF22C55E)),
                  ] else if (_isLoading) ...[
                    // Cargando
                    const SizedBox(height: 30),
                    const CircularProgressIndicator(color: Color(0xFFE50914)),
                    const SizedBox(height: 24),
                    const Text(
                      'Conectando con el servidor VJ STREAM...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 30),
                  ] else ...[
                    // Título
                    Text(
                      _errorMessage != null ? 'Acceso Requiere Activación' : 'Activa tu Pantalla',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTv ? 24 : 20,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ??
                          'Envía este código a tu proveedor de VJ STREAM por WhatsApp para activar tu membresía:',
                      style: TextStyle(
                        color: _errorMessage != null ? const Color(0xFFEF4444) : Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Cuadro destacado con el Código (ej: VJ-8421)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE50914),
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33E50914),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'CÓDIGO DE ACTIVACIÓN',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _code ?? 'VJ-....',
                            style: TextStyle(
                              color: const Color(0xFFE50914),
                              fontSize: isTv ? 42 : 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Animación de espera / polling en tiempo real
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE50914),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Esperando que el administrador active tu pantalla...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Botones de acción
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF333333)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                            label: const Text('Copiar Código', style: TextStyle(color: Colors.white)),
                            onPressed: () {
                              if (_code != null) {
                                Clipboard.setData(ClipboardData(text: _code!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Código copiado al portapapeles.'),
                                    backgroundColor: Color(0xFF22C55E),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                            label: const Text('Comprobar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: _startDeviceRegistration,
                          ),
                        ),
                      ],
                    ),

                    if (_whatsappNumber != null && _whatsappNumber!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Contacto de Soporte y Renovación: $_whatsappNumber',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
