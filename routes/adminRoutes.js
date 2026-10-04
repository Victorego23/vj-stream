const express = require('express');
const router = express.Router();
const accountService = require('../services/accountService');
const channelService = require('../services/channelService');
const { loginRateLimiter } = require('../middlewares/rateLimitMiddleware');

// Middleware para verificar token o contraseña del Administrador
function adminAuth(req, res, next) {
  const token = req.headers['x-admin-password'] || req.headers['authorization'] || req.query.key;
  if (!token) {
    return res.status(401).json({ success: false, error: 'Se requiere token o credenciales de administrador.' });
  }

  const cleanPass = token.startsWith('Bearer ') ? token.slice(7) : token;
  if (!accountService.verifyAdminToken(cleanPass)) {
    return res.status(403).json({ success: false, error: 'Sesión o credenciales de administrador inválidas.' });
  }

  next();
}

/**
 * @route   POST /api/admin/login
 * @desc    Valida credenciales de acceso al Panel Web y emite token firmado de sesión
 */
router.post('/login', loginRateLimiter, (req, res) => {
  const { password } = req.body;
  if (!password || !accountService.verifyAdminPassword(password)) {
    return res.status(401).json({ success: false, error: 'Contraseña de administrador incorrecta.' });
  }

  const sessionToken = accountService.generateAdminToken();

  return res.json({
    success: true,
    token: sessionToken,
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

  const resellers = accountService.getResellers();
  const totalResellers = resellers.length;
  const totalCredits = resellers.reduce((acc, r) => acc + (r.credits || 0), 0);
  const resellerClientsCount = clients.filter(c => c.resellerId).length;

  return res.json({
    success: true,
    stats: {
      totalClients,
      activeClients,
      expiringSoon,
      expiredClients,
      pendingCount: pending.length,
      totalResellers,
      totalCredits,
      resellerClientsCount
    },
    clients,
    pending,
    resellers,
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

  const isTwoHourDemo = planDays === '2h' || planDays === 'demo_2h' || planDays === 0 || planDays === '0';
  const result = accountService.activateCode(code.trim().toUpperCase(), {
    name,
    planDays: isTwoHourDemo ? '2h' : (parseInt(planDays, 10) || 30),
    maxDevices: parseInt(maxDevices, 10) || 1,
    isDemo: isTwoHourDemo
  });

  if (!result.success) {
    return res.status(404).json(result);
  }

  return res.json(result);
});

/**
 * @route   POST /api/admin/create-demo
 * @desc    Genera instantáneamente un Demo Gratuito de 2 Horas
 */
router.post('/create-demo', (req, res) => {
  const { name = 'Cliente Demo (2 Horas)' } = req.body;
  const client = accountService.createDemoClient({ name });
  return res.json({
    success: true,
    client,
    message: 'Demo de 2 Horas generado con éxito.'
  });
});

/**
 * @route   POST /api/admin/clients
 * @route   POST /api/admin/create-client
 * @desc    Crea un cliente manual sin código previo
 */
const handleCreateClient = (req, res) => {
  const { name, planDays = 30, maxDevices = 1, isDemo = false } = req.body;

  if (!name || name.trim().length === 0) {
    return res.status(400).json({ success: false, error: 'El nombre es obligatorio.' });
  }

  const isTwoHourDemo = isDemo || planDays === '2h' || planDays === 'demo_2h';
  const client = accountService.createClient({
    name,
    planDays: isTwoHourDemo ? '2h' : (parseInt(planDays, 10) || 30),
    maxDevices: parseInt(maxDevices, 10) || 1,
    isDemo: isTwoHourDemo
  });

  return res.json({ success: true, client });
};

router.post('/clients', handleCreateClient);
router.post('/create-client', handleCreateClient);

/**
 * @route   POST /api/admin/clients/:id/renew
 * @route   POST /api/admin/renew
 * @desc    Renueva la membresía sumando días (ej: +30 días tras pago)
 */
const handleRenew = (req, res) => {
  const clientId = req.params.id || req.body.clientId;
  const days = req.body.additionalDays || req.body.days || 30;

  const client = accountService.renewClient(clientId, parseInt(days, 10));
  if (!client) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, client, message: `Membresía renovada por ${days} días con éxito.` });
};

router.post('/clients/:id/renew', handleRenew);
router.post('/renew', handleRenew);

/**
 * @route   POST /api/admin/clients/:id/toggle-status
 * @route   POST /api/admin/toggle-status
 * @desc    Suspende o reactiva el acceso de un cliente
 */
const handleToggleStatus = (req, res) => {
  const clientId = req.params.id || req.body.clientId;

  const client = accountService.toggleClientStatus(clientId);
  if (!client) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, client });
};

