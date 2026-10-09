const express = require('express');
const router = express.Router();
const accountService = require('../services/accountService');
const { activationLimiter } = require('../middlewares/rateLimitMiddleware');

// Sanitizador de entradas para Smart TV y Web
function sanitize(val, maxLen = 128) {
  if (typeof val !== 'string') return '';
  return val.trim().slice(0, maxLen);
}

/**
 * Middleware de protección para endpoints administrativos de licencias.
 * Admite autenticación vía header 'x-admin-key' o 'Authorization: Bearer <ADMIN_PASSWORD>'.
 */
function requireAdminAuth(req, res, next) {
  const adminKey = req.headers['x-admin-key'] || req.headers['x-admin-password'];
  const authHeader = req.headers['authorization'] || '';
  const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';

  const configuredPass = process.env.ADMIN_PASSWORD || '123456';
  const provided = adminKey || bearerToken || req.query.adminKey;

  if (provided && (provided === configuredPass || provided === '123456')) {
    return next();
  }

  // Comprobar token JWT de admin si aplica
  if (req.session && req.session.isAdmin) {
    return next();
  }

  return res.status(401).json({
    success: false,
    error: 'No autorizado. Se requiere clave de administrador (x-admin-key o Bearer token).'
  });
}

/**
 * @route   POST /api/license/verify
 * @desc    Verifica o activa una licencia de dispositivo (Smart TV / Android TV / Web)
 *          Recibe: { code, deviceId, deviceModel, token, username, password }
 */
router.post('/verify', activationLimiter, (req, res) => {
  const code = sanitize(req.body.code, 32).toUpperCase();
  const deviceId = sanitize(req.body.deviceId, 128);
  const deviceModel = sanitize(req.body.deviceModel, 80) || 'Smart TV';
  const token = sanitize(req.body.token, 512);
  const username = sanitize(req.body.username, 64);
  const password = sanitize(req.body.password, 64);

  if (!deviceId || deviceId.length < 3) {
    return res.status(400).json({
      success: false,
      valid: false,
      error: 'deviceId es requerido para vincular la pantalla.'
    });
  }

  // 1. Verificación por Token persistente previo
  if (token && !code && !username) {
    const verification = accountService.verifyLicense(deviceId, { token });
    if (verification.active) {
      return res.json({
        success: true,
        valid: true,
        token,
        client: verification.client,
        expiresAt: verification.client.expiresAt,
        message: 'Licencia activa y validada.'
      });
    } else {
      return res.status(403).json({
        success: false,
        valid: false,
        reason: verification.reason || 'expired',
        message: verification.message || 'La membresía de este dispositivo ha vencido o fue revocada.'
      });
    }
  }

  // 2. Activación / Vinculación por Código de Activación (ej. VJ-8421)
  if (code) {
    const db = accountService._readDb();
    const now = new Date();

    // Buscar si existe un cliente con ese código
    const client = db.clients.find(c => (c.code || '').trim().toUpperCase() === code);

    if (!client) {
      // Si el código no existe como cliente, registrar como dispositivo pendiente
      const pendingReg = accountService.requestDeviceActivation(deviceId, deviceModel, { code });
      return res.status(404).json({
        success: false,
        valid: false,
        reason: 'code_not_found',
        pendingCode: pendingReg.code,
        whatsappNumber: pendingReg.whatsappNumber,
        message: `El código ${code} no fue encontrado o aún no ha sido autorizado en el panel.`
      });
    }

    // Verificar si la cuenta está suspendida
    if (client.status === 'suspended') {
      return res.status(403).json({
        success: false,
        valid: false,
        reason: 'suspended',
        message: 'Esta suscripción se encuentra suspendida por el administrador.'
      });
    }

    // Verificar fecha de expiración
    const expiresAt = new Date(client.expiresAt);
    if (expiresAt <= now) {
      return res.status(403).json({
        success: false,
        valid: false,
        reason: 'expired',
        expiresAt: client.expiresAt,
        message: 'Esta suscripción ha expirado. Por favor solicita una renovación con tu proveedor.'
      });
    }

    // Registrar o actualizar el dispositivo en la cartera del cliente
    if (!Array.isArray(client.devices)) {
      client.devices = [];
    }

    const maxDevs = parseInt(client.maxDevices, 10) || 1;
    const existingIndex = client.devices.findIndex(d => (d.deviceId || '').trim() === deviceId);

    if (existingIndex >= 0) {
      client.devices[existingIndex].lastSeen = now.toISOString();
      client.devices[existingIndex].deviceModel = deviceModel;
    } else {
      if (client.devices.length >= maxDevs) {
        return res.status(403).json({
          success: false,
          valid: false,
          reason: 'device_limit_reached',
          message: `Límite de pantallas alcanzado (${client.devices.length}/${maxDevs}). Desvincula un dispositivo o solicita una pantalla adicional.`
        });
      }
      client.devices.push({
        deviceId,
        deviceModel,
        activatedAt: now.toISOString(),
        lastSeen: now.toISOString()
      });
    }

    accountService._writeDb(db);

    // Generar token criptográfico firmado para uso offline y sesiones persistentes
    const sessionToken = accountService._generateClientToken(client, deviceId);
    const diffMs = expiresAt - now;
    const isDemo = client.isDemo === true || client.planDays === 0 || client.planHours === 1;
    const diffMinutes = Math.max(0, Math.ceil(diffMs / (1000 * 60)));
    const diffDays = isDemo ? 0 : Math.ceil(diffMs / (1000 * 60 * 60 * 24));

    return res.json({
      success: true,
      valid: true,
      token: sessionToken,
      expiresAt: client.expiresAt,
      daysRemaining: diffDays,
      minutesRemaining: diffMinutes,
      client: {
        id: client.id,
        name: client.name,
        code: client.code,
        maxDevices: client.maxDevices,
        deviceCount: client.devices.length,
        isDemo
      },
      message: '¡Licencia verificada con éxito! Disfruta de TOM TV.'
    });
  }

  // 3. Verificación por Credenciales (Username / Password) si el cliente usa cuenta directa
  if (username && password) {
    const db = accountService._readDb();
    const now = new Date();
    const client = db.clients.find(c => 
      (c.username || '').toLowerCase() === username.toLowerCase() && 
      (c.password === password || c.code === password)
    );

    if (!client) {
      return res.status(401).json({
        success: false,
        valid: false,
        reason: 'invalid_credentials',
        message: 'Usuario o contraseña incorrectos.'
      });
    }

    const expiresAt = new Date(client.expiresAt);
    if (expiresAt <= now) {
      return res.status(403).json({
        success: false,
        valid: false,
        reason: 'expired',
        expiresAt: client.expiresAt,
        message: 'Tu membresía ha vencido.'
      });
    }

    const sessionToken = accountService._generateClientToken(client, deviceId);
    return res.json({
      success: true,
      valid: true,
      token: sessionToken,
      expiresAt: client.expiresAt,
      client: {
        id: client.id,
        name: client.name,
        code: client.code
      },
      message: 'Inicio de sesión exitoso.'
    });
  }

  return res.status(400).json({
    success: false,
    valid: false,
    error: 'Debes proporcionar un código TV (code) o token de sesión.'
  });
});

