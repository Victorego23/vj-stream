import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_service.dart';
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
        scaffoldBackgroundColor: const Color(0xFF101018), // Dark Mode puro TOM TV
        primaryColor: const Color(0xFF2962FF),             // Azul eléctrico primario
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2962FF),
          secondary: Color(0xFF2962FF),
          surface: Color(0xFF1C1C28),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101018),
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
    // Si ya existe una sesión guardada localmente válida, autorizamos de inmediato
    final hasSession = await AuthService.hasValidSavedSession();
    if (hasSession && mounted) {
      setState(() {
        _isAuthorized = true;
        _isChecking = false;
      });
      // Sincronizar silenciosamente en segundo plano sin interrumpir la experiencia
      AuthService.registerOrCheckDevice();
      return;
    }

    // Si es una primera instalación sin sesión previa, registrar ante el servidor
    final info = await AuthService.registerOrCheckDevice();
    if (mounted) {
      setState(() {
        _isAuthorized = info.isActive;
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

