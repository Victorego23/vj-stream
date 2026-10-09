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
  static const String _prefClientIdKey = 'vj_stream_client_id';
  static const String _prefClientUsernameKey = 'vj_stream_client_username';
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
  static Future<DeviceAuthInfo> registerOrCheckDevice({String? customCode}) async {
    try {
      final deviceId = await getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_prefSessionTokenKey);
      final savedCode = customCode ?? prefs.getString(_prefClientCodeKey);

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
              : 'Dispositivo TOM TV',
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
              if (client['id'] != null && client['id'].toString().isNotEmpty) {
                await prefs.setString(_prefClientIdKey, client['id'].toString());
              }
              if (client['username'] != null && client['username'].toString().isNotEmpty) {
                await prefs.setString(_prefClientUsernameKey, client['username'].toString());
              }
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
              if (client['id'] != null && client['id'].toString().isNotEmpty) {
                await prefs.setString(_prefClientIdKey, client['id'].toString());
              }
              if (client['username'] != null && client['username'].toString().isNotEmpty) {
                await prefs.setString(_prefClientUsernameKey, client['username'].toString());
              }
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

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefSessionTokenKey);
      final clientCode = prefs.getString(_prefClientCodeKey);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'deviceId': deviceId,
          'token': token,
          'code': clientCode,
        }),
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

  /// Comprueba si el dispositivo tiene una sesión activa válida guardada localmente
  static Future<bool> hasValidSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefSessionTokenKey);
      final clientCode = prefs.getString(_prefClientCodeKey);
      final exp = prefs.getString(_prefExpiresAtKey);

      // Si tiene código o token registrado previamente
      if ((token != null && token.isNotEmpty) || (clientCode != null && clientCode.isNotEmpty)) {
        if (exp != null && exp.isNotEmpty) {
          final expDate = DateTime.tryParse(exp);
          if (expDate != null && expDate.isBefore(DateTime.now())) {
            return false; // Vencida
          }
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Activa o vincula manualmente un código existente (ej: VJ-3166) ingresado por el usuario
  static Future<DeviceAuthInfo> activateWithManualCode(String manualCode) async {
    final cleanCode = manualCode.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefClientCodeKey, cleanCode);
    return registerOrCheckDevice(customCode: cleanCode);
  }

  /// Verifica y activa la licencia contra el endpoint unificado /api/license/verify
  static Future<LicenseVerificationResult> verifyLicenseWithServer({
    String? code,
    String? token,
    String? username,
    String? password,
  }) async {
    try {
      final deviceId = await getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final effectiveToken = token ?? prefs.getString(_prefSessionTokenKey);
      final effectiveCode = code != null && code.trim().isNotEmpty
          ? code.trim().toUpperCase()
          : (effectiveToken == null ? prefs.getString(_prefClientCodeKey) : null);

      final origin = ApiService().serverOrigin;
      final uri = Uri.parse('$origin/api/license/verify');

      String modelDesc = 'Dispositivo TOM TV';
      if (kIsWeb) {
        modelDesc = 'Smart TV Web (Samsung Tizen / LG webOS)';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        modelDesc = 'Android TV / Móvil';
      }

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'deviceId': deviceId,
          'deviceModel': modelDesc,
          'code': effectiveCode,
          'token': effectiveToken,
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && data['valid'] == true) {
        final client = data['client'] as Map<String, dynamic>?;
        final resToken = data['token'] as String?;
        final resExp = (data['expiresAt'] ?? client?['expiresAt'])?.toString();
        final resCode = client?['code']?.toString() ?? effectiveCode;
        final resName = client?['name']?.toString();

        if (resToken != null && resToken.isNotEmpty) {
          await prefs.setString(_prefSessionTokenKey, resToken);
        }
        if (resCode != null && resCode.isNotEmpty) {
          await prefs.setString(_prefClientCodeKey, resCode);
        }
        if (resName != null && resName.isNotEmpty) {
          await prefs.setString(_prefClientNameKey, resName);
        }
        if (resExp != null && resExp.isNotEmpty) {
          await prefs.setString(_prefExpiresAtKey, resExp);
        }
        if (client?['id'] != null) {
          await prefs.setString(_prefClientIdKey, client!['id'].toString());
        }

        return LicenseVerificationResult(
          isValid: true,
          token: resToken,
          expiresAt: resExp,
          daysRemaining: data['daysRemaining'] is int ? data['daysRemaining'] : 30,
          minutesRemaining: data['minutesRemaining'] is int ? data['minutesRemaining'] : 0,
          clientName: resName,
          clientCode: resCode,
          message: data['message'] ?? 'Licencia activada con éxito.',
        );
      } else {
        return LicenseVerificationResult(
          isValid: false,
          reason: data['reason']?.toString() ?? 'invalid',
          message: data['message'] ?? data['error'] ?? 'El código no es válido o ha expirado.',
        );
      }
    } catch (e) {
      debugPrint('[AuthService] Error verificando licencia: $e');
      return LicenseVerificationResult(
        isValid: false,
        reason: 'network_error',
        message: 'No fue posible conectar con el servidor de licencias. Revisa tu conexión a internet.',
      );
    }
  }

  static Future<String> getClientName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefClientNameKey) ?? 'Cliente TOM TV';
  }

  static Future<String?> getSavedClientCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefClientCodeKey);
  }

  static Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefSessionTokenKey);
  }

  static Future<String?> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefClientIdKey);
  }

  static Future<String?> getClientUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefClientUsernameKey);
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
    await prefs.remove(_prefClientIdKey);
    await prefs.remove(_prefClientUsernameKey);
    await prefs.remove(_prefExpiresAtKey);
  }
}

/// Modelo con el resultado detallado de la verificación de licencia
class LicenseVerificationResult {
  final bool isValid;
  final String? token;
  final String? expiresAt;
  final int daysRemaining;
  final int minutesRemaining;
  final String? clientName;
  final String? clientCode;
  final String? reason;
  final String message;

  LicenseVerificationResult({
    required this.isValid,
    this.token,
    this.expiresAt,
    this.daysRemaining = 0,
    this.minutesRemaining = 0,
    this.clientName,
    this.clientCode,
    this.reason,
    required this.message,
  });
}