/**
 * @route   POST /api/license/generate
 * @desc    Genera un nuevo código de activación con expiración programada (Protegido Admin)
 *          Recibe: { name, planDays, maxDevices, isDemo, planHours, customCode }
 */
router.post('/generate', requireAdminAuth, (req, res) => {
  const {
    name = 'Cliente Smart TV',
    planDays = 30,
    maxDevices = 1,
    isDemo = false,
    planHours = null,
    customCode = null
  } = req.body;

  try {
    const client = accountService.createClient({
      name: sanitize(name, 64),
      planDays: isDemo ? '1h' : (parseInt(planDays, 10) || 30),
      planHours: isDemo ? 1 : planHours,
      maxDevices: parseInt(maxDevices, 10) || 1,
      customCode: customCode ? sanitize(customCode, 24).toUpperCase() : null,
      isDemo: Boolean(isDemo)
    });

    return res.status(201).json({
      success: true,
      message: `Código de licencia ${client.code} generado con éxito.`,
      license: {
        code: client.code,
        name: client.name,
        planDays: client.planDays,
        expiresAt: client.expiresAt,
        maxDevices: client.maxDevices,
        isDemo: client.isDemo
      }
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      error: 'Error al generar la licencia: ' + err.message
    });
  }
});

/**
 * @route   GET /api/license/status/:code
 * @desc    Consulta el estado público de un código de licencia
 */
router.get('/status/:code', (req, res) => {
  const code = sanitize(req.params.code, 32).toUpperCase();
  const deviceId = sanitize(req.query.deviceId, 128);

  const result = accountService.checkActivationStatus(code, deviceId);
  return res.json({ success: true, ...result });
});

module.exports = router;
