import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class DeviceAuthInfo {
  final String status; // 'active', 'pending', 'expired', 'suspended', 'error'
  final String? code;
  final String? clientName;
  final String? expiresAt;
  final int maxDevices;
  final String? message;
  final String? whatsappNumber;

  DeviceAuthInfo({
    required this.status,
    this.code,
    this.clientName,
    this.expiresAt,
    this.maxDevices = 1,
    this.message,
    this.whatsappNumber,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';
  bool get isSuspended => status == 'suspended';
}

/// Servicio de autenticación de dispositivo y validación de membresía para VJ STREAM
class AuthService {
  static const String _prefDeviceIdKey = 'vj_stream_device_id';
  static const String _prefSessionTokenKey = 'vj_stream_session_token';
  static const String _prefClientCodeKey = 'vj_stream_client_code';
  static const String _prefClientNameKey = 'vj_stream_client_name';
  static const String _prefExpiresAtKey = 'vj_stream_expires_at';

  static String? _cachedDeviceId;

  /// Obtiene o genera un identificador único persistente para este dispositivo
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_prefDeviceIdKey);
    if (id == null || id.isEmpty) {
      final randomNum = Random().nextInt(900000) + 100000;
      id = 'VJ_DEV_${DateTime.now().millisecondsSinceEpoch}_$randomNum';
      await prefs.setString(_prefDeviceIdKey, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// Registra el dispositivo ante el servidor y consulta si está activo o pendiente de activación
  static Future<DeviceAuthInfo> registerOrCheckDevice() async {
    try {
      final deviceId = await getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_prefSessionTokenKey);
      final savedCode = prefs.getString(_prefClientCodeKey);

      final origin = ApiService().serverOrigin;
      final uri = Uri.parse('$origin/api/auth/register-device');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'deviceId': deviceId,
          'token': savedToken,
          'code': savedCode,
          'deviceModel': defaultTargetPlatform == TargetPlatform.android
              ? 'Android TV / Móvil'
              : 'Dispositivo VJ STREAM',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          final status = data['status'] as String? ?? 'pending';

          if (status == 'active') {
            final client = data['client'] as Map<String, dynamic>?;
            if (client != null) {
              await prefs.setString(_prefClientNameKey, client['name'] ?? '');
              await prefs.setString(_prefExpiresAtKey, client['expiresAt'] ?? '');
              if (client['code'] != null && client['code'].toString().isNotEmpty) {
                await prefs.setString(_prefClientCodeKey, client['code'].toString());
              }
            }
            if (data['code'] != null && data['code'].toString().isNotEmpty) {
              await prefs.setString(_prefClientCodeKey, data['code'].toString());
            }
            if (data['token'] != null && data['token'].toString().isNotEmpty) {
              await prefs.setString(_prefSessionTokenKey, data['token'].toString());
            }

            return DeviceAuthInfo(
              status: 'active',
              clientName: client?['name'],
              expiresAt: client?['expiresAt'],
              maxDevices: client?['maxDevices'] ?? 1,
            );
          }

          return DeviceAuthInfo(
            status: status,
            code: data['code'],
            message: data['message'],
            whatsappNumber: data['whatsappNumber'],
          );
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Error registrando dispositivo: $e');
    }

    return DeviceAuthInfo(status: 'error', message: 'No se pudo conectar con el servidor.');
  }

  /// Sondeo automático de estado cuando el cliente tiene la pantalla de código abierta en su TV
  static Future<DeviceAuthInfo> pollActivationStatus(String code) async {
    try {
      final deviceId = await getDeviceId();
      final origin = ApiService().serverOrigin;
      final uri = Uri.parse('$origin/api/auth/check-status/$code?deviceId=$deviceId');

      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          final status = data['status'] as String? ?? 'pending';

          if (status == 'active') {
            final client = data['client'] as Map<String, dynamic>?;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefClientCodeKey, code);
            if (client != null) {
              await prefs.setString(_prefClientNameKey, client['name'] ?? '');
              await prefs.setString(_prefExpiresAtKey, client['expiresAt'] ?? '');
              if (client['code'] != null && client['code'].toString().isNotEmpty) {
                await prefs.setString(_prefClientCodeKey, client['code'].toString());
              }
            }
            if (data['token'] != null && data['token'].toString().isNotEmpty) {
              await prefs.setString(_prefSessionTokenKey, data['token'].toString());
            }

            return DeviceAuthInfo(
              status: 'active',
              clientName: client?['name'],
              expiresAt: client?['expiresAt'],
              maxDevices: client?['maxDevices'] ?? 1,
            );
          }

          return DeviceAuthInfo(status: status, code: data['code']);
        }
      }
    } catch (_) {}

    return DeviceAuthInfo(status: 'pending', code: code);
  }

  /// Verifica si la membresía sigue activa
  static Future<bool> isMembershipActive() async {
    try {
      final deviceId = await getDeviceId();
      final origin = ApiService().serverOrigin;
      final uri = Uri.parse('$origin/api/auth/verify-license');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'deviceId': deviceId}),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['active'] == true;
      }
    } catch (_) {}

    // Si no hay red, comprobamos fecha guardada localmente
    try {
      final prefs = await SharedPreferences.getInstance();
      final exp = prefs.getString(_prefExpiresAtKey);
      if (exp != null) {
        return DateTime.parse(exp).isAfter(DateTime.now());
      }
    } catch (_) {}

    return true; // Tolerancia si la red falla momentáneamente
  }

  static Future<String> getClientName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefClientNameKey) ?? 'Cliente VJ STREAM';
  }

  static Future<String?> getExpiresAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefExpiresAtKey);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSessionTokenKey);
    await prefs.remove(_prefClientCodeKey);
    await prefs.remove(_prefClientNameKey);
    await prefs.remove(_prefExpiresAtKey);
  }
}
