import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Servicio de seguridad criptográfica para la aplicación VJ STREAM.
/// Firma todas las solicitudes HTTP salientes con HMAC-SHA256 para autenticar
/// que el cliente sea la app oficial y proteger los tokens de Real-Debrid.
class SecurityService {
  // Clave secreta compartida con el backend
  static const String _secretKey = 'VJ_SECURE_STREAM_APP_SIG_KEY_2026_@#!';

  /// Genera cabeceras de firma HMAC para una URL determinada
  static Map<String, String> getSecurityHeaders(String urlOrPath) {
    final uri = Uri.tryParse(urlOrPath);
    final path = (uri != null && uri.path.isNotEmpty ? uri.path : urlOrPath).toLowerCase();

    // Timestamp actual en segundos UNIX
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // Payload de firma canónica: timestamp:path
    final payload = '$timestamp:$path';

    // Generación de firma HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    final signature = hmac.convert(utf8.encode(payload)).toString();

    return {
      'x-vj-timestamp': timestamp,
      'x-vj-signature': signature,
      'x-vj-client': 'VJ-STREAM-OFFICIAL-APP',
      'Content-Type': 'application/json',
    };
  }
}