router.post('/clients/:id/toggle-status', handleToggleStatus);
router.post('/toggle-status', handleToggleStatus);

/**
 * @route   POST /api/admin/clients/:id/reset-devices
 * @route   POST /api/admin/reset-devices
 * @desc    Limpia los dispositivos registrados del cliente para permitirle cambiar de TV
 */
const handleResetDevices = (req, res) => {
  const clientId = req.params.id || req.body.clientId;

  const client = accountService.resetClientDevices(clientId);
  if (!client) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado.' });
  }

  return res.json({ success: true, message: 'Dispositivos desvinculados correctamente.', client });
};

router.post('/clients/:id/reset-devices', handleResetDevices);
router.post('/reset-devices', handleResetDevices);

/**
 * @route   DELETE /api/admin/clients/:id
 * @route   POST /api/admin/clients/:id/delete
 * @route   POST /api/admin/delete-client
 * @desc    Elimina un cliente definitivamente y revoca sus dispositivos hasta nueva aprobación
 */
const handleDeleteClient = (req, res) => {
  const clientId = req.params.id || req.body.clientId || req.body.id;
  if (!clientId) {
    return res.status(400).json({ success: false, error: 'ID o código de cliente requerido.' });
  }

  const deleted = accountService.deleteClient(clientId);
  if (!deleted) {
    return res.status(404).json({ success: false, error: 'Cliente no encontrado o ya eliminado.' });
  }

  return res.json({ 
    success: true, 
    message: 'Cliente eliminado definitivamente. Sus dispositivos han sido revocados hasta que lo apruebes otra vez.' 
  });
};

router.delete('/clients/:id', handleDeleteClient);
router.post('/clients/:id/delete', handleDeleteClient);
router.post('/delete-client', handleDeleteClient);

/**
 * @route   DELETE /api/admin/pending/:code
 * @route   POST /api/admin/reject-pending
 * @desc    Descarta / rechaza una pantalla pendiente de activación
 */
const handleRejectPending = (req, res) => {
  const code = req.params.code || req.body.code;
  if (!code) {
    return res.status(400).json({ success: false, error: 'Código requerido.' });
  }

  const deleted = accountService.deletePendingActivation(code);
  return res.json({ success: true, deleted, message: 'Pantalla pendiente descartada correctamente.' });
};

router.delete('/pending/:code', handleRejectPending);
router.post('/reject-pending', handleRejectPending);

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
 * @route   GET /api/admin/backup
 * @desc    Descarga la copia de seguridad completa de clientes y configuraciones
 */
router.get('/backup', (req, res) => {
  const backup = accountService.exportBackup();
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', `attachment; filename="vj_stream_backup_${new Date().toISOString().slice(0, 10)}.json"`);
  return res.json(backup);
});

/**
 * @route   POST /api/admin/restore
 * @desc    Restaura la copia de seguridad de clientes
 */
