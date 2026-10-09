const accountService = require('../services/accountService');

/**
 * Middleware para validar que las peticiones a rutas de streaming
 * cuenten con una licencia activa no vencida ni revocada.
 */
function requireActiveLicense(req, res, next) {
  // 1. Extraer credenciales desde Header, Parámetros o Cookies
  const authHeader = req.headers['authorization'] || '';
  const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : null;
  const token = bearerToken || req.headers['x-license-token'] || req.query.token || req.query.t;
  const deviceId = req.headers['x-device-id'] || req.query.deviceId || req.query.dev;
  const code = req.headers['x-client-code'] || req.query.code;

  // Permitir accesos del administrador con x-admin-key o sesión admin
  const adminKey = req.headers['x-admin-key'] || req.query.adminKey;
  const configuredAdminPass = process.env.ADMIN_PASSWORD || '123456';
  if (adminKey && adminKey === configuredAdminPass) {
    req.licenseClient = { id: 'admin', name: 'Administrador Master', role: 'admin' };
    return next();
  }

  // 2. Si no hay token ni código ni deviceId
  if (!token && !code && !deviceId) {
    return res.status(401).json({
      success: false,
      error: 'Acceso no autorizado: Se requiere token de licencia o identificador de pantalla activo.',
      code: 'LICENSE_REQUIRED'
    });
  }

  // 3. Validar con el motor central de cuentas
  try {
    const verification = accountService.verifyLicense(deviceId || 'WEB_ANON', { token, code });

    if (!verification.active) {
      return res.status(403).json({
        success: false,
        error: verification.message || 'Membresía no válida o expirada.',
        reason: verification.reason || 'expired',
        code: 'LICENSE_INVALID'
      });
    }

    // Adjuntar la información del cliente validado a la solicitud
    req.licenseClient = verification.client;
    next();
  } catch (err) {
    console.error('[licenseAuthMiddleware] Error verificando licencia:', err.message);
    return res.status(500).json({
      success: false,
      error: 'Error interno verificando la licencia del dispositivo.'
    });
  }
}

/**
 * Middleware permisivo que verifica la licencia si está presente pero no bloquea si es pública
 */
function optionalLicense(req, res, next) {
  const token = (req.headers['authorization'] || '').replace(/^Bearer\s+/, '') || req.query.token;
  const deviceId = req.headers['x-device-id'] || req.query.deviceId;
  if (token || deviceId) {
    try {
      const v = accountService.verifyLicense(deviceId || 'WEB_ANON', { token });
      if (v.active) {
        req.licenseClient = v.client;
      }
    } catch (_) {}
  }
  next();
}

module.exports = {
  requireActiveLicense,
  optionalLicense
};
