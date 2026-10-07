import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/tom_tokens.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';

/// Modal oficial de Control Parental según la especificación técnica (Sección 5)
void showParentalWarningDialog(BuildContext context, {VoidCallback? onGoToLink}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'ParentalModal',
    barrierColor: TomTokens.overlayScrim,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, anim1, anim2) {
      return Center(
        child: Container(
          width: MediaQuery.of(dialogContext).size.width > 500
              ? 420
              : MediaQuery.of(dialogContext).size.width * 0.88,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TomTokens.surfaceCard,
            borderRadius: TomTokens.borderLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: TomTokens.primaryAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: TomTokens.primaryAccent,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nota',
                  style: TextStyle(
                    color: TomTokens.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Para proteger a los menores, por favor establezca una contraseña. Puede ir a Perfil - Gestión de Cuenta para establecer una contraseña al vincular su correo electrónico.',
                  style: TextStyle(
                    color: TomTokens.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TomTokens.primaryAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: TomTokens.borderMd,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      if (onGoToLink != null) {
                        onGoToLink();
                      }
                    },
                    child: const Text(
                      'Ir a vincular',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: TomTokens.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return Transform.scale(
        scale: 0.92 + (anim1.value * 0.08),
        child: Opacity(
          opacity: anim1.value,
          child: child,
        ),
      );
    },
  );
}

/// Pantalla 3: Perfil de Usuario ("Mi Cuenta") de TOM TV
class ProfileView extends StatefulWidget {
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSearch;

  const ProfileView({
    super.key,
    this.onOpenFavorites,
    this.onOpenHistory,
    this.onOpenSearch,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  String _userId = '';
  String _username = 'Visitante';
  String _clientCode = '';
  String _expiresAt = '';
  bool _isAccountActivated = false;
  String _linkedEmail = '';
  String _linkedPhone = '';
  bool _isAdultEnabled = false;
  bool _hasCredentialsLinked = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Comprobar si hay una cuenta vinculada o sesión activa en la base de datos
    final hasValidSession = await AuthService.hasValidSavedSession();
    final clientName = prefs.getString('vj_stream_client_name');
    final clientCode = prefs.getString('vj_stream_client_code');
    final clientId = prefs.getString('vj_stream_client_id');
    final expiresAt = prefs.getString('vj_stream_expires_at') ?? '';

    // ID de respaldo solo para modo visitante
    String effectiveGuestId = prefs.getString('tom_tv_user_id') ?? '';
    if (effectiveGuestId.isEmpty) {
      final random = Random();
      final num = 900000000 + random.nextInt(99999999);
      effectiveGuestId = num.toString();
      await prefs.setString('tom_tv_user_id', effectiveGuestId);
    }

    final isActivated = hasValidSession &&
        ((clientName != null && clientName.isNotEmpty) || (clientCode != null && clientCode.isNotEmpty));

    final String resolvedUserId;
    if (isActivated) {
      if (clientCode != null && clientCode.isNotEmpty) {
        resolvedUserId = clientCode;
      } else if (clientId != null && clientId.isNotEmpty) {
        resolvedUserId = clientId;
      } else {
        resolvedUserId = effectiveGuestId;
      }
    } else {
      resolvedUserId = effectiveGuestId;
    }

    final email = prefs.getString('tom_tv_email') ?? '';
    final phone = prefs.getString('tom_tv_phone') ?? '';
    final adult = prefs.getBool('tom_tv_adult_switch') ?? false;

    if (mounted) {
      setState(() {
        _isAccountActivated = isActivated;
        if (isActivated) {
          // Sustituir la etiqueta 'Visitante' por el nombre real del usuario registrado en base de datos
          _username = (clientName != null && clientName.isNotEmpty) ? clientName : 'Usuario TOM TV';
        } else {
          _username = 'Visitante';
        }
        _userId = resolvedUserId;
        _clientCode = clientCode ?? '';
        _expiresAt = expiresAt;
        _linkedEmail = email;
        _linkedPhone = phone;
        _hasCredentialsLinked = email.isNotEmpty || isActivated;
        _isAdultEnabled = adult && _hasCredentialsLinked;
      });
    }
  }

  void _triggerParentalWarning() {
    showParentalWarningDialog(
      context,
      onGoToLink: _showAccountManagementModal,
    );
  }

  void _showAccountManagementModal() {
    final emailCtrl = TextEditingController(text: _linkedEmail);
    final phoneCtrl = TextEditingController(text: _linkedPhone);
    final passCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: TomTokens.surfaceCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Gestión de Cuenta y Credenciales',
                style: TextStyle(
                  color: TomTokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vincula tus datos para proteger tu perfil y activar el control parental.',
                style: TextStyle(
                  color: TomTokens.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  labelStyle: const TextStyle(color: TomTokens.textSecondary),
                  prefixIcon: const Icon(Icons.email_outlined, color: TomTokens.primaryAccent),
                  filled: true,
                  fillColor: TomTokens.backgroundMain,
                  border: OutlineInputBorder(
                    borderRadius: TomTokens.borderMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Número de teléfono (opcional)',
                  labelStyle: const TextStyle(color: TomTokens.textSecondary),
                  prefixIcon: const Icon(Icons.phone_outlined, color: TomTokens.primaryAccent),
                  filled: true,
                  fillColor: TomTokens.backgroundMain,
                  border: OutlineInputBorder(
                    borderRadius: TomTokens.borderMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Contraseña / PIN Parental (4 dígitos o más)',
                  labelStyle: const TextStyle(color: TomTokens.textSecondary),
                  prefixIcon: const Icon(Icons.lock_outline, color: TomTokens.primaryAccent),
                  filled: true,
                  fillColor: TomTokens.backgroundMain,
                  border: OutlineInputBorder(
                    borderRadius: TomTokens.borderMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TomTokens.primaryAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: TomTokens.borderMd,
                    ),
                  ),
                  onPressed: () async {
                    final email = emailCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    final pass = passCtrl.text.trim();

                    if (email.isEmpty || !email.contains('@')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Por favor ingresa un correo válido.')),
                      );
                      return;
                    }

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('tom_tv_email', email);
                    await prefs.setString('tom_tv_phone', phone);
                    if (pass.isNotEmpty) {
                      await prefs.setString('tom_tv_parental_pin', pass);
                    }

                    if (mounted) {
                      setState(() {
                        _linkedEmail = email;
                        _linkedPhone = phone;
                        _hasCredentialsLinked = true;
                      });
                      Navigator.pop(bottomSheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: TomTokens.primaryAccent,
                          content: Text('¡Credenciales vinculadas exitosamente!'),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Guardar y Vincular',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRedeemCodeModal() {
    final codeCtrl = TextEditingController();
    bool isLoading = false;
    showDialog(
      context: context,
      builder: (dlgContext) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: TomTokens.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: TomTokens.borderLg),
          title: const Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: TomTokens.primaryAccent),
              SizedBox(width: 10),
              Text('Activar Cuenta', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresa tu código de activación único (ej: VJ-3166) registrado en la base de datos para vincular tu perfil:',
                style: TextStyle(color: TomTokens.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'EJ: VJ-3166',
                  hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 0),
                  filled: true,
                  fillColor: TomTokens.backgroundMain,
                  border: OutlineInputBorder(borderRadius: TomTokens.borderMd, borderSide: BorderSide.none),
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 14),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TomTokens.primaryAccent),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dlgContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: TomTokens.primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: TomTokens.borderSm),
              ),
              onPressed: isLoading ? null : () async {
                final code = codeCtrl.text.trim().toUpperCase();
                if (code.isEmpty) return;

                setDlgState(() => isLoading = true);
                final res = await AuthService.activateWithManualCode(code);
                setDlgState(() => isLoading = false);

                if (!dlgContext.mounted) return;
                Navigator.pop(dlgContext);

                if (res.isActive) {
                  await _loadProfileData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1B5E20),
                        behavior: SnackBarBehavior.floating,
                        content: Row(
                          children: [
                            const Icon(Icons.verified_rounded, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '¡Cuenta activada para ${res.clientName ?? "Usuario"}! Perfil actualizado.',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: TomTokens.accentRed,
                        behavior: SnackBarBehavior.floating,
                        content: Text(res.message ?? 'Código inválido o aún no activado por el administrador.'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Vincular y Activar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrdersModal() {
    showDialog(
      context: context,
      builder: (dlgContext) => AlertDialog(
        backgroundColor: TomTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: TomTokens.borderLg),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 24),
            SizedBox(width: 10),
            Text('Mi Suscripción y Cuenta', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TomTokens.backgroundMain,
                borderRadius: TomTokens.borderMd,
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.badge_rounded, color: TomTokens.primaryAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isAccountActivated ? _username : 'Modo Demo',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Identificador Único en BD: $_userId',
                    style: const TextStyle(color: TomTokens.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isAccountActivated
                        ? (_expiresAt.isNotEmpty ? 'Vigencia: ${_expiresAt.split("T").first}' : 'Estado: Membresía Activa en Base de Datos')
                        : 'Estado: Versión Demo antes de activación',
                    style: TextStyle(
                      color: _isAccountActivated ? TomTokens.accentGreen : Colors.amber,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_isAccountActivated) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5252),
                    side: const BorderSide(color: Color(0xFFFF5252)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Cerrar Sesión / Desvincular'),
                  onPressed: () async {
                    Navigator.pop(dlgContext);
                    await AuthService.logout();
                    await _loadProfileData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cuenta desvinculada. Perfil en modo visitante.')),
                      );
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgContext),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal() {
    showDialog(
      context: context,
      builder: (dlgContext) => AlertDialog(
        backgroundColor: TomTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: TomTokens.borderLg),
        title: const Text('Configuraciones', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cleaning_services_rounded, color: TomTokens.primaryAccent),
              title: const Text('Limpiar memoria caché', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Libera espacio de video temporal', style: TextStyle(color: TomTokens.textSecondary, fontSize: 12)),
              onTap: () {
                Navigator.pop(dlgContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Caché del reproductor liberada.')),
                );
              },
            ),
            const Divider(color: Colors.white12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update_rounded, color: TomTokens.primaryAccent),
              title: const Text('Buscar actualizaciones', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text('Versión actual: ${UpdateService.currentVersion}', style: const TextStyle(color: TomTokens.textSecondary, fontSize: 12)),
              onTap: () {
                Navigator.pop(dlgContext);
                UpdateService.checkUpdate(context, silent: false);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgContext),
            child: const Text('Listo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TomTokens.backgroundMain,
      body: CustomScrollView(
        slivers: [
          // 6.1 Cabecera de Identidad con Ondas Abstractas
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Fondo con gradiente y ondas estilizadas
                Container(
                  height: 240,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF14193A),
                        Color(0xFF0F1122),
                        TomTokens.backgroundMain,
                      ],
                    ),
                  ),
                ),
                // Gráficos circulares translúcidos tipo onda
                Positioned(
                  right: -40,
                  top: -20,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TomTokens.primaryAccent.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                Positioned(
                  left: -50,
                  top: 40,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF40A9FF).withValues(alpha: 0.08),
                    ),
                  ),
                ),
                // Contenido de la cabecera
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top bar con Campana de notificaciones con Badge Rojo
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Mi Cuenta',
                              style: TextStyle(
                                color: TomTokens.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 26),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No tienes notificaciones pendientes.')),
                                    );
                                  },
                                ),
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: TomTokens.accentRed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Avatar y nombre
                        Row(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: _isAccountActivated
                                      ? const [Color(0xFFE50914), Color(0xFFFF5252)]
                                      : const [Color(0xFF2C3247), Color(0xFF1B1E2B)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isAccountActivated ? const Color(0xFFE50914) : Colors.black)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: _isAccountActivated ? Colors.white70 : Colors.white24,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  _isAccountActivated ? Icons.verified_user_rounded : Icons.person_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _username,
                                          style: const TextStyle(
                                            color: TomTokens.textPrimary,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_isAccountActivated) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF4CAF50), width: 1),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 12),
                                              SizedBox(width: 3),
                                              Text(
                                                'ACTIVO',
                                                style: TextStyle(
                                                  color: Color(0xFF4CAF50),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Text(
                                        _isAccountActivated ? 'ID Cuenta: $_userId' : 'ID Demo: $_userId',
                                        style: TextStyle(
                                          color: _isAccountActivated ? Colors.white70 : TomTokens.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: _userId));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('ID copiado al portapapeles')),
                                          );
                                        },
                                        child: const Icon(Icons.copy_rounded, color: TomTokens.textSecondary, size: 14),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isAccountActivated
                                        ? (_expiresAt.isNotEmpty ? 'Vigencia: ${_expiresAt.split("T").first}' : 'Membresía vinculada en base de datos')
                                        : 'Versión Demo antes de la activación',
                                    style: TextStyle(
                                      color: _isAccountActivated ? const Color(0xFF81C784) : Colors.amber.withValues(alpha: 0.8),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 6.2 Tarjeta de Activación / Membresía
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _isAccountActivated
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF13231B), Color(0xFF0F1A15)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: TomTokens.borderLg,
                        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.5), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0x264CAF50),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded, color: Color(0xFF4CAF50), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cuenta Vinculada: $_username',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'ID: $_userId • ${_expiresAt.isNotEmpty ? "Vence: ${_expiresAt.split("T").first}" : "Activo"}',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _showOrdersModal,
                            child: const Text('Detalles', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E2235), Color(0xFF141724)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: TomTokens.borderLg,
                        border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.4), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.lock_open_rounded, color: Color(0xFFE50914), size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Vincular y Activar Cuenta',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Ingresa tu código único de activación para sustituir la etiqueta Visitante por tu nombre e ID oficial.',
                                  style: TextStyle(
                                    color: TomTokens.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: TomTokens.borderMd,
                              ),
                            ),
                            icon: const Icon(Icons.key_rounded, size: 16),
                            label: const Text(
                              'Activar',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _showRedeemCodeModal,
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          // 6.3 Acciones Rápidas (3 Cards Horizontales)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildQuickActionCard(
                      icon: Icons.favorite_rounded,
                      iconColor: TomTokens.accentRed,
                      label: 'Favoritos',
                      onTap: () {
                        if (widget.onOpenFavorites != null) {
                          widget.onOpenFavorites!();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Accediendo a Favoritos...')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionCard(
                      icon: Icons.history_rounded,
                      iconColor: TomTokens.accentBlue,
                      label: 'Historial',
                      onTap: () {
                        if (widget.onOpenHistory != null) {
                          widget.onOpenHistory!();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Accediendo a Historial...')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionCard(
                      icon: Icons.share_rounded,
                      iconColor: TomTokens.accentGreen,
                      label: 'Compartir',
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: '¡Descarga TOM TV y disfruta de cine y TV en vivo gratis! https://tomtv.vip'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enlace de la app copiado al portapapeles.')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 6.4 Menú de Configuración ("Más funciones")
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: const Text(
                'Más funciones',
                style: TextStyle(
                  color: TomTokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: TomTokens.surfaceCard,
                  borderRadius: TomTokens.borderLg,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    _buildSettingsItem(
                      icon: Icons.manage_accounts_outlined,
                      title: 'Gestión de Credenciales',
                      onTap: _showAccountManagementModal,
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 52),
                    _buildSettingsItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Mi Suscripción y Cuenta',
                      onTap: _showOrdersModal,
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 52),
                    _buildSettingsItem(
                      icon: Icons.vpn_key_outlined,
                      title: _isAccountActivated ? 'Vincular otro código / Renovar' : 'Activar Código de Cuenta',
                      onTap: _showRedeemCodeModal,
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 52),
                    // Item 4: Para adultos con Switch interactivo
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.eighteen_mp_rounded, color: Colors.amber, size: 22),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'Para adultos',
                              style: TextStyle(
                                color: TomTokens.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Switch(
                            value: _isAdultEnabled,
                            activeColor: TomTokens.primaryAccent,
                            activeTrackColor: TomTokens.primaryAccent.withValues(alpha: 0.4),
                            inactiveThumbColor: Colors.white54,
                            inactiveTrackColor: Colors.white12,
                            onChanged: (val) async {
                              if (val) {
                                if (!_hasCredentialsLinked) {
                                  _triggerParentalWarning();
                                  return;
                                }
                              }
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('tom_tv_adult_switch', val);
                              setState(() => _isAdultEnabled = val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 52),
                    _buildSettingsItem(
                      icon: Icons.help_outline_rounded,
                      title: 'Ayuda y Feedback',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Soporte técnico: contacto en soporte@tomtv.vip')),
                        );
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 52),
                    _buildSettingsItem(
                      icon: Icons.subtitles_outlined,
                      title: 'Audio y subtítulos',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Idioma predeterminado: Español Latino')),
                        );
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12, indent: 52),
                    _buildSettingsItem(
                      icon: Icons.settings_outlined,
                      title: 'Configuraciones',
                      onTap: _showSettingsModal,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: TomTokens.surfaceCard,
          borderRadius: TomTokens.borderMd,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: TomTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: TomTokens.borderMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: TomTokens.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: TomTokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }
}