router.post('/restore', (req, res) => {
  const backupData = req.body;
  const result = accountService.importBackup(backupData);
  if (!result.success) {
    return res.status(400).json(result);
  }
  return res.json(result);
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

/**
 * ====================================================================
 * GESTIÓN DE REVENDEDORES Y CRÉDITOS (MASTER ADMIN)
 * ====================================================================
 */

/**
 * @route   GET /api/admin/resellers
 * @desc    Lista todos los revendedores registrados
 */
router.get('/resellers', (req, res) => {
  try {
    const resellers = accountService.getResellers();
    return res.json({
      success: true,
      resellers
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/resellers
 * @desc    Crea un nuevo revendedor con asignación inicial de créditos
 */
router.post('/resellers', (req, res) => {
  try {
    const { name, username, password, whatsapp, initialCredits } = req.body;
    const newReseller = accountService.createReseller({
      name,
      username,
      password,
      whatsapp,
      initialCredits
    });

    return res.status(201).json({
      success: true,
      reseller: newReseller,
      message: 'Revendedor creado exitosamente.'
    });
  } catch (err) {
    return res.status(400).json({ success: false, error: err.message });
  }
});

/**
 * @route   GET /api/admin/resellers/:id
 * @desc    Obtiene detalles de un revendedor, historial y lista de clientes
 */
router.get('/resellers/:id', (req, res) => {
  try {
    const reseller = accountService.getResellerById(req.params.id);
    if (!reseller) {
      return res.status(404).json({ success: false, error: 'Revendedor no encontrado.' });
    }
    const clients = accountService.getResellerClients(req.params.id);
    return res.json({
      success: true,
      reseller,
      clients
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   PUT /api/admin/resellers/:id
 * @desc    Actualiza datos del revendedor (estado, whatsapp, contraseña, etc.)
 */
router.put('/resellers/:id', (req, res) => {
  try {
    const updated = accountService.updateReseller(req.params.id, req.body);
    return res.json({
      success: true,
      reseller: updated,
      message: 'Datos del revendedor actualizados.'
    });
  } catch (err) {
    return res.status(400).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/resellers/:id/recharge
 * @desc    Recarga créditos al revendedor tras confirmar el pago
 */
router.post('/resellers/:id/recharge', (req, res) => {
  try {
    const { credits, note } = req.body;
    const result = accountService.rechargeResellerCredits(req.params.id, credits, note);
    return res.json({
      success: true,
      reseller: result,
      message: `Se han añadido ${credits} créditos con éxito al revendedor.`
    });
  } catch (err) {
    return res.status(400).json({ success: false, error: err.message });
  }
});

/**
 * @route   DELETE /api/admin/resellers/:id
 * @desc    Elimina un revendedor del sistema
 */
router.delete('/resellers/:id', (req, res) => {
  try {
    const deleted = accountService.deleteReseller(req.params.id);
    if (!deleted) {
      return res.status(404).json({ success: false, error: 'Revendedor no encontrado.' });
    }
    return res.json({
      success: true,
      message: 'Revendedor eliminado con éxito.'
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});
/**
 * ====================================================================
 * AVISOS Y NOTIFICACIONES A LAS PANTALLAS (SUPER ADMIN)
 * ====================================================================
 */

/**
 * @route   GET /api/admin/announcement
 * @desc    Obtiene el estado del aviso o notificación en pantalla
 */
router.get('/announcement', (req, res) => {
  try {
    const announcement = accountService.getAnnouncement();
    return res.json({
      success: true,
      announcement
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/announcement
 * @desc    Crea, actualiza o desactiva un aviso en pantalla para TVs y móviles
 */
router.post('/announcement', (req, res) => {
  try {
    const { title, message, type, active, expiresHours } = req.body;
    const updated = accountService.updateAnnouncement({
      title,
      message,
      type,
      active,
      expiresHours
    });
    return res.json({
      success: true,
      announcement: updated,
      message: active ? 'Aviso transmitido a todas las pantallas con éxito.' : 'Aviso desactivado.'
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * ====================================================================
 * MONITOR DE PANTALLAS CONECTADAS Y EXPULSIÓN REMOTA
 * ====================================================================
 */

/**
 * @route   GET /api/admin/sessions
 * @desc    Lista todas las pantallas y dispositivos conectados en tiempo real
 */
router.get('/sessions', (req, res) => {
  try {
    const sessions = accountService.getAllConnectedSessions();
    const onlineCount = sessions.filter(s => s.isOnline).length;
    return res.json({
      success: true,
      totalSessions: sessions.length,
      onlineCount,
      sessions
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * @route   POST /api/admin/sessions/disconnect
 * @desc    Desconecta y expulsa remotamente un dispositivo de la app
 */
router.post('/sessions/disconnect', (req, res) => {
  try {
    const { clientId, deviceId } = req.body;
    if (!deviceId) {
      return res.status(400).json({ success: false, error: 'deviceId es requerido.' });
    }
    const result = accountService.disconnectDevice(clientId, deviceId);
    return res.json(result);
  } catch (err) {
    return res.status(400).json({ success: false, error: err.message });
  }
});

/**
 * ====================================================================
 * TABLERO FINANCIERO Y REPORTES DE INGRESOS
 * ====================================================================
 */

/**
 * @route   GET /api/admin/server-health
 * @desc    Monitoreo en tiempo real del servidor, memoria, uptime, APK oficial y CDN
 */
router.get('/server-health', (req, res) => {
  const path = require('path');
  const fs = require('fs');

  const mem = process.memoryUsage();
  const uptimeSec = Math.floor(process.uptime());
  const hours = Math.floor(uptimeSec / 3600);
  const minutes = Math.floor((uptimeSec % 3600) / 60);
  const seconds = uptimeSec % 60;
  const uptimeFormatted = `${hours}h ${minutes}m ${seconds}s`;

  const apkPath = path.resolve(__dirname, '..', 'TOM-TV-release.apk');
  let apkSizeMb = '58.28 MB';
  let apkExists = false;
  if (fs.existsSync(apkPath)) {
    apkExists = true;
    apkSizeMb = (fs.statSync(apkPath).size / (1024 * 1024)).toFixed(2) + ' MB';
  }

  const sessions = accountService.getAllConnectedSessions();
  const clients = accountService.getClients();

  return res.json({
    success: true,
    server: {
      status: 'ONLINE',
      uptimeSeconds: uptimeSec,
      uptimeFormatted,
      nodeVersion: process.version,
      platform: process.platform,
      memory: {
        rss: (mem.rss / (1024 * 1024)).toFixed(1) + ' MB',
        heapUsed: (mem.heapUsed / (1024 * 1024)).toFixed(1) + ' MB',
        heapTotal: (mem.heapTotal / (1024 * 1024)).toFixed(1) + ' MB'
      },
      apk: {
        version: '3.5.0',
        exists: apkExists,
        size: apkSizeMb,
        endpoint: '/apk'
      },
      services: {
        realDebrid: Boolean(process.env.REALDEBRID_API_KEY),
        tmdb: Boolean(process.env.TMDB_API_KEY)
      },
      stats: {
        activeClients: clients.filter(c => c.status === 'active').length,
        onlineSessions: sessions.filter(s => s.isOnline).length,
        totalSessions: sessions.length
      }
    }
  });
});

/**
 * @route   POST /api/admin/quick-activate
 * @desc    Aprobación express de pantallas pendientes con un solo clic y generación de WhatsApp
 */
router.post('/quick-activate', (req, res) => {
  const { code, plan = '30d', name, maxDevices = 1 } = req.body;
  if (!code) {
    return res.status(400).json({ success: false, error: 'Código de activación requerido.' });
  }

  const cleanCode = code.trim().toUpperCase();
  const pending = accountService.getPendingActivations().find(p => p.code === cleanCode);
  const clientName = (name && name.trim()) 
    ? name.trim() 
    : (pending ? `TV ${pending.deviceModel || cleanCode}` : `Cliente ${cleanCode}`);

  let planDays = 30;
  let isDemo = false;
  if (plan === '2h' || plan === 'demo') {
    planDays = '2h';
    isDemo = true;
  } else if (plan === '90d' || plan === '3m') {
    planDays = 90;
  } else if (plan === '365d' || plan === '1y') {
    planDays = 365;
  } else {
    planDays = parseInt(plan, 10) || 30;
  }

  const result = accountService.activateCode(cleanCode, {
    name: clientName,
    planDays,
    maxDevices: parseInt(maxDevices, 10) || 1,
    isDemo
  });

  if (!result.success) {
    return res.status(404).json(result);
  }

  const expFormatted = isDemo
    ? '2 Horas de acceso libre'
    : `${planDays} Días (hasta el ${new Date(result.client.expiresAt).toLocaleDateString('es-ES')})`;

  const whatsappMsg = `🎬 *¡BIENVENIDO A TOM TV OFICIAL!*\n\n` +
    `✅ Tu pantalla ha sido activada con éxito.\n` +
    `👤 *Cliente:* ${result.client.name}\n` +
    `🔑 *Código TV:* ${result.client.code}\n` +
    `⏳ *Vigencia:* ${expFormatted}\n` +
    `📺 *Dispositivos:* ${result.client.deviceCount || 1} de ${result.client.maxDevices || 1} permitidos\n\n` +
    `📲 *Para ver en Celular o PC:* https://tomtv.lat/play\n` +
    `📺 *Para Smart TV o Firestick (en Downloader):* tomtv.lat/apk\n\n` +
    `¡Que disfrutes del mejor cine, series y TV en vivo sin cortes! ⭐`;

  return res.json({
    success: true,
    client: result.client,
    whatsappMsg,
    whatsappUrl: `https://wa.me/?text=${encodeURIComponent(whatsappMsg)}`,
    message: `Pantalla ${cleanCode} activada con éxito (${isDemo ? 'Demo 2 Horas' : planDays + ' días'}).`
  });
});

/**
 * @route   GET /api/admin/financial-stats
 * @desc    Calcula métricas financieras, proyecciones de ingresos y renovaciones
 */
router.get('/financial-stats', (req, res) => {
  try {
    const price = parseFloat(req.query.price) || 10;
    const stats = accountService.getFinancialStats(price);
    return res.json({
      success: true,
      stats
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
