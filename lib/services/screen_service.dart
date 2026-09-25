import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servicio para controlar el encendido permanente de pantalla (WakeLock nativo).
/// Evita apagados inesperados o suspensión del celular / Smart TV mientras el usuario ve una película.
class ScreenService {
  static const MethodChannel _channel = MethodChannel('com.vjstream.vj_stream/screen_manager');

  /// Activa o desactiva la permanencia de pantalla encendida.
  /// En Android activa FLAG_KEEP_SCREEN_ON directamente en la ventana nativa.
  static Future<void> keepScreenOn(bool enabled) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('keepScreenOn', {'enabled': enabled});
      }
    } catch (e) {
      debugPrint('[ScreenService] Error en keepScreenOn($enabled): $e');
    }
  }

  /// Consulta si la pantalla está actualmente fijada para no apagarse.
  static Future<bool> isScreenOnKept() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final res = await _channel.invokeMethod<bool>('isScreenOnKept');
        return res ?? false;
      }
    } catch (e) {
      debugPrint('[ScreenService] Error en isScreenOnKept: $e');
    }
    return false;
  }
}
