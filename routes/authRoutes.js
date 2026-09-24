const express = require('express');
const router = express.Router();
const accountService = require('../services/accountService');

/**
 * @route   POST /api/auth/register-device
 * @desc    Registra un dispositivo (Smart TV / Móvil). Devuelve sesión activa o código de activación
 */
router.post('/register-device', (req, res) => {
  const { deviceId, deviceModel } = req.body;

  if (!deviceId) {
    return res.status(400).json({ success: false, error: 'deviceId es requerido.' });
  }

  const result = accountService.requestDeviceActivation(deviceId, deviceModel || 'Android Device');
  return res.json({ success: true, ...result });
});

/**
 * @route   GET /api/auth/check-status/:code
 * @desc    Consulta si el código de activación ya fue autorizado por el administrador
 */
router.get('/check-status/:code', (req, res) => {
  const { code } = req.params;
  const { deviceId } = req.query;

  if (!code) {
    return res.status(400).json({ success: false, error: 'Código requerido.' });
  }

  const result = accountService.checkActivationStatus(code.toUpperCase().trim(), deviceId);
  return res.json({ success: true, ...result });
});

/**
 * @route   POST /api/auth/verify-license
 * @desc    Verifica la validez de la membresía en cada reproducción o inicio
 */
router.post('/verify-license', (req, res) => {
  const { deviceId } = req.body;

  if (!deviceId) {
    return res.status(400).json({ success: false, error: 'deviceId es requerido.' });
  }

  const result = accountService.verifyLicense(deviceId);
  return res.json({ success: true, ...result });
});

/**
 * @route   GET /api/auth/settings
 * @desc    Obtiene datos de contacto de WhatsApp para renovación
 */
router.get('/settings', (req, res) => {
  const settings = accountService.getSettings();
  return res.json({ success: true, settings });
});

module.exports = router;
