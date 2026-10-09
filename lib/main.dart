import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_service.dart';
import 'theme/tom_tokens.dart';
import 'views/activation_view.dart';
import 'views/home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Estilo de barras del sistema con negro absoluto OLED
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const VjStreamApp());
}

/// Scroll behavior optimizado para permitir navegación suave con D-Pad, mouse, trackpad y touch
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class VjStreamApp extends StatelessWidget {
  const VjStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOM TV',
      debugShowCheckedModeBanner: false,
      scrollBehavior: AppScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TomTokens.backgroundMain, // Negro Carbón (#0B0B0E)
        primaryColor: TomTokens.primaryAccent,             // Rojo Neón Carmesí (#E50914)
        colorScheme: const ColorScheme.dark(
          primary: TomTokens.primaryAccent,
          secondary: TomTokens.primaryAccentGlow,
          surface: TomTokens.surfaceCard,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: TomTokens.backgroundMain,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFF8F92A1)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Compuerta de autorización: valida si la pantalla está activada por el administrador
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;
  bool _isAuthorized = false;

  @override
  void initState() {
    super.initState();
    _checkAuthorization();
  }

  Future<void> _checkAuthorization() async {
    // 1. Probar validación directa contra el servidor con token o sesión guardada
    final licResult = await AuthService.verifyLicenseWithServer();
    if (licResult.isValid && mounted) {
      setState(() {
        _isAuthorized = true;
        _isChecking = false;
      });
      return;
    }

    // 2. Si no hay conexión o no hay sesión, comprobar sesión local
    final hasSession = await AuthService.hasValidSavedSession();
    if (hasSession && mounted) {
      setState(() {
        _isAuthorized = true;
        _isChecking = false;
      });
      return;
    }

    // 3. Primera instalación o licencia no válida: mostrar pantalla de activación
    if (mounted) {
      setState(() {
        _isAuthorized = false;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFE50914)),
              SizedBox(height: 16),
              Text(
                'Iniciando TOM TV...',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_isAuthorized) {
      return const HomeView();
    } else {
      return ActivationView(
        onActivated: () {
          if (mounted) {
            setState(() {
              _isAuthorized = true;
            });
          }
        },
      );
    }
  }
}

