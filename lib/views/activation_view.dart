import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../theme/tom_tokens.dart';
import 'home_view.dart';

/// Pantalla de Activación y Licenciamiento TV-First para TOM TV.
/// Totalmente optimizada para navegación D-Pad en Samsung Tizen, LG webOS y Android TV.
class ActivationView extends StatefulWidget {
  final bool isExpired;
  final VoidCallback? onActivated;

  const ActivationView({super.key, this.isExpired = false, this.onActivated});

  @override
  State<ActivationView> createState() => _ActivationViewState();
}

class _ActivationViewState extends State<ActivationView> {
  bool _isLoading = true;
  String? _deviceId;
  String? _tvCode;
  String? _errorMessage;
  String? _whatsappNumber;
  Timer? _pollingTimer;
  bool _isSuccess = false;
  String? _clientName;
  String? _expiresAtFormatted;

  // Controlador de entrada de código manual
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _verifyButtonFocusNode = FocusNode();
  final FocusNode _firstKeypadFocusNode = FocusNode();

  bool _isVerifyingManual = false;

  @override
  void initState() {
    super.initState();
    _initDeviceAndLicense();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _codeController.dispose();
    _inputFocusNode.dispose();
    _verifyButtonFocusNode.dispose();
    _firstKeypadFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initDeviceAndLicense() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final devId = await AuthService.getDeviceId();
    if (!mounted) return;
    setState(() {
      _deviceId = devId;
    });

    // 1. Probar validación remota por token/sesión guardada
    final licResult = await AuthService.verifyLicenseWithServer();
    if (!mounted) return;

    if (licResult.isValid) {
      _handleActivationSuccess(licResult.clientName, licResult.expiresAt);
      return;
    }

    // 2. Si no hay sesión válida, registrar la pantalla para generar el código TV en espera
    final info = await AuthService.registerOrCheckDevice();
    if (!mounted) return;

    if (info.isActive) {
      _handleActivationSuccess(info.clientName, info.expiresAt);
      return;
    }

    setState(() {
      _isLoading = false;
      _tvCode = info.code ?? 'TOM-....';
      _whatsappNumber = info.whatsappNumber;
      if (info.isExpired || widget.isExpired) {
        _errorMessage = 'Tu membresía ha vencido. Contacta a tu proveedor para renovar.';
      } else if (info.isSuspended) {
        _errorMessage = 'Tu suscripción está suspendida temporalmente por el administrador.';
      } else if (info.status == 'error') {
        _errorMessage = 'No se pudo conectar con el servidor. Verifica tu conexión a internet.';
      }
    });

    // Iniciar sondeo automático cada 3.5 segundos si hay código TV asignado
    if (info.isPending && _tvCode != null) {
      _startPolling(_tvCode!);
    }
  }

