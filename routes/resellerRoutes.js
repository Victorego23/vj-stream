const express = require('express');
const router = express.Router();
const accountService = require('../services/accountService');
const { loginRateLimiter } = require('../middlewares/rateLimitMiddleware');

/**
 * Middleware para autenticar las peticiones de revendedores
 */
function resellerAuth(req, res, next) {
  const authHeader = req.headers['authorization'] || req.headers['x-reseller-token'] || req.query.token;
  if (!authHeader) {
    return res.status(401).json({
      success: false,
      error: 'Se requiere inicio de sesión de revendedor.'
    });
  }

  const cleanToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;
  const reseller = accountService.verifyResellerAuth(cleanToken);

  if (!reseller) {
    return res.status(403).json({
      success: false,
      error: 'Sesión de revendedor caducada o inválida. Por favor inicia sesión nuevamente.'
    });
  }

  if (reseller.status === 'suspended') {
    return res.status(403).json({
      success: false,
      error: 'Tu cuenta de revendedor está suspendida. Contacta al administrador.'
    });
  }

  req.reseller = reseller;
  next();
}

/**
 * @route   POST /api/reseller/login
 * @desc    Inicio de sesión para revendedores en el Sub-Panel
 */
router.post('/login', loginRateLimiter, (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({
        success: false,
        error: 'Usuario y contraseña requeridos.'
      });
    }

    const authResult = accountService.authenticateReseller(username, password);
    const settings = accountService.getSettings();

    return res.json({
      success: true,
      token: authResult.token,
      reseller: authResult.reseller,
      adminContact: {
        whatsappNumber: settings.whatsappNumber || '+51999999999'
      }
    });
  } catch (error) {
    return res.status(401).json({
      success: false,
      error: error.message || 'Error de autenticación'
    });
  }
});

/**
 * @route   GET /api/reseller/config
 * @desc    Obtiene configuración básica de contacto del administrador para recargas
 */
router.get('/config', (req, res) => {
  const settings = accountService.getSettings();
  return res.json({
    success: true,
    whatsappNumber: settings.whatsappNumber || '+51999999999'
  });
});

// Todas las rutas siguientes requieren sesión activa de revendedor
router.use(resellerAuth);

/**
 * @route   GET /api/reseller/me
 * @desc    Obtiene el perfil actualizado del revendedor con su saldo de créditos
 */
router.get('/me', (req, res) => {
  const profile = accountService.getResellerById(req.reseller.id);
  const settings = accountService.getSettings();

  return res.json({
    success: true,
    reseller: profile,
    adminContact: {
      whatsappNumber: settings.whatsappNumber || '+51999999999'
    }
  });
});

/**
 * @route   GET /api/reseller/clients
 * @desc    Obtiene únicamente los clientes pertenecientes a este revendedor
 */
router.get('/clients', (req, res) => {
  const clients = accountService.getResellerClients(req.reseller.id);
  const profile = accountService.getResellerById(req.reseller.id);

  return res.json({
    success: true,
    credits: profile.credits,
    clients
  });
});

/**
 * @route   POST /api/reseller/clients
 * @desc    Crea un nuevo cliente descontando créditos del saldo del revendedor
 */
router.post('/clients', (req, res) => {
  try {
    const { name, planDays, maxDevices, customCode } = req.body;
    const result = accountService.createClientForReseller(req.reseller.id, {
      name,
      planDays,
      maxDevices,
      customCode
    });

    return res.status(201).json(result);
  } catch (error) {
    return res.status(400).json({
      success: false,
      error: error.message || 'Error al crear cliente'
    });
  }
});

/**
 * @route   POST /api/reseller/clients/:id/renew
 * @desc    Renueva la suscripción de un cliente descontando créditos del revendedor
 */
router.post('/clients/:id/renew', (req, res) => {
  try {
    const { id } = req.params;
    const { additionalDays } = req.body;

    const result = accountService.renewClientForReseller(req.reseller.id, id, additionalDays);
    return res.json(result);
  } catch (error) {
    return res.status(400).json({
      success: false,
      error: error.message || 'Error al renovar cliente'
    });
  }
});

/**
 * @route   DELETE /api/reseller/clients/:id
 * @desc    Elimina un cliente de la cartera del revendedor
 */
router.delete('/clients/:id', (req, res) => {
  try {
    const { id } = req.params;
    const deleted = accountService.deleteClientForReseller(req.reseller.id, id);

    if (!deleted) {
      return res.status(404).json({
        success: false,
        error: 'Cliente no encontrado o no pertenece a tu cuenta.'
      });
    }

    return res.json({
      success: true,
      message: 'Cliente eliminado correctamente.'
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: error.message || 'Error al eliminar cliente'
    });
  }
});

module.exports = router;
