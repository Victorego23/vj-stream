const express = require('express');
const router = express.Router();
const accountService = require('../services/accountService');
const channelService = require('../services/channelService');

// Middleware para verificar la contraseña del Administrador
function adminAuth(req, res, next) {
  const token = req.headers['x-admin-password'] || req.headers['authorization'] || req.query.key;
  if (!token) {
    return res.status(401).json({ success: false, error: 'Se requiere contraseña de administrador.' });
  }

  const cleanPass = token.startsWith('Bearer ') ? token.slice(7) : token;
  if (!accountService.verifyAdminPassword(cleanPass)) {
    return res.status(403).json({ success: false, error: 'Contraseña de administrador incorrecta.' });
  }

  next();
}

/**
 * @route   POST /api/admin/login
 * @desc    Valida credenciales de acceso al Panel Web de Administrador
 */
router.post('/login', (req, res) => {
  const { password } = req.body;
  if (!password || !accountService.verifyAdminPassword(password)) {
    return res.status(401).json({ success: false, error: 'Contraseña de administrador incorrecta.' });
  }

  return res.json({
    success: true,
    token: password,
    message: 'Bienvenido al Panel de Administrador VJ STREAM'
  });
});

// Todas las rutas siguientes requieren autenticación de administrador
router.use(adminAuth);

/**
 * @route   GET /api/admin/overview
 * @desc    Devuelve estadísticas generales, lista de clientes y pantallas pendientes
 */
router.get('/overview', (req, res) => {
  const clients = accountService.getClients();
  const pending = accountService.getPendingActivations();
  const settings = accountService.getSettings();

  const totalClients = clients.length;
  const activeClients = clients.filter(c => c.status === 'active').length;
  const expiringSoon = clients.filter(c => c.status === 'active' && c.daysRemaining <= 3).length;
  const expiredClients = clients.filter(c => c.status !== 'active').length;

  return res.json({
    success: true,
    stats: {
      totalClients,
      activeClients,
      expiringSoon,
      expiredClients,
      pendingCount: pending.length
    },
    clients,
    pending,
    settings
  });
});

/**
 * @route   POST /api/admin/activate-code
 * @desc    El Administrador aprueba una pantalla pendiente usando su código VJ-XXXX
 */
router.post('/activate-code', (req, res) => {
  const { code, name, planDays = 30, maxDevices = 1 } = req.body;

  if (!code || !name) {
    return res.status(400).json({ success: false, error: 'Código y nombre de cliente requeridos.' });
  }

  const result = accountService.activateCode(code.trim().toUpperCase(), {
    name,
    planDays: parseInt(planDays, 10),
    maxDevices: parseInt(maxDevices, 10)
  });

  if (!result.success) {
    return res.status(404).json(result);
  }

  return res.json(result);
});

/**
 * @route   POST /api/admin/create-client
 * @desc    Crea un cliente manual sin código previo
 */
router.post('/create-client', (req, res) => {
  const { name, planDays = 30, maxDevices = 1 } = req.body;

  if (!name || name.trim().length === 0) {
    return res.status(400).json({ success: false, error: 'El nombre es obligatorio.' });
  }

  const client = accountService.createClient({
    name,
    planDays: parseInt(planDays, 10),
    maxDevices: parseInt(maxDevices, 10)
  });

  return res.json({ success: true, client });
});

/**
 * @route   POST /api/admin/renew
 * @desc    Renueva la membresía sumando días (ej: +30 días tras pago)
 */
router.post('/renew', (req, res) => {
  const { clientId, days = 30 } = req.body;

  const client = accountService.renewClient(clientId, parseInt(days, 10));
  if (!client) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, client, message: `Membresía renovada por ${days} días con éxito.` });
});

/**
 * @route   POST /api/admin/toggle-status
 * @desc    Suspende o reactiva el acceso de un cliente
 */
router.post('/toggle-status', (req, res) => {
  const { clientId } = req.body;

  const client = accountService.toggleClientStatus(clientId);
  if (!client) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, client });
});

/**
 * @route   POST /api/admin/reset-devices
 * @desc    Limpia los dispositivos registrados del cliente para permitirle cambiar de TV
 */
router.post('/reset-devices', (req, res) => {
  const { clientId } = req.body;

  const client = accountService.resetClientDevices(clientId);
  if (!client) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, message: 'Dispositivos desvinculados correctamente.', client });
});

/**
 * @route   DELETE /api/admin/clients/:id
 * @desc    Elimina un cliente definitivamente
 */
router.delete('/clients/:id', (req, res) => {
  const deleted = accountService.deleteClient(req.params.id);
  if (!deleted) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, message: 'Cliente eliminado correctamente.' });
});

/**
 * @route   POST /api/admin/settings
 * @desc    Actualiza la contraseña del panel y el número de WhatsApp de contacto
 */
router.post('/settings', (req, res) => {
  const { adminPassword, whatsappNumber, whatsappMessage } = req.body;

  const updated = accountService.updateSettings({
    adminPassword,
    whatsappNumber,
    whatsappMessage
  });

  return res.json({ success: true, settings: updated, message: 'Ajustes guardados correctamente.' });
});

/**
 * ====================================================================
 * GESTIÓN DE CANALES DE TV EN VIVO (ADMIN)
 * ====================================================================
 */

/**
 * @route   GET /api/admin/channels
 * @desc    Obtiene todos los canales de TV (activos e inactivos)
 */
router.get('/channels', (req, res) => {
  try {
    const channels = channelService.getAllForAdmin();
    const categories = channelService.getCategories();
    return res.json({
      success: true,
      channels,
      categories
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/channels
 * @desc    Añade un nuevo canal de TV en vivo
 */
router.post('/channels', (req, res) => {
  try {
    const { name, category, logoUrl, streamUrl, quality, isActive } = req.body;
    if (!name || !streamUrl) {
      return res.status(400).json({ success: false, error: 'Nombre y URL de stream requeridos.' });
    }
    const channel = channelService.addChannel({
      name,
      category,
      logoUrl,
      streamUrl,
      quality,
      isActive: isActive !== false
    });
    return res.json({ success: true, channel, message: 'Canal añadido con éxito.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   PUT /api/admin/channels/:id
 * @desc    Actualiza los datos de un canal de TV
 */
router.put('/channels/:id', (req, res) => {
  try {
    const updated = channelService.updateChannel(req.params.id, req.body);
    if (!updated) {
      return res.status(404).json({ success: false, error: 'Canal no encontrado.' });
    }
    return res.json({ success: true, channel: updated, message: 'Canal actualizado.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/channels/:id/toggle
 * @desc    Activa o desactiva un canal
 */
router.post('/channels/:id/toggle', (req, res) => {
  try {
    const updated = channelService.toggleChannel(req.params.id);
    if (!updated) {
      return res.status(404).json({ success: false, error: 'Canal no encontrado.' });
    }
    return res.json({ success: true, channel: updated });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   DELETE /api/admin/channels/:id
 * @desc    Elimina un canal de TV
 */
router.delete('/channels/:id', (req, res) => {
  try {
    const deleted = channelService.deleteChannel(req.params.id);
    if (!deleted) {
      return res.status(404).json({ success: false, error: 'Canal no encontrado.' });
    }
    return res.json({ success: true, message: 'Canal eliminado correctamente.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/channels/sync-iptv
 * @desc    Sincroniza y descarga canales en vivo de iptv-org automáticamente
 */
router.post('/channels/sync-iptv', async (req, res) => {
  try {
    const result = await channelService.syncFromIptvOrg();
    return res.json({
      success: true,
      message: 'Sincronización con iptv-org completada con éxito.',
      result
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