  void _startPolling(String code) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 3500), (timer) async {
      final info = await AuthService.pollActivationStatus(code);
      if (info.isActive && mounted) {
        timer.cancel();
        _handleActivationSuccess(info.clientName, info.expiresAt);
      }
    });
  }

  Future<void> _handleActivationSuccess(String? name, String? expiresAt) async {
    _pollingTimer?.cancel();
    String formattedExp = 'Acceso Activo';
    if (expiresAt != null && expiresAt.isNotEmpty) {
      final dt = DateTime.tryParse(expiresAt);
      if (dt != null) {
        formattedExp = 'Vigente hasta el ${dt.day}/${dt.month}/${dt.year}';
      }
    }

    setState(() {
      _isSuccess = true;
      _clientName = name ?? 'Cliente';
      _expiresAtFormatted = formattedExp;
      _isLoading = false;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      if (widget.onActivated != null) {
        widget.onActivated!();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeView()),
        );
      }
    }
  }

  Future<void> _verifyManualCode() async {
    final input = _codeController.text.trim().toUpperCase();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'Por favor ingresa un código de activación.';
      });
      return;
    }

    setState(() {
      _isVerifyingManual = true;
      _errorMessage = null;
    });

    final result = await AuthService.verifyLicenseWithServer(code: input);

    if (!mounted) return;
    setState(() {
      _isVerifyingManual = false;
    });

    if (result.isValid) {
      _handleActivationSuccess(result.clientName, result.expiresAt);
    } else {
      setState(() {
        _errorMessage = result.message;
      });
    }
  }

  void _appendChar(String char) {
    setState(() {
      _codeController.text += char;
      _codeController.selection = TextSelection.fromPosition(
        TextPosition(offset: _codeController.text.length),
      );
    });
  }

  void _backspace() {
    if (_codeController.text.isNotEmpty) {
      setState(() {
        _codeController.text = _codeController.text.substring(0, _codeController.text.length - 1);
        _codeController.selection = TextSelection.fromPosition(
          TextPosition(offset: _codeController.text.length),
        );
      });
    }
  }

  void _clearInput() {
    setState(() {
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTvWide = screenSize.width >= 900;

    return Scaffold(
      backgroundColor: TomTokens.backgroundMain,
      body: Center(
        child: _isLoading
            ? _buildLoadingState()
            : _isSuccess
                ? _buildSuccessState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isTvWide ? 1040 : 580),
                        child: Container(
                          padding: EdgeInsets.all(isTvWide ? 36 : 24),
                          decoration: BoxDecoration(
                            color: TomTokens.surfaceCard,
                            borderRadius: TomTokens.borderLg,
                            border: Border.all(color: const Color(0xFF262626), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: TomTokens.primaryAccent.withValues(alpha: 0.15),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 24),
                              if (_errorMessage != null) ...[
                                _buildErrorBanner(_errorMessage!),
                                const SizedBox(height: 20),
                              ],
                              if (isTvWide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 5, child: _buildDeviceCodePanel()),
                                    const SizedBox(width: 32),
                                    Container(width: 1, height: 420, color: const Color(0xFF2A2A32)),
                                    const SizedBox(width: 32),
                                    Expanded(flex: 6, child: _buildManualEntryPanel()),
                                  ],
                                )
                              else ...[
                                _buildDeviceCodePanel(),
                                const SizedBox(height: 28),
                                const Divider(color: Color(0xFF2A2A32)),
                                const SizedBox(height: 20),
                                _buildManualEntryPanel(),
                              ],
                              const SizedBox(height: 20),
                              _buildFooterSupport(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: TomTokens.primaryAccent, strokeWidth: 3),
        const SizedBox(height: 20),
        const Text(
          'Validando licencia de pantalla...',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'ID: ${_deviceId ?? "..."}',
          style: const TextStyle(color: TomTokens.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF22C55E), width: 2),
          ),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 72),
        ),
        const SizedBox(height: 24),
        const Text(
          '¡Pantalla Activada con Éxito!',
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Bienvenido ${_clientName ?? "Cliente"}\n${_expiresAtFormatted ?? ""}',
          style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const CircularProgressIndicator(color: Color(0xFF22C55E), strokeWidth: 3),
        const SizedBox(height: 12),
        const Text('Iniciando TOM TV...', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [TomTokens.primaryAccent, Color(0xFF990000)]),
                borderRadius: TomTokens.borderSm,
                boxShadow: const [BoxShadow(color: Color(0x66E50914), blurRadius: 10)],
              ),
              child: const Text(
                'TOM TV',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 2),
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'Sistema de Activación',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (_deviceId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tv_rounded, color: TomTokens.primaryAccent, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Device ID: ${_deviceId!.length > 18 ? "${_deviceId!.substring(0, 18)}..." : _deviceId!}',
                  style: const TextStyle(color: TomTokens.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0D0E),
        borderRadius: TomTokens.borderMd,
        border: Border.all(color: const Color(0xFFE50914), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE50914), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCodePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'MÉTODO 1: ACTIVACIÓN POR CÓDIGO TV',
          style: TextStyle(color: TomTokens.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: TomTokens.borderMd,
            border: Border.all(color: TomTokens.primaryAccent, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x33E50914), blurRadius: 20, spreadRadius: 1),
            ],
          ),
          child: Column(
            children: [
              const Text('CÓDIGO DE TU PANTALLA', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              SelectableText(
                _tvCode ?? 'TOM-....',
                style: const TextStyle(color: TomTokens.primaryAccent, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 3),
              ),
              if (_tvCode != null && _whatsappNumber != null && _whatsappNumber!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: Image.network(
                    'https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=${Uri.encodeComponent("https://wa.me/${_whatsappNumber!.replaceAll(RegExp(r'[^0-9]'), '')}?text=Hola,%20deseo%20activar%20mi%20pantalla%20TOM%20TV%20C%C3%B3digo:%20$_tvCode")}',
                    width: 110,
                    height: 110,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Escanea con tu celular para enviar a WhatsApp', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF14141A), borderRadius: BorderRadius.circular(8)),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: TomTokens.primaryAccent)),
              SizedBox(width: 10),
              Text('Esperando aprobación del administrador...', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualEntryPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'MÉTODO 2: INGRESAR CÓDIGO O LICENCIA',
          style: TextStyle(color: TomTokens.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        // Campo de texto con FocusNode para control remoto
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF09090D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _inputFocusNode.hasFocus ? TomTokens.primaryAccent : const Color(0xFF33333E), width: 2),
          ),
          child: TextField(
            controller: _codeController,
            focusNode: _inputFocusNode,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: 'EJ: VJ-9842',
              hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 1),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
              suffixIcon: _codeController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                      onPressed: _clearInput,
                    )
                  : null,
            ),
            onSubmitted: (_) => _verifyManualCode(),
          ),
        ),
        const SizedBox(height: 14),
        // Botón de activación con soporte D-Pad
        ElevatedButton(
          focusNode: _verifyButtonFocusNode,
          style: ElevatedButton.styleFrom(
            backgroundColor: TomTokens.primaryAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isVerifyingManual ? null : _verifyManualCode,
          child: _isVerifyingManual
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.vpn_key_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Vincular y Activar Pantalla', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        // Teclado virtual adaptado a D-Pad para Smart TV
        _buildVirtualKeypad(),
      ],
    );
  }

  Widget _buildVirtualKeypad() {
    const keys = [
      ['1', '2', '3', '4', '5'],
      ['6', '7', '8', '9', '0'],
      ['V', 'J', '-', 'A', 'B'],
      ['C', 'D', 'E', 'F', 'G'],
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF22222E)),
      ),
      child: Column(
        children: [
          for (var row in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (var k in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _KeypadButton(
                          label: k,
                          onPressed: () => _appendChar(k),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _KeypadButton(
                    label: 'BORRAR',
                    icon: Icons.backspace_outlined,
                    onPressed: _backspace,
                    isAction: true,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _KeypadButton(
                    label: 'LIMPIAR',
                    onPressed: _clearInput,
                    isAction: true,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _KeypadButton(
                    label: 'VJ-',
                    onPressed: () => _appendChar('VJ-'),
                    isAction: true,
                    isAccent: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterSupport() {
    return Column(
      children: [
        if (_whatsappNumber != null && _whatsappNumber!.isNotEmpty)
          Text(
            'Soporte Oficial & Activación Inmediata por WhatsApp: $_whatsappNumber',
            style: const TextStyle(color: TomTokens.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 6),
        const Text(
          'Compatible con Samsung Tizen, LG webOS, Android TV, Firestick y Web PWA.',
          style: TextStyle(color: Colors.white24, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Botón de teclado en pantalla con foco visual prominente para control remoto D-pad
class _KeypadButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool isAction;
  final bool isAccent;

  const _KeypadButton({
    required this.label,
    this.icon,
    required this.onPressed,
    this.isAction = false,
    this.isAccent = false,
  });

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (val) => setState(() => _isFocused = val),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _isFocused
                  ? (widget.isAccent ? TomTokens.primaryAccent : const Color(0xFF2E2E3A))
                  : (widget.isAccent
                      ? const Color(0xFF4A0A10)
                      : (widget.isAction ? const Color(0xFF1E1E26) : const Color(0xFF16161E))),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused ? TomTokens.primaryAccent : Colors.transparent,
                width: 2,
              ),
              boxShadow: _isFocused
                  ? [BoxShadow(color: TomTokens.primaryAccent.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
            child: Center(
              child: widget.icon != null
                  ? Icon(widget.icon, size: 16, color: Colors.white)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        color: _isFocused ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: widget.isAction ? 11 : 14,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
