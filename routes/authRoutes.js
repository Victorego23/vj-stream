const express = require('express');
const router = express.Router();
const accountService = require('../services/accountService');
const {
  activationLimiter,
  demoLimiter,
  statusPollLimiter
} = require('../middlewares/rateLimitMiddleware');

// Validador y sanitizador de entradas de dispositivo y códigos
function sanitizeInput(val, maxLen = 64) {
  if (typeof val !== 'string') return '';
  return val.trim().slice(0, maxLen);
}

function isValidCode(code) {
  if (!code || typeof code !== 'string') return false;
  return /^[A-Za-z0-9_-]{3,24}$/.test(code.trim());
}

/**
 * @route   POST /api/auth/register-device
 * @desc    Registra un dispositivo (Smart TV / Móvil). Protegido contra fuerza bruta
 */
router.post('/register-device', activationLimiter, (req, res) => {
  const deviceId = sanitizeInput(req.body.deviceId, 128);
  const deviceModel = sanitizeInput(req.body.deviceModel, 64) || 'Android Device';
  const token = sanitizeInput(req.body.token, 256);
  const code = sanitizeInput(req.body.code, 24);

  if (!deviceId || deviceId.length < 4) {
    return res.status(400).json({ success: false, error: 'deviceId inválido o requerido.' });
  }

  if (code && !isValidCode(code)) {
    return res.status(400).json({ success: false, error: 'Formato de código inválido.' });
  }

  const result = accountService.requestDeviceActivation(deviceId, deviceModel, { token, code });
  return res.json({ success: true, ...result });
});

/**
 * @route   GET /api/auth/check-status/:code
 * @desc    Consulta si el código de activación ya fue autorizado (Rate limited anti-polling spam)
 */
router.get('/check-status/:code', statusPollLimiter, (req, res) => {
  const code = sanitizeInput(req.params.code, 24);
  const deviceId = sanitizeInput(req.query.deviceId, 128);

  if (!code || !isValidCode(code)) {
    return res.status(400).json({ success: false, error: 'Código de activación inválido.' });
  }

  const result = accountService.checkActivationStatus(code.toUpperCase(), deviceId);
  return res.json({ success: true, ...result });
});

/**
 * @route   POST /api/auth/verify-license
 * @desc    Verifica la validez de la membresía en cada reproducción (Blindado contra enumeración)
 */
router.post('/verify-license', activationLimiter, (req, res) => {
  const deviceId = sanitizeInput(req.body.deviceId, 128);
  const token = sanitizeInput(req.body.token, 256);
  const code = sanitizeInput(req.body.code, 24);

  if (!deviceId || deviceId.length < 4) {
    return res.status(400).json({ success: false, error: 'deviceId es requerido.' });
  }

  if (code && !isValidCode(code)) {
    return res.status(400).json({ success: false, error: 'Código no válido.' });
  }

  const result = accountService.verifyLicense(deviceId, { token, code });
  return res.json({ success: true, ...result });
});

/**
 * @route   POST /api/auth/request-demo
 * @desc    Solicita activación de prueba gratuita (Máx 4 por IP cada 2 horas contra abuso)
 */
router.post('/request-demo', demoLimiter, (req, res) => {
  const deviceId = sanitizeInput(req.body.deviceId, 128);
  const deviceModel = sanitizeInput(req.body.deviceModel, 64) || 'Web PWA / Smart TV';

  if (!deviceId || deviceId.length < 4) {
    return res.status(400).json({ success: false, error: 'deviceId es requerido.' });
  }

  const result = accountService.requestPublicTrialDemo(deviceId, deviceModel);
  return res.json(result);
});

/**
 * @route   GET /api/auth/public-info
 * @desc    Devuelve configuración pública para WhatsApp y datos de contacto oficiales
 */
router.get('/public-info', (req, res) => {
  return res.json({
    success: true,
    ...accountService.getPublicSettings()
  });
});

module.exports = router;
