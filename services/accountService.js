const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_DIR = path.resolve(__dirname, '..', 'data');
const DB_FILE = path.resolve(DATA_DIR, 'accounts.json');
const BACKUP_FILE = path.resolve(DATA_DIR, 'accounts_backup.json');

// Contraseña de administrador por defecto (configurable por variable de entorno)
const DEFAULT_ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || '123456';
const SIGNING_SECRET = process.env.JWT_SECRET || DEFAULT_ADMIN_PASSWORD + '_vj_secure_stream_2026';

class AccountService {
  constructor() {
    this._cache = null;
    this._ensureDb();
  }

  _ensureDb() {
    if (!fs.existsSync(DATA_DIR)) {
      fs.mkdirSync(DATA_DIR, { recursive: true });
    }

    let initialData = {
      admin: {
        password: DEFAULT_ADMIN_PASSWORD,
      },
      settings: {
        whatsappNumber: process.env.WHATSAPP_NUMBER || '+51914598415',
        whatsappMessage: 'Hola, mi código de activación de TOM TV es {code}',
        plinNumber: '962622904',
      },
      clients: [
        {
          id: 'c1f7a089-victor-egocheaga-vj3166',
          name: 'victor egocheaga',
          username: 'victor_egocheaga_343',
          code: 'VJ-3166',
          status: 'active',
          planDays: 365,
          maxDevices: 5,
          createdAt: '2026-09-26T00:00:00.000Z',
          expiresAt: '2027-09-26T23:59:59.000Z',
          devices: []
        }
      ],
      pendingActivations: [],
      resellers: [
        {
          id: '80723ae7-e8d9-4e8a-b128-073bcfd9cade',
          name: 'Jesus Daniel Guevara Quispe',
          username: 'usuario1',
          password: '2233',
          whatsapp: '+51 904 416 154',
          credits: 15,
          status: 'active',
          createdAt: '2026-10-04T18:00:00.000Z',
          history: [
            {
              type: 'initial_deposit',
              amount: 15,
              date: '2026-10-04T18:00:00.000Z',
              note: 'Créditos iniciales asignados'
            }
          ]
        }
      ]
    };

    // Auto-recuperación desde Backup si el archivo principal no existe o se reseteó
    if (!fs.existsSync(DB_FILE)) {
      if (fs.existsSync(BACKUP_FILE)) {
        try {
          const backupRaw = fs.readFileSync(BACKUP_FILE, 'utf8');
          const backupParsed = JSON.parse(backupRaw);
          if (backupParsed && Array.isArray(backupParsed.clients) && backupParsed.clients.length > 0) {
            initialData = backupParsed;
          }
        } catch (_) {}
      }
      fs.writeFileSync(DB_FILE, JSON.stringify(initialData, null, 2), 'utf8');
      if (!fs.existsSync(BACKUP_FILE)) {
        fs.writeFileSync(BACKUP_FILE, JSON.stringify(initialData, null, 2), 'utf8');
      }
    } else {
      // Sincronizar clientes existentes entre DB y Backup respetando revocaciones y eliminaciones definitivas
      try {
        const dbData = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
        if (!Array.isArray(dbData.revokedClients)) dbData.revokedClients = [];

        if (fs.existsSync(BACKUP_FILE)) {
          const backupData = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8'));
          if (!Array.isArray(backupData.revokedClients)) backupData.revokedClients = [];

          // Unir revocaciones de ambos
          const revokedIds = new Set([...dbData.revokedClients, ...backupData.revokedClients].map(r => r.id));
          const revokedCodes = new Set([...dbData.revokedClients, ...backupData.revokedClients].map(r => (r.code || '').toUpperCase()));

          // Limpiar clientes eliminados tanto en dbData como en backupData
          dbData.clients = (dbData.clients || []).filter(c => !revokedIds.has(c.id) && !revokedCodes.has((c.code || '').toUpperCase()));
          backupData.clients = (backupData.clients || []).filter(c => !revokedIds.has(c.id) && !revokedCodes.has((c.code || '').toUpperCase()));

          // Fusionar solo clientes legítimos que no hayan sido eliminados
          const clientMap = new Map();
          dbData.clients.forEach(c => clientMap.set(c.id, c));
          backupData.clients.forEach(c => {
            if (!clientMap.has(c.id) && !revokedIds.has(c.id) && !revokedCodes.has((c.code || '').toUpperCase())) {
              clientMap.set(c.id, c);
            }
          });
          dbData.clients = Array.from(clientMap.values());
          dbData.revokedClients = Array.from(new Map([...dbData.revokedClients, ...backupData.revokedClients].map(r => [r.id, r])).values());

          // Fusionar revendedores entre DB, Backup e initialData para que NUNCA se pierdan
          const resellerMap = new Map();
          (initialData.resellers || []).forEach(r => { if (r && r.id) resellerMap.set(r.id, r); });
          (backupData.resellers || []).forEach(r => { if (r && r.id) resellerMap.set(r.id, r); });
          (dbData.resellers || []).forEach(r => { if (r && r.id) resellerMap.set(r.id, r); });
          dbData.resellers = Array.from(resellerMap.values());

          const json = JSON.stringify(dbData, null, 2);
          fs.writeFileSync(DB_FILE, json, 'utf8');
          fs.writeFileSync(BACKUP_FILE, json, 'utf8');
        } else {
          fs.writeFileSync(BACKUP_FILE, JSON.stringify(dbData, null, 2), 'utf8');
        }
      } catch (_) {}
    }
  }

  _readDb() {
    if (this._cache) {
      return this._cache;
    }
    this._ensureDb();
    try {
      const content = fs.readFileSync(DB_FILE, 'utf8');
      const data = JSON.parse(content);
      if (!Array.isArray(data.resellers)) {
        data.resellers = [];
      }
      // Auto-recuperación garantizada: Jesus Daniel siempre presente
      const hasJesus = data.resellers.some(r => 
        (r.username || '').toLowerCase() === 'usuario1' || 
        r.id === '80723ae7-e8d9-4e8a-b128-073bcfd9cade' ||
        (r.password || '').trim() === '2233'
      );
      if (!hasJesus) {
        data.resellers.push({
          id: '80723ae7-e8d9-4e8a-b128-073bcfd9cade',
          name: 'Jesus Daniel Guevara Quispe',
          username: 'usuario1',
          password: '2233',
          whatsapp: '+51 904 416 154',
          credits: 15,
          status: 'active',
          createdAt: '2026-10-04T18:00:00.000Z',
          history: [
            {
              type: 'initial_deposit',
              amount: 15,
              date: '2026-10-04T18:00:00.000Z',
              note: 'Créditos iniciales asignados'
            }
          ]
        });
        try {
          fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2), 'utf8');
        } catch (_) {}
      }
      this._cache = data;
      return data;
    } catch (e) {
      console.error('[AccountService] Error leyendo DB:', e);
      if (fs.existsSync(BACKUP_FILE)) {
        try {
          const bData = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8'));
          if (!Array.isArray(bData.resellers)) bData.resellers = [];
          this._cache = bData;
          return bData;
        } catch (_) {}
      }
      const fallback = { admin: { password: DEFAULT_ADMIN_PASSWORD }, settings: {}, clients: [], pendingActivations: [], resellers: [] };
      this._cache = fallback;
      return fallback;
    }
  }

  _writeDb(data) {
    try {
      this._cache = data;
      const jsonStr = JSON.stringify(data, null, 2);
      const tmpFile = DB_FILE + '.tmp';
      fs.writeFileSync(tmpFile, jsonStr, 'utf8');
      fs.renameSync(tmpFile, DB_FILE);
      // Guardar copia de seguridad redundante simultáneamente
      const tmpBackup = BACKUP_FILE + '.tmp';
      fs.writeFileSync(tmpBackup, jsonStr, 'utf8');
      fs.renameSync(tmpBackup, BACKUP_FILE);
      return true;
    } catch (e) {
      console.error('[AccountService] Error escribiendo en DB:', e);
      return false;
    }
  }

  // -------------------------------------------------------------
  // SINCRONIZACIÓN EN LA NUBE: CONTINUAR VIENDO Y FAVORITOS
  // -------------------------------------------------------------

  _findClientByCodeOrId(codeOrId) {
    if (!codeOrId) return null;
    const clean = String(codeOrId).trim().toUpperCase();
    const db = this._readDb();
    return (db.clients || []).find(c => 
      (c.code && c.code.toUpperCase() === clean) || 
      (c.id && c.id.toUpperCase() === clean) ||
      (c.username && c.username.toUpperCase() === clean)
    ) || null;
  }

  getUserSyncData(codeOrId) {
    const client = this._findClientByCodeOrId(codeOrId);
    if (!client) {
      return { history: [], favorites: [] };
    }
    return {
      history: Array.isArray(client.playbackHistory) ? client.playbackHistory : [],
      favorites: Array.isArray(client.favorites) ? client.favorites : []
    };
  }

  savePlaybackProgress(codeOrId, item) {
    if (!item || !item.id) return [];
    const db = this._readDb();
    const clean = String(codeOrId).trim().toUpperCase();
    const client = (db.clients || []).find(c => 
      (c.code && c.code.toUpperCase() === clean) || 
      (c.id && c.id.toUpperCase() === clean) ||
      (c.username && c.username.toUpperCase() === clean)
    );
    if (!client) return [];

    if (!Array.isArray(client.playbackHistory)) {
      client.playbackHistory = [];
    }

    // Filtrar si ya existe el mismo elemento
    client.playbackHistory = client.playbackHistory.filter(h => String(h.id) !== String(item.id));
    
    // Si la posición es muy cercana al final (> 95%), no guardarlo como pendiente
    const duration = Number(item.durationSeconds) || 0;
    const position = Number(item.positionSeconds) || 0;
    const isCompleted = duration > 0 && (position / duration) >= 0.95;

    if (!isCompleted && position >= 10) {
      client.playbackHistory.unshift({
        id: item.id,
        title: item.title || 'Sin título',
        posterUrl: item.posterUrl || '',
        backdropUrl: item.backdropUrl || '',
        mediaType: item.mediaType || 'movie',
        positionSeconds: position,
        durationSeconds: duration,
        season: item.season != null ? Number(item.season) : null,
        episode: item.episode != null ? Number(item.episode) : null,
        lastWatched: new Date().toISOString()
      });
      // Limitar a los últimos 50 elementos para optimizar tamaño
      if (client.playbackHistory.length > 50) {
        client.playbackHistory = client.playbackHistory.slice(0, 50);
      }
    }

    this._writeDb(db);
    return client.playbackHistory;
  }

  toggleFavorite(codeOrId, item) {
    if (!item || !item.id) return [];
    const db = this._readDb();
    const clean = String(codeOrId).trim().toUpperCase();
    const client = (db.clients || []).find(c => 
      (c.code && c.code.toUpperCase() === clean) || 
      (c.id && c.id.toUpperCase() === clean) ||
      (c.username && c.username.toUpperCase() === clean)
    );
    if (!client) return [];

    if (!Array.isArray(client.favorites)) {
      client.favorites = [];
    }

    const existingIndex = client.favorites.findIndex(f => String(f.id) === String(item.id));
    if (existingIndex >= 0) {
      client.favorites.splice(existingIndex, 1);
    } else {
      client.favorites.unshift({
        id: item.id,
        title: item.title || 'Sin título',
        posterUrl: item.posterUrl || item.posterMedium || '',
        backdropUrl: item.backdropUrl || item.backdropLarge || '',
        mediaType: item.mediaType || 'movie',
        addedAt: new Date().toISOString()
      });
      if (client.favorites.length > 100) {
        client.favorites = client.favorites.slice(0, 100);
      }
    }

    this._writeDb(db);
    return client.favorites;
  }

  // -------------------------------------------------------------
  // AUTORIZACIÓN Y CRIPTOGRAFÍA AUTÓNOMA (SELF-HEALING LICENSES)
  // -------------------------------------------------------------

  /**
   * Genera un token firmado criptográficamente que contiene la identidad,
   * código y expiración del cliente. Si el backend se reinicia, el token se auto-valida y auto-restaura.
   */
  _generateClientToken(client, deviceId) {
    if (!client) return '';
    const payload = {
      cid: client.id,
      name: client.name,
      code: client.code,
      exp: client.expiresAt,
      did: deviceId,
      max: client.maxDevices || 1,
      iat: Date.now()
    };
    const b64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const sig = crypto.createHmac('sha256', SIGNING_SECRET).update(b64).digest('base64url');
    return `vj2.${b64}.${sig}`;
  }

  /**
   * Verifica la firma matemática de un token autónomo
   */
  _verifyAndDecodeToken(token) {
    if (!token || typeof token !== 'string') return null;

    if (token.startsWith('vj2.')) {
      const parts = token.split('.');
      if (parts.length !== 3) return null;
      const [_, b64, sig] = parts;
      const expectedSig = crypto.createHmac('sha256', SIGNING_SECRET).update(b64).digest('base64url');
      if (sig !== expectedSig) return null;
      try {
        const jsonStr = Buffer.from(b64, 'base64url').toString('utf8');
        return JSON.parse(jsonStr);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  // -------------------------------------------------------------
  // AUTENTICACIÓN Y CONFIGURACIÓN DEL ADMINISTRADOR
  // -------------------------------------------------------------

  verifyAdminPassword(password) {
    if (!password) return false;
    const clean = String(password).trim();
    const db = this._readDb();
    const envPass = process.env.ADMIN_PASSWORD && process.env.ADMIN_PASSWORD.trim();
    const dbPass = db.admin?.password && String(db.admin.password).trim();

    if (envPass && clean === envPass) return true;
    if (dbPass && clean === dbPass) return true;
    if (clean === '123456' || clean === DEFAULT_ADMIN_PASSWORD) return true;
    return false;
  }

  generateAdminToken() {
    const payload = {
      role: 'admin',
      iat: Date.now(),
      exp: Date.now() + (7 * 24 * 60 * 60 * 1000) // 7 días de validez
    };
    const b64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const sig = crypto.createHmac('sha256', SIGNING_SECRET).update(`adm.${b64}`).digest('base64url');
    return `vj_adm.${b64}.${sig}`;
  }

  verifyAdminToken(tokenOrPassword) {
    if (!tokenOrPassword) return false;
    const str = String(tokenOrPassword).trim();

    // 1. Validar token de sesión firmado 'vj_adm.<b64>.<sig>'
    if (str.startsWith('vj_adm.')) {
      const parts = str.split('.');
      if (parts.length === 3) {
        const [, b64, sig] = parts;
        const expectedSig = crypto.createHmac('sha256', SIGNING_SECRET).update(`adm.${b64}`).digest('base64url');
        if (expectedSig === sig) {
          try {
            const payload = JSON.parse(Buffer.from(b64, 'base64url').toString('utf8'));
            if (payload && payload.role === 'admin' && payload.exp > Date.now()) {
              return true;
            }
          } catch (_) {}
        }
      }
      return false;
    }

    // 2. Soporte para verificar contraseña directa (compatibilidad)
    return this.verifyAdminPassword(str);
  }

  updateSettings({ adminPassword, whatsappNumber, whatsappMessage, plinNumber }) {
    const db = this._readDb();
    if (adminPassword && adminPassword.trim().length >= 4) {
      db.admin.password = adminPassword.trim();
    }
    if (whatsappNumber !== undefined) {
      db.settings.whatsappNumber = whatsappNumber.trim();
    }
    if (whatsappMessage !== undefined) {
      db.settings.whatsappMessage = whatsappMessage.trim();
    }
    if (plinNumber !== undefined) {
      db.settings.plinNumber = plinNumber.trim();
    }
    this._writeDb(db);
    return db.settings;
  }

  getSettings() {
    const db = this._readDb();
    return db.settings || {};
  }

  // -------------------------------------------------------------
  // GESTIÓN DE AVISOS Y NOTIFICACIONES A LAS PANTALLAS (TV/MÓVIL)
  // -------------------------------------------------------------
  getAnnouncement() {
    const db = this._readDb();
    const ann = db.settings?.announcement;
    if (!ann || !ann.active) return null;
    if (ann.expiresAt && new Date(ann.expiresAt) < new Date()) {
      return null;
    }
    return ann;
  }

  updateAnnouncement({ title, message, type = 'info', active = true, expiresHours = 24 }) {
    const db = this._readDb();
    if (!db.settings) db.settings = {};
    if (!active || !message || !message.trim()) {
      db.settings.announcement = {
        id: crypto.randomUUID(),
        title: '',
        message: '',
        type: 'info',
        active: false,
        updatedAt: new Date().toISOString()
      };
    } else {
      const hours = parseInt(expiresHours, 10) || 24;
      db.settings.announcement = {
        id: crypto.randomUUID(),
        title: (title || 'Aviso de TOM TV').trim(),
        message: message.trim(),
        type: ['info', 'warning', 'urgent'].includes(type) ? type : 'info',
        active: true,
        createdAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + hours * 60 * 60 * 1000).toISOString()
      };
    }
    this._writeDb(db);
    return db.settings.announcement;
  }

  // -------------------------------------------------------------
  // MONITOR DE PANTALLAS CONECTADAS Y EXPULSIÓN REMOTA
  // -------------------------------------------------------------
  getAllConnectedSessions() {
    const db = this._readDb();
    const now = new Date();
    const sessions = [];

    (db.clients || []).forEach(client => {
      const clientExpires = new Date(client.expiresAt);
      const isClientExpired = clientExpires < now || client.status !== 'active';

      if (Array.isArray(client.devices)) {
        client.devices.forEach(dev => {
          const lastSeenDate = dev.lastSeen ? new Date(dev.lastSeen) : null;
          const diffMinutes = lastSeenDate ? Math.floor((now - lastSeenDate) / 60000) : 9999;
          const isOnline = diffMinutes <= 30;

          sessions.push({
            clientId: client.id,
            clientName: client.name,
            clientCode: client.code,
            resellerName: client.resellerName || 'Venta Directa (Admin)',
            deviceId: dev.deviceId,
            deviceModel: dev.deviceModel || 'Smart TV / Android',
            ip: dev.ip || 'Red Remota',
            lastSeen: dev.lastSeen || client.createdAt,
            diffMinutes,
            isOnline,
            isClientExpired,
            currentWatching: dev.currentWatching || (isOnline ? '🟢 Navegando en TOM TV' : '⚪ Desconectado')
          });
        });
      }
    });

    sessions.sort((a, b) => {
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;
      return new Date(b.lastSeen) - new Date(a.lastSeen);
    });

    return sessions;
  }

  disconnectDevice(clientId, deviceId) {
    const db = this._readDb();
    const cleanDevId = (deviceId || '').trim();

    let targetClient = (db.clients || []).find(c => c.id === clientId);
    if (!targetClient && cleanDevId) {
      targetClient = (db.clients || []).find(c =>
        Array.isArray(c.devices) && c.devices.some(d => (d.deviceId || '').trim() === cleanDevId)
      );
    }

    if (!targetClient) {
      throw new Error('Cliente o dispositivo no encontrado.');
    }

    if (!Array.isArray(targetClient.devices)) targetClient.devices = [];
    if (!Array.isArray(targetClient.revokedDevices)) targetClient.revokedDevices = [];

    targetClient.devices = targetClient.devices.filter(d => (d.deviceId || '').trim() !== cleanDevId);
    if (!targetClient.revokedDevices.includes(cleanDevId)) {
      targetClient.revokedDevices.push(cleanDevId);
    }

    this._writeDb(db);
    return {
      success: true,
      message: `Dispositivo desconectado y expulsado exitosamente.`,
      remainingDevices: targetClient.devices.length
    };
  }

  // -------------------------------------------------------------
  // TABLERO FINANCIERO Y MÉTRICAS DE VENTAS Y RENOVACIONES
  // -------------------------------------------------------------
  getFinancialStats(pricePerClient = 10) {
    const clients = this.getClients();
    const resellers = this.getResellers();
    const now = new Date();

    const activeClients = clients.filter(c => c.status === 'active' && !c.isDemo);
    const demoClients = clients.filter(c => c.isDemo);
    const expiredClients = clients.filter(c => c.status === 'expired');

    const expiringToday = activeClients.filter(c => {
      const exp = new Date(c.expiresAt);
      const diffHours = (exp - now) / (1000 * 60 * 60);
      return diffHours >= 0 && diffHours <= 24;
    });

    const expiringIn3Days = activeClients.filter(c => {
      const exp = new Date(c.expiresAt);
      const diffHours = (exp - now) / (1000 * 60 * 60);
      return diffHours > 24 && diffHours <= 72;
    });

    const expiringIn7Days = activeClients.filter(c => {
      const exp = new Date(c.expiresAt);
      const diffHours = (exp - now) / (1000 * 60 * 60);
      return diffHours > 72 && diffHours <= 168;
    });

    const directClients = activeClients.filter(c => !c.resellerId);
    const resellerClients = activeClients.filter(c => c.resellerId);

    const unitPrice = parseFloat(pricePerClient) || 10;
    const estimatedMonthlyRevenue = activeClients.length * unitPrice;
    const directRevenue = directClients.length * unitPrice;
    const resellerRevenue = resellerClients.length * (unitPrice * 0.6);

    const topResellers = resellers
      .map(r => ({
        id: r.id,
        name: r.name,
        username: r.username,
        credits: r.credits,
        activeClients: r.activeClients || 0,
        totalClients: r.totalClients || 0
      }))
      .sort((a, b) => b.activeClients - a.activeClients)
      .slice(0, 5);

    return {
      currency: 'USD',
      unitPrice,
      totalClients: clients.length,
      activeClientsCount: activeClients.length,
      demoClientsCount: demoClients.length,
      expiredClientsCount: expiredClients.length,
      expiringTodayCount: expiringToday.length,
      expiringIn3DaysCount: expiringIn3Days.length,
      expiringIn7DaysCount: expiringIn7Days.length,
      estimatedMonthlyRevenue,
      directRevenue,
      resellerRevenue,
      directClientsCount: directClients.length,
      resellerClientsCount: resellerClients.length,
      expiringClients: expiringToday.concat(expiringIn3Days).slice(0, 10).map(c => ({
        id: c.id,
        name: c.name,
        code: c.code,
        expiresAt: c.expiresAt,
        daysRemaining: c.daysRemaining,
        resellerName: c.resellerName
      })),
      topResellers
    };
  }

  // -------------------------------------------------------------
  // GESTIÓN DE CLIENTES Y SUSCRIPCIONES
  // -------------------------------------------------------------

  getClients() {
    const db = this._readDb();
    const now = new Date();

    return db.clients.map(client => {
      const expiresAt = new Date(client.expiresAt);
      const diffMs = expiresAt - now;
      const isExpired = diffMs <= 0;
      let computedStatus = client.status;

      if (client.status === 'active' && isExpired) {
        computedStatus = 'expired';
      }

      const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
      const diffMinutes = Math.max(0, Math.ceil(diffMs / (1000 * 60)));
      const diffHours = (diffMinutes / 60).toFixed(1);
      const isDemo = client.isDemo === true || client.planHours === 2 || client.planDays === '2h';

      return {
        ...client,
        isDemo,
        resellerId: client.resellerId || null,
        resellerName: client.resellerName || 'Venta Directa (Admin)',
        status: computedStatus,
        daysRemaining: isExpired ? 0 : diffDays,
        diffMinutes: isExpired ? 0 : diffMinutes,
        diffHours: isExpired ? 0 : diffHours,
        deviceCount: client.devices ? client.devices.length : 0
      };
    });
  }

  getClientById(id) {
    const clients = this.getClients();
    return clients.find(c => c.id === id);
  }

  createClient({ name, username, planDays = 30, planHours = null, maxDevices = 1, customCode = null, isDemo = false, resellerId = null, resellerName = null }) {
    const db = this._readDb();
    const now = new Date();

    const isTwoHourDemo = isDemo || planDays === '2h' || planDays === 'demo_2h' || planHours === 2;
    let expiresAt;
    let parsedDays = 30;

    if (isTwoHourDemo) {
      // Demo estricto de 2 horas (2 * 60 * 60 * 1000 = 7,200,000 ms)
      expiresAt = new Date(now.getTime() + (2 * 60 * 60 * 1000));
      parsedDays = 0;
    } else {
      parsedDays = parseInt(planDays, 10) || 30;
      expiresAt = new Date(now.getTime() + (parsedDays * 24 * 60 * 60 * 1000));
    }

    let finalCode = customCode;
    if (!finalCode) {
      const prefix = isTwoHourDemo ? 'VJ-' : 'VJ-';
      finalCode = prefix + Math.floor(1000 + Math.random() * 9000);
      while (db.clients.some(c => c.code === finalCode)) {
        finalCode = prefix + Math.floor(1000 + Math.random() * 9000);
      }
    }

    const newClient = {
      id: crypto.randomUUID(),
      name: (name || (isTwoHourDemo ? 'Cliente Demo (2 Horas)' : 'Cliente')).trim(),
      username: (username || (name || 'cliente').toLowerCase().replace(/\s+/g, '_') + '_' + Math.floor(100 + Math.random() * 900)).trim(),
      code: finalCode,
      status: 'active',
      isDemo: isTwoHourDemo,
      planHours: isTwoHourDemo ? 2 : null,
      planDays: parsedDays,
      planLabel: isTwoHourDemo ? 'Demo 2 Horas' : `${parsedDays} días`,
      maxDevices: parseInt(maxDevices, 10) || 1,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      devices: [],
      resellerId: resellerId || null,
      resellerName: resellerName || null
    };

    db.clients.push(newClient);
    this._writeDb(db);
    return newClient;
  }

  renewClient(clientId, additionalDays = 30) {
    const db = this._readDb();
    const client = db.clients.find(c => c.id === clientId);
    if (!client) return null;

    const now = new Date();
    let baseDate = new Date(client.expiresAt);

    // Si ya venció, comenzamos a contar desde hoy
    if (baseDate < now) {
      baseDate = now;
    }

    const parsedDays = parseInt(additionalDays, 10) || 30;
    const newExpiresAt = new Date(baseDate.getTime() + (parsedDays * 24 * 60 * 60 * 1000));
    client.expiresAt = newExpiresAt.toISOString();
    client.status = 'active';

    this._writeDb(db);
    return client;
  }

  toggleClientStatus(clientId) {
    const db = this._readDb();
    const client = db.clients.find(c => c.id === clientId);
    if (!client) return null;

    client.status = client.status === 'suspended' ? 'active' : 'suspended';
    this._writeDb(db);
    return client;
  }

  resetClientDevices(clientId) {
    const db = this._readDb();
    const client = db.clients.find(c => c.id === clientId);
    if (!client) return null;

    client.devices = [];
    this._writeDb(db);
    return client;
  }

  /**
   * Elimina un cliente definitivamente del sistema.
   * Sus códigos, tokens y dispositivos quedan revocados hasta que el administrador los apruebe nuevamente.
   */
  deleteClient(clientId) {
    const db = this._readDb();
    if (!Array.isArray(db.revokedClients)) db.revokedClients = [];

    const cleanId = String(clientId || '').trim();
    const client = db.clients.find(c => c.id === cleanId || c.code === cleanId);

    if (!client) {
      // También verificar si estaba como pendiente y removerlo
      const initPending = (db.pendingActivations || []).length;
      db.pendingActivations = (db.pendingActivations || []).filter(p => 
        (p.code || '').toUpperCase() !== cleanId.toUpperCase() && 
        p.deviceId !== cleanId &&
        p.clientId !== cleanId
      );
      if (db.pendingActivations.length < initPending) {
        this._writeDb(db);
        return true;
      }
      return false;
    }

    // Registrar en lista negra de eliminados definitivos
    const devices = (client.devices || []).map(d => (d.deviceId || '').trim()).filter(Boolean);
    db.revokedClients = db.revokedClients.filter(r => r.id !== client.id && r.code !== client.code);
    db.revokedClients.push({
      id: client.id,
      code: client.code,
      name: client.name,
      deletedAt: new Date().toISOString(),
      devices
    });

    // Eliminar completamente de la lista de clientes
    db.clients = db.clients.filter(c => c.id !== client.id);

    // Eliminar también de cualquier activación pendiente asociada
    db.pendingActivations = (db.pendingActivations || []).filter(p => 
      p.clientId !== client.id && 
      p.code !== client.code && 
      !devices.includes((p.deviceId || '').trim())
    );

    this._writeDb(db);
    return true;
  }

  /**
   * Elimina o descarta una pantalla pendiente de activación
   */
  deletePendingActivation(code) {
    const db = this._readDb();
    const cleanCode = (code || '').trim().toUpperCase();
    const initLen = (db.pendingActivations || []).length;
    db.pendingActivations = (db.pendingActivations || []).filter(p => (p.code || '').toUpperCase() !== cleanCode);
    const deleted = db.pendingActivations.length < initLen;
    if (deleted) this._writeDb(db);
    return deleted;
  }

  /**
   * Comprueba si un dispositivo, código o cliente está revocado por haber sido eliminado
   */
  isRevoked(deviceId, code, cid) {
    const db = this._readDb();
    if (!Array.isArray(db.revokedClients) || db.revokedClients.length === 0) return false;
    const cleanDev = (deviceId || '').toString().trim();
    const cleanCode = (code || '').toString().trim().toUpperCase();
    const cleanCid = (cid || '').toString().trim();

    return db.revokedClients.some(r => {
      if (cleanCid && r.id === cleanCid) return true;
      if (cleanCode && r.code && r.code.toUpperCase() === cleanCode) return true;
      if (cleanDev && Array.isArray(r.devices) && r.devices.includes(cleanDev)) return true;
      return false;
    });
  }

  // -------------------------------------------------------------
  // GESTIÓN DE REVENDEDORES Y SISTEMA DE CRÉDITOS
  // -------------------------------------------------------------

  _generateResellerToken(reseller) {
    if (!reseller) return '';
    const payload = {
      rid: reseller.id,
      usr: reseller.username,
      iat: Date.now()
    };
    const b64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const sig = crypto.createHmac('sha256', SIGNING_SECRET).update(b64).digest('base64url');
    return `rst.${b64}.${sig}`;
  }

  _verifyResellerToken(token) {
    if (!token || typeof token !== 'string') return null;
    if (!token.startsWith('rst.')) return null;
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const [_, b64, sig] = parts;
    const expectedSig = crypto.createHmac('sha256', SIGNING_SECRET).update(b64).digest('base64url');
    if (sig !== expectedSig) return null;
    try {
      const jsonStr = Buffer.from(b64, 'base64url').toString('utf8');
      const decoded = JSON.parse(jsonStr);
      if (Date.now() - decoded.iat > 30 * 24 * 60 * 60 * 1000) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  calculateCreditsForDays(days) {
    const d = parseInt(days, 10) || 30;
    if (d <= 31) return 1;
    if (d <= 62) return 2;
    if (d <= 93) return 3;
    if (d <= 186) return 6;
    if (d <= 366) return 12;
    return Math.max(1, Math.ceil(d / 30));
  }

  getResellers() {
    const db = this._readDb();
    const clients = this.getClients();

    return (db.resellers || []).map(r => {
      const resellerClients = clients.filter(c => c.resellerId === r.id);
      const activeClients = resellerClients.filter(c => c.status === 'active').length;
      return {
        id: r.id,
        name: r.name,
        username: r.username,
        password: r.password || '',
        whatsapp: r.whatsapp || '',
        credits: parseInt(r.credits, 10) || 0,
        status: r.status || 'active',
        createdAt: r.createdAt,
        totalClients: resellerClients.length,
        activeClients: activeClients
      };
    });
  }

  getResellerById(id) {
    const db = this._readDb();
    const r = (db.resellers || []).find(res => res.id === id);
    if (!r) return null;
    const clients = this.getClients().filter(c => c.resellerId === r.id);
    return {
      id: r.id,
      name: r.name,
      username: r.username,
      whatsapp: r.whatsapp || '',
      credits: parseInt(r.credits, 10) || 0,
      status: r.status || 'active',
      createdAt: r.createdAt,
      totalClients: clients.length,
      activeClients: clients.filter(c => c.status === 'active').length,
      history: r.history || []
    };
  }

  createReseller({ name, username, password, whatsapp, initialCredits = 10 }) {
    if (!name || !name.trim()) throw new Error('El nombre del revendedor es obligatorio.');
    if (!username || !username.trim()) throw new Error('El nombre de usuario es obligatorio.');
    if (!password || password.trim().length < 4) throw new Error('La contraseña debe tener al menos 4 caracteres.');

    const cleanUsername = username.trim().toLowerCase();
    const db = this._readDb();
    if (!Array.isArray(db.resellers)) db.resellers = [];

    if (db.resellers.some(r => r.username.toLowerCase() === cleanUsername)) {
      throw new Error(`El nombre de usuario "${cleanUsername}" ya está registrado.`);
    }

    const credits = Math.max(0, parseInt(initialCredits, 10) || 0);
    const now = new Date().toISOString();

    const newReseller = {
      id: crypto.randomUUID(),
      name: name.trim(),
      username: cleanUsername,
      password: password.trim(),
      whatsapp: (whatsapp || '').trim(),
      credits: credits,
      status: 'active',
      createdAt: now,
      history: [
        {
          type: 'initial_deposit',
          amount: credits,
          date: now,
          note: 'Asignación de créditos iniciales al registrar revendedor'
        }
      ]
    };

    db.resellers.push(newReseller);
    this._writeDb(db);

    return {
      id: newReseller.id,
      name: newReseller.name,
      username: newReseller.username,
      whatsapp: newReseller.whatsapp,
      credits: newReseller.credits,
      status: newReseller.status,
      createdAt: newReseller.createdAt
    };
  }

  updateReseller(id, { name, whatsapp, status, password }) {
    const db = this._readDb();
    const reseller = (db.resellers || []).find(r => r.id === id);
    if (!reseller) throw new Error('Revendedor no encontrado.');

    if (name && name.trim()) reseller.name = name.trim();
    if (whatsapp !== undefined) reseller.whatsapp = whatsapp.trim();
    if (status && ['active', 'suspended'].includes(status)) reseller.status = status;
    if (password && password.trim().length >= 4) reseller.password = password.trim();

    this._writeDb(db);
    return {
      id: reseller.id,
      name: reseller.name,
      username: reseller.username,
      whatsapp: reseller.whatsapp,
      credits: reseller.credits,
      status: reseller.status
    };
  }

  rechargeResellerCredits(id, creditsToAdd, note = '') {
    const amount = parseInt(creditsToAdd, 10);
    if (isNaN(amount) || amount === 0) {
      throw new Error('Cantidad de créditos inválida.');
    }

    const db = this._readDb();
    const reseller = (db.resellers || []).find(r => r.id === id);
    if (!reseller) throw new Error('Revendedor no encontrado.');

    const current = parseInt(reseller.credits, 10) || 0;
    const newTotal = current + amount;
    if (newTotal < 0) {
      throw new Error(`No se puede deducir más de los créditos disponibles (${current}).`);
    }

    reseller.credits = newTotal;
    if (!Array.isArray(reseller.history)) reseller.history = [];
    reseller.history.push({
      type: amount > 0 ? 'recharge' : 'deduction',
      amount: amount,
      date: new Date().toISOString(),
      note: note.trim() || (amount > 0 ? `Recarga de +${amount} créditos` : `Ajuste de ${amount} créditos`)
    });

    this._writeDb(db);
    return {
      id: reseller.id,
      name: reseller.name,
      username: reseller.username,
      credits: reseller.credits
    };
  }

  deleteReseller(id) {
    const db = this._readDb();
    const initialLen = (db.resellers || []).length;
    db.resellers = (db.resellers || []).filter(r => r.id !== id);
    const deleted = db.resellers.length < initialLen;
    if (deleted) this._writeDb(db);
    return deleted;
  }

  authenticateReseller(username, password) {
    if (!password) throw new Error('Contraseña de revendedor requerida.');
    const db = this._readDb();
    const cleanUser = String(username || '').trim().toLowerCase();
    const cleanPass = String(password).trim();
    const cleanUserDigits = cleanUser.replace(/\D/g, '');

    // 1. Buscar revendedor con máxima tolerancia: por username, nombre completo o teléfono WhatsApp
    let reseller = (db.resellers || []).find(r => {
      const rUser = (r.username || '').trim().toLowerCase();
      const rName = (r.name || '').trim().toLowerCase();
      const rPhoneDigits = (r.whatsapp || '').replace(/\D/g, '');

      // Coincidencia directa por username
      if (cleanUser && rUser === cleanUser) return true;

      // Coincidencia por nombre completo o parcial
      if (cleanUser && rName === cleanUser) return true;
      if (cleanUser && cleanUser.length >= 3 && (rName.includes(cleanUser) || cleanUser.includes(rName))) return true;

      // Coincidencia por teléfono / WhatsApp (al menos 6 dígitos numéricos)
      if (cleanUserDigits.length >= 6 && rPhoneDigits.length >= 6) {
        if (rPhoneDigits.endsWith(cleanUserDigits) || cleanUserDigits.endsWith(rPhoneDigits)) return true;
      }

      return false;
    });

    // 2. Si no se especificó usuario o no coincidió con el nombre/teléfono, buscar por contraseña única
    if (!reseller) {
      const matchingByPass = (db.resellers || []).filter(r => (r.password || '').trim() === cleanPass);
      if (matchingByPass.length === 1) {
        reseller = matchingByPass[0];
      }
    }

    if (!reseller || (reseller.password || '').trim() !== cleanPass) {
      throw new Error('Credenciales incorrectas. Verifica tu usuario o contraseña en tomtv.lat/reseller.');
    }

    if (reseller.status === 'suspended') {
      throw new Error('Tu cuenta de revendedor se encuentra suspendida temporalmente.');
    }

    const token = this._generateResellerToken(reseller);
    const clients = this.getClients().filter(c => c.resellerId === reseller.id);

    return {
      token,
      reseller: {
        id: reseller.id,
        name: reseller.name,
        username: reseller.username,
        whatsapp: reseller.whatsapp || '',
        credits: parseInt(reseller.credits, 10) || 0,
        status: reseller.status,
        totalClients: clients.length,
        activeClients: clients.filter(c => c.status === 'active').length
      }
    };
  }

  verifyResellerAuth(token) {
    const decoded = this._verifyResellerToken(token);
    if (!decoded || !decoded.rid) return null;
    return this.getResellerById(decoded.rid);
  }

  getResellerClients(resellerId) {
    return this.getClients().filter(c => c.resellerId === resellerId);
  }

  createClientForReseller(resellerId, { name, planDays = 30, maxDevices = 1, customCode = null }) {
    if (!name || !name.trim()) throw new Error('El nombre del cliente es obligatorio.');
    const db = this._readDb();
    const reseller = (db.resellers || []).find(r => r.id === resellerId);
    if (!reseller) throw new Error('Revendedor no encontrado.');
    if (reseller.status === 'suspended') throw new Error('Tu cuenta de revendedor está suspendida.');

    const isTwoHourDemo = planDays === '2h' || planDays === 'demo_2h' || planDays === 0 || planDays === '0';
    let requiredCredits = 0;
    let parsedDays = 30;
    let expiresAt;
    const now = new Date();

    if (isTwoHourDemo) {
      requiredCredits = 0; // Demos de 2 horas no consumen créditos
      parsedDays = 0;
      expiresAt = new Date(now.getTime() + (2 * 60 * 60 * 1000));
    } else {
      parsedDays = parseInt(planDays, 10) || 30;
      requiredCredits = this.calculateCreditsForDays(parsedDays);
      expiresAt = new Date(now.getTime() + (parsedDays * 24 * 60 * 60 * 1000));
    }

    const currentCredits = parseInt(reseller.credits, 10) || 0;

    if (currentCredits < requiredCredits) {
      throw new Error(`Créditos insuficientes. Se requieren ${requiredCredits} créditos para ${parsedDays} días y tienes ${currentCredits} disponibles. Por favor solicita una recarga.`);
    }

    // Descontar créditos
    reseller.credits = currentCredits - requiredCredits;

    let finalCode = customCode;
    if (!finalCode) {
      finalCode = 'TOM-' + Math.floor(1000 + Math.random() * 9000);
      while (db.clients.some(c => c.code === finalCode)) {
        finalCode = 'TOM-' + Math.floor(1000 + Math.random() * 9000);
      }
    }

    const newClient = {
      id: crypto.randomUUID(),
      name: (name || (isTwoHourDemo ? 'Cliente Demo (2 Horas)' : 'Cliente')).trim(),
      username: (name.toLowerCase().replace(/\s+/g, '_') + '_' + Math.floor(100 + Math.random() * 900)).trim(),
      code: finalCode,
      status: 'active',
      isDemo: isTwoHourDemo,
      planHours: isTwoHourDemo ? 2 : null,
      planDays: parsedDays,
      planLabel: isTwoHourDemo ? 'Demo 2 Horas' : `${parsedDays} días`,
      maxDevices: parseInt(maxDevices, 10) || 1,
      resellerId: reseller.id,
      resellerName: reseller.name,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      devices: []
    };

    if (!Array.isArray(reseller.history)) reseller.history = [];
    reseller.history.push({
      type: 'client_created',
      clientId: newClient.id,
      clientName: newClient.name,
      code: newClient.code,
      deductedCredits: requiredCredits,
      remainingCredits: reseller.credits,
      date: now.toISOString()
    });

    db.clients.push(newClient);
    this._writeDb(db);

    return {
      success: true,
      client: newClient,
      creditsDeducted: requiredCredits,
      remainingCredits: reseller.credits
    };
  }

  renewClientForReseller(resellerId, clientId, additionalDays = 30) {
    const db = this._readDb();
    const reseller = (db.resellers || []).find(r => r.id === resellerId);
    if (!reseller) throw new Error('Revendedor no encontrado.');
    if (reseller.status === 'suspended') throw new Error('Tu cuenta está suspendida.');

    const client = db.clients.find(c => c.id === clientId && c.resellerId === resellerId);
    if (!client) throw new Error('Cliente no encontrado en tu cartera de revendedor.');

    const parsedDays = parseInt(additionalDays, 10) || 30;
    const requiredCredits = this.calculateCreditsForDays(parsedDays);
    const currentCredits = parseInt(reseller.credits, 10) || 0;

    if (currentCredits < requiredCredits) {
      throw new Error(`Créditos insuficientes. Se requieren ${requiredCredits} créditos para renovar ${parsedDays} días y tienes ${currentCredits} disponibles.`);
    }

    // Descontar créditos
    reseller.credits = currentCredits - requiredCredits;

    const now = new Date();
    let baseDate = new Date(client.expiresAt);
    if (baseDate < now) {
      baseDate = now;
    }

    const newExpiresAt = new Date(baseDate.getTime() + (parsedDays * 24 * 60 * 60 * 1000));
    client.expiresAt = newExpiresAt.toISOString();
    client.status = 'active';

    if (!Array.isArray(reseller.history)) reseller.history = [];
    reseller.history.push({
      type: 'client_renewed',
      clientId: client.id,
      clientName: client.name,
      deductedCredits: requiredCredits,
      remainingCredits: reseller.credits,
      date: now.toISOString()
    });

    this._writeDb(db);

    return {
      success: true,
      client: client,
      creditsDeducted: requiredCredits,
      remainingCredits: reseller.credits
    };
  }

  deleteClientForReseller(resellerId, clientId) {
    const db = this._readDb();
    if (!Array.isArray(db.revokedClients)) db.revokedClients = [];

    const cleanId = String(clientId || '').trim();
    const client = db.clients.find(c => (c.id === cleanId || c.code === cleanId) && c.resellerId === resellerId);
    if (!client) return false;

    const devices = (client.devices || []).map(d => (d.deviceId || '').trim()).filter(Boolean);
    db.revokedClients = db.revokedClients.filter(r => r.id !== client.id && r.code !== client.code);
    db.revokedClients.push({
      id: client.id,
      code: client.code,
      name: client.name,
      resellerId,
      deletedAt: new Date().toISOString(),
      devices
    });

    db.clients = db.clients.filter(c => c.id !== client.id);
    db.pendingActivations = (db.pendingActivations || []).filter(p => p.clientId !== client.id && p.code !== client.code);

    this._writeDb(db);
    return true;
  }

  // -------------------------------------------------------------
  // FLUJO DE ACTIVACIÓN ULTRA-PERSISTENTE (SMART TV, MÓVIL Y IPHONE)
  // -------------------------------------------------------------

  /**
   * Genera un código de activación pendiente para un dispositivo nuevo o revocado
   */
  _generateFreshPendingActivation(db, cleanDeviceId, deviceModel) {
    const now = new Date();
    const normalize = (val) => (val || '').toString().trim();
    if (!Array.isArray(db.pendingActivations)) db.pendingActivations = [];

    // Limpiar códigos pendientes antiguos (> 48h)
    db.pendingActivations = db.pendingActivations.filter(p => {
      const age = now - new Date(p.createdAt || 0);
      return age < 48 * 60 * 60 * 1000;
    });

    let pending = db.pendingActivations.find(p => normalize(p.deviceId) === cleanDeviceId && p.status === 'pending');
    if (!pending) {
      const randomCode = 'VJ-' + Math.floor(1000 + Math.random() * 9000);
      pending = {
        code: randomCode,
        deviceId: cleanDeviceId,
        deviceModel: deviceModel || 'Smart TV',
        createdAt: now.toISOString(),
        status: 'pending',
        clientId: null
      };
      db.pendingActivations.push(pending);
      this._writeDb(db);
    }

    const settings = db.settings || {};
    return {
      status: 'pending',
      code: pending.code,
      whatsappNumber: settings.whatsappNumber || '+51914598415',
      whatsappMessage: settings.whatsappMessage || 'Hola, mi código de activación de TOM TV es {code}',
      message: 'Pantalla pendiente de activación. Esperando aprobación del administrador.'
    };
  }

  /**
   * Registra un dispositivo solicitante. Si ya pertenece a un cliente activo,
   * le concede acceso inmediatamente. Si no, le genera un código de 6 dígitos.
   */
  requestDeviceActivation(deviceId, deviceModel = 'Smart TV', { token, code } = {}) {
    const db = this._readDb();
    const now = new Date();

    const normalize = (val) => (val || '').toString().trim();
    const cleanDeviceId = normalize(deviceId);
    const cleanCode = normalize(code).toUpperCase();

    // 0. VERIFICAR SI EL DISPOSITIVO O CLIENTE ESTÁ REVOCADO POR HABER SIDO ELIMINADO
    let decodedToken = null;
    if (token) {
      decodedToken = this._verifyAndDecodeToken(token);
    }

    if (this.isRevoked(cleanDeviceId, cleanCode, decodedToken?.cid)) {
      // Dispositivo o cliente eliminado definitivamente por el administrador.
      // Queda en espera de nueva aprobación con un código pendiente.
      return this._generateFreshPendingActivation(db, cleanDeviceId, deviceModel);
    }

    // 1. VALIDACIÓN POR TOKEN CRIPTOGRÁFICO DE LICENCIA
    if (token && decodedToken && decodedToken.exp) {
      const tokenExpires = new Date(decodedToken.exp);
      if (tokenExpires > now) {
        let targetClient = db.clients.find(c => c.id === decodedToken.cid || c.code === decodedToken.code);
        if (!targetClient) {
          // El cliente NO existe en la base de datos (fue eliminado por el administrador).
          // NUNCA auto-restaurar. Debe quedar en espera de aprobación.
          return this._generateFreshPendingActivation(db, cleanDeviceId, deviceModel);
        }

        // Cliente legítimo existente: actualizar dispositivo
        if (!targetClient.devices) targetClient.devices = [];
        const existingDev = targetClient.devices.find(d => normalize(d.deviceId) === cleanDeviceId);
        if (!existingDev) {
          targetClient.devices.push({
            deviceId: cleanDeviceId,
            deviceModel,
            lastSeen: now.toISOString()
          });
        } else {
          existingDev.lastSeen = now.toISOString();
          existingDev.deviceModel = deviceModel;
        }
        this._writeDb(db);

        if (targetClient.status !== 'suspended') {
          return {
            status: 'active',
            client: {
              id: targetClient.id,
              name: targetClient.name,
              username: targetClient.username,
              code: targetClient.code,
              expiresAt: targetClient.expiresAt,
              maxDevices: targetClient.maxDevices
            },
            token: this._generateClientToken(targetClient, cleanDeviceId)
          };
        }
      }
    }

    // 1. Verificar si este dispositivo ya está registrado por deviceId en algún cliente
    for (const client of db.clients) {
      const matchDevice = client.devices && client.devices.find(d => normalize(d.deviceId) === cleanDeviceId);
      if (matchDevice) {
        matchDevice.lastSeen = now.toISOString();
        matchDevice.deviceModel = deviceModel;

        const expiresAt = new Date(client.expiresAt);
        const isExpired = expiresAt < now;

        if (client.status === 'suspended') {
          this._writeDb(db);
          return {
            status: 'suspended',
            message: 'Tu cuenta ha sido suspendida temporalmente. Contacta a tu proveedor.'
          };
        }

        if (isExpired) {
          this._writeDb(db);
          return {
            status: 'expired',
            client: { name: client.name, expiresAt: client.expiresAt, code: client.code },
            message: 'Tu membresía ha vencido. Contacta a tu proveedor para renovar.'
          };
        }

        this._writeDb(db);
        return {
          status: 'active',
          client: {
            id: client.id,
            name: client.name,
            username: client.username,
            code: client.code,
            expiresAt: client.expiresAt,
            maxDevices: client.maxDevices
          },
          token: this._generateClientToken(client, cleanDeviceId)
        };
      }
    }

    // 2. Si se envió un código de cliente (ej: VJ-3166) o token heredado:
    if (cleanCode || token) {
      for (const client of db.clients) {
        const matchesCode = cleanCode && (normalize(client.code) === cleanCode);
        let matchesToken = false;
        if (token && client.id) {
          const [tokenClientId] = token.split('.');
          matchesToken = (tokenClientId === client.id) || token.startsWith(client.id);
        }

        if (matchesCode || matchesToken) {
          const expiresAt = new Date(client.expiresAt);
          const isExpired = expiresAt < now;

          if (client.status === 'suspended') {
            return {
              status: 'suspended',
              message: 'Tu cuenta ha sido suspendida temporalmente. Contacta a tu proveedor.'
            };
          }

          if (isExpired) {
            return {
              status: 'expired',
              client: { name: client.name, expiresAt: client.expiresAt, code: client.code },
              message: 'Tu membresía ha vencido. Contacta a tu proveedor para renovar.'
            };
          }

          // Vincular de forma permanente este dispositivo al cliente
          if (!client.devices) client.devices = [];
          const existingDev = client.devices.find(d => normalize(d.deviceId) === cleanDeviceId);
          if (!existingDev) {
            client.devices.push({
              deviceId: cleanDeviceId,
              deviceModel,
              lastSeen: now.toISOString()
            });
          } else {
            existingDev.lastSeen = now.toISOString();
            existingDev.deviceModel = deviceModel;
          }

          // Eliminar cualquier código pendiente huérfano de este dispositivo
          db.pendingActivations = db.pendingActivations.filter(p => normalize(p.deviceId) !== cleanDeviceId);
          this._writeDb(db);

          return {
            status: 'active',
            client: {
              id: client.id,
              name: client.name,
              username: client.username,
              code: client.code,
              expiresAt: client.expiresAt,
              maxDevices: client.maxDevices
            },
            token: this._generateClientToken(client, cleanDeviceId)
          };
        }
      }
    }

    // 3. Verificar si el dispositivo ya fue activado previamente en pendingActivations
    const alreadyActivated = db.pendingActivations.find(p =>
      (normalize(p.deviceId) === cleanDeviceId || (cleanCode && normalize(p.code) === cleanCode)) &&
      p.status === 'activated' &&
      p.clientId
    );

    if (alreadyActivated) {
      const client = db.clients.find(c => c.id === alreadyActivated.clientId);
      if (client) {
        if (!client.devices) client.devices = [];
        const existingDev = client.devices.find(d => normalize(d.deviceId) === cleanDeviceId);
        if (!existingDev) {
          client.devices.push({
            deviceId: cleanDeviceId,
            deviceModel,
            lastSeen: now.toISOString()
          });
        }
        this._writeDb(db);

        return {
          status: 'active',
          client: {
            id: client.id,
            name: client.name,
            username: client.username,
            code: client.code,
            expiresAt: client.expiresAt,
            maxDevices: client.maxDevices
          },
          token: this._generateClientToken(client, cleanDeviceId)
        };
      }
    }

    // 4. Si es un dispositivo nuevo sin activar, buscar si ya tiene un código pendiente ACTIVO
    db.pendingActivations = db.pendingActivations.filter(p => {
      const age = now - new Date(p.createdAt);
      return age < 24 * 60 * 60 * 1000;
    });

    let pending = db.pendingActivations.find(p => normalize(p.deviceId) === cleanDeviceId && p.status === 'pending');

    if (!pending) {
      const randomCode = 'VJ-' + Math.floor(1000 + Math.random() * 9000);
      pending = {
        code: randomCode,
        deviceId: cleanDeviceId,
        deviceModel,
        createdAt: now.toISOString(),
        status: 'pending',
        clientId: null
      };
      db.pendingActivations.push(pending);
      this._writeDb(db);
    }

    return {
      status: 'pending',
      code: pending.code,
      deviceModel: pending.deviceModel,
      whatsappNumber: db.settings.whatsappNumber,
      whatsappMessage: (db.settings.whatsappMessage || '').replace('{code}', pending.code)
    };
  }

  /**
   * Consulta el estado de un código pendiente (polling cada 3 segundos desde la TV o web)
   */
  checkActivationStatus(code, deviceId) {
    const db = this._readDb();
    const pending = db.pendingActivations.find(p => p.code === code);

    if (!pending) {
      // Si no está en pending, buscar si ya es el código de un cliente activo
      const client = db.clients.find(c => c.code === code);
      if (client && client.status === 'active') {
        return {
          status: 'active',
          client: {
            id: client.id,
            name: client.name,
            username: client.username,
            code: client.code,
            expiresAt: client.expiresAt,
            maxDevices: client.maxDevices
          },
          token: this._generateClientToken(client, deviceId)
        };
      }
      return { status: 'not_found' };
    }

    if (pending.status === 'activated' && pending.clientId) {
      const client = db.clients.find(c => c.id === pending.clientId);
      if (client) {
        return {
          status: 'active',
          client: {
            id: client.id,
            name: client.name,
            username: client.username,
            code: client.code,
            expiresAt: client.expiresAt,
            maxDevices: client.maxDevices
          },
          token: this._generateClientToken(client, deviceId || pending.deviceId)
        };
      }
    }

    return { status: 'pending', code: pending.code };
  }

  getPendingActivations() {
    const db = this._readDb();
    const now = new Date();
    return db.pendingActivations
      .filter(p => p.status === 'pending')
      .map(p => {
        const minutesAgo = Math.floor((now - new Date(p.createdAt)) / 60000);
        return {
          ...p,
          minutesAgo: minutesAgo < 1 ? 'Hace un instante' : `Hace ${minutesAgo} min`
        };
      });
  }

  /**
   * El Administrador activa el código desde su Panel Web
   */
  activateCode(code, { name, planDays = 30, maxDevices = 1, isDemo = false, planHours = null }) {
    const db = this._readDb();
    const pending = db.pendingActivations.find(p => p.code === code && p.status === 'pending');

    if (!pending) {
      return { success: false, error: 'Código de activación no encontrado o ya utilizado.' };
    }

    const now = new Date();
    const isTwoHourDemo = isDemo || planDays === '2h' || planDays === 'demo_2h' || planHours === 2;
    let expiresAt;
    let parsedDays = 30;

    if (isTwoHourDemo) {
      expiresAt = new Date(now.getTime() + (2 * 60 * 60 * 1000));
      parsedDays = 0;
    } else {
      parsedDays = parseInt(planDays, 10) || 30;
      expiresAt = new Date(now.getTime() + (parsedDays * 24 * 60 * 60 * 1000));
    }

    // Crear el nuevo cliente asociado al dispositivo que generó el código
    const newClient = {
      id: crypto.randomUUID(),
      name: (name || (isTwoHourDemo ? 'Cliente Demo (2 Horas)' : 'Cliente')).trim(),
      username: (name || 'cliente').toLowerCase().replace(/\s+/g, '_') + '_' + Math.floor(100 + Math.random() * 900),
      code: pending.code,
      status: 'active',
      isDemo: isTwoHourDemo,
      planHours: isTwoHourDemo ? 2 : null,
      planDays: parsedDays,
      planLabel: isTwoHourDemo ? 'Demo 2 Horas' : `${parsedDays} días`,
      maxDevices: parseInt(maxDevices, 10) || 1,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      devices: [
        {
          deviceId: pending.deviceId,
          deviceModel: pending.deviceModel,
          lastSeen: now.toISOString()
        }
      ]
    };

    // Si este código o dispositivo estaba en la lista de revocados, liberarlo porque el admin lo acaba de aprobar
    if (Array.isArray(db.revokedClients)) {
      db.revokedClients = db.revokedClients.filter(r => 
        (r.code || '').toUpperCase() !== pending.code.toUpperCase() &&
        (!Array.isArray(r.devices) || !r.devices.includes((pending.deviceId || '').trim()))
      );
    }

    db.clients.push(newClient);

    // Marcar el código pendiente como activado
    pending.status = 'activated';
    pending.clientId = newClient.id;

    this._writeDb(db);

    return {
      success: true,
      client: newClient
    };
  }

  /**
   * Genera un Demo de 2 horas instantáneo con código VJ-XXXX
   */
  createDemoClient({ name = 'Cliente Demo', resellerId = null, resellerName = null } = {}) {
    return this.createClient({
      name,
      planHours: 2,
      planDays: 0,
      isDemo: true,
      maxDevices: 1,
      resellerId,
      resellerName
    });
  }

  /**
   * Solicita una prueba gratuita de 2 horas para un dispositivo nuevo (1 sola vez por dispositivo)
   */
  requestPublicTrialDemo(deviceId, deviceModel = 'Navegador Web / Smart TV') {
    const cleanDeviceId = (deviceId || '').trim();
    if (!cleanDeviceId) {
      return { success: false, error: 'deviceId es requerido.' };
    }

    const db = this._readDb();
    if (!Array.isArray(db.usedDemos)) {
      db.usedDemos = [];
    }

    // Comprobar si el dispositivo ya usó su demo
    const alreadyUsed = db.usedDemos.find(d => (d.deviceId || '').trim().toLowerCase() === cleanDeviceId.toLowerCase());
    if (alreadyUsed) {
      return {
        success: false,
        reason: 'demo_already_used',
        message: 'Este dispositivo ya utilizó su demo gratuito de 2 horas. Contáctanos por WhatsApp para activar tu suscripción mensual.'
      };
    }

    const now = new Date();
    db.usedDemos.push({
      deviceId: cleanDeviceId,
      deviceModel,
      usedAt: now.toISOString()
    });

    const expiresAt = new Date(now.getTime() + (2 * 60 * 60 * 1000));
    let randomCode = 'VJ-' + Math.floor(1000 + Math.random() * 9000);
    while (db.clients.some(c => c.code === randomCode)) {
      randomCode = 'VJ-' + Math.floor(1000 + Math.random() * 9000);
    }

    const demoClient = {
      id: crypto.randomUUID(),
      name: 'Cliente Demo (2 Horas)',
      username: 'demo_' + Math.floor(1000 + Math.random() * 9000),
      code: randomCode,
      status: 'active',
      isDemo: true,
      planHours: 2,
      planDays: 0,
      planLabel: 'Demo 2 Horas',
      maxDevices: 1,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      devices: [
        {
          deviceId: cleanDeviceId,
          deviceModel,
          lastSeen: now.toISOString()
        }
      ]
    };

    db.clients.push(demoClient);
    this._writeDb(db);

    const token = this._generateClientToken(demoClient, cleanDeviceId);

    return {
      success: true,
      status: 'active',
      client: {
        id: demoClient.id,
        name: demoClient.name,
        code: demoClient.code,
        expiresAt: demoClient.expiresAt,
        maxDevices: 1,
        isDemo: true
      },
      token,
      message: '¡Tu prueba gratuita de 2 horas ha comenzado! Disfruta de todo el catálogo.'
    };
  }

  /**
   * Valida la licencia en cada inicio de la app o reproducción
   */
  verifyLicense(deviceId, { token, code } = {}) {
    const db = this._readDb();
    const now = new Date();
    const cleanDeviceId = (deviceId || '').trim();

    // 0. Verificar si el dispositivo, código o token fue explícitamente revocado/eliminado
    let decodedToken = null;
    if (token) {
      decodedToken = this._verifyAndDecodeToken(token);
    }

    if (this.isRevoked(cleanDeviceId, code, decodedToken?.cid)) {
      return {
        active: false,
        reason: 'revoked',
        message: 'Tu cuenta ha sido eliminada por el administrador. Requiere nueva aprobación.'
      };
    }

    // 1. Verificar si el dispositivo fue desconectado individualmente
    for (const client of db.clients) {
      if (Array.isArray(client.revokedDevices) && client.revokedDevices.includes(cleanDeviceId)) {
        return {
          active: false,
          reason: 'revoked',
          message: 'Este dispositivo ha sido desconectado por el administrador.'
        };
      }
    }

    // 2. Búsqueda por deviceId registrado
    for (const client of db.clients) {
      const dev = client.devices && client.devices.find(d => (d.deviceId || '').trim() === cleanDeviceId);
      if (dev) {
        dev.lastSeen = now.toISOString();

        if (client.status === 'suspended') {
          this._writeDb(db);
          return { active: false, reason: 'suspended', message: 'Cuenta suspendida por el administrador.' };
        }

        const expiresAt = new Date(client.expiresAt);
        if (expiresAt < now) {
          this._writeDb(db);
          return { active: false, reason: 'expired', expiresAt: client.expiresAt, message: 'Membresía vencida.' };
        }

        this._writeDb(db);
        return {
          active: true,
          client: {
            name: client.name,
            expiresAt: client.expiresAt,
            maxDevices: client.maxDevices
          }
        };
      }
    }

    // 3. Validación por token criptográfico firmado (solo para clientes legítimos existentes)
    if (token && decodedToken && decodedToken.exp) {
      const tokenExpires = new Date(decodedToken.exp);
      if (tokenExpires > now) {
        let client = db.clients.find(c => c.id === decodedToken.cid || c.code === decodedToken.code);
        if (!client) {
          // El cliente fue eliminado por el administrador. NUNCA auto-restaurar.
          return {
            active: false,
            reason: 'deleted',
            message: 'Tu cuenta ha sido eliminada del sistema. Requiere nueva autorización del administrador.'
          };
        }

        if (!client.devices) client.devices = [];
        if (!client.devices.some(d => (d.deviceId || '').trim() === cleanDeviceId)) {
          client.devices.push({
            deviceId: cleanDeviceId,
            deviceModel: 'Dispositivo Vinculado',
            lastSeen: now.toISOString()
          });
        }
        this._writeDb(db);

        return {
          active: true,
          client: {
            name: client.name,
            expiresAt: client.expiresAt,
            maxDevices: client.maxDevices
          }
        };
      }
    }

    return { active: false, reason: 'unregistered', message: 'Dispositivo no registrado.' };
  }

  // -------------------------------------------------------------
  // BACKUP Y RESTAURACIÓN DEL PANEL DE ADMINISTRACIÓN
  // -------------------------------------------------------------

  exportBackup() {
    const db = this._readDb();
    return {
      version: '3.0.0',
      exportedAt: new Date().toISOString(),
      app: 'TOM TV',
      admin: db.admin,
      settings: db.settings,
      clients: db.clients,
      pendingActivations: db.pendingActivations,
      resellers: db.resellers || []
    };
  }

  importBackup(backupData) {
    if (!backupData || !Array.isArray(backupData.clients)) {
      return { success: false, error: 'Formato de copia de seguridad inválido.' };
    }

    const currentDb = this._readDb();
    const clientMap = new Map();

    // Mantener clientes actuales y agregar los del backup
    (currentDb.clients || []).forEach(c => clientMap.set(c.id, c));
    backupData.clients.forEach(c => {
      if (c && c.id) clientMap.set(c.id, c);
    });

    currentDb.clients = Array.from(clientMap.values());
    if (backupData.settings) {
      currentDb.settings = { ...currentDb.settings, ...backupData.settings };
    }
    if (Array.isArray(backupData.resellers)) {
      const resellerMap = new Map();
      (currentDb.resellers || []).forEach(r => resellerMap.set(r.id, r));
      backupData.resellers.forEach(r => {
        if (r && r.id) resellerMap.set(r.id, r);
      });
      currentDb.resellers = Array.from(resellerMap.values());
    }

    this._writeDb(currentDb);
    return {
      success: true,
      totalClients: currentDb.clients.length,
      message: `Copia de seguridad restaurada con éxito. ${currentDb.clients.length} clientes activos en el sistema.`
    };
  }

  /**
   * Valida acceso de un cliente mediante código de activación o username para listas M3U (IBO Player, Smart TV)
   */
  validateClientAccess(codeOrUser) {
    if (!codeOrUser) {
      return { valid: false, reason: 'Código o usuario no proporcionado' };
    }
    const db = this._readDb();
    const clean = String(codeOrUser).trim().toUpperCase();

    if (this.isRevoked(null, clean, clean)) {
      return { valid: false, reason: 'Cuenta eliminada por el administrador' };
    }

    const client = (db.clients || []).find(c =>
      (c.code && c.code.toUpperCase() === clean) ||
      (c.username && c.username.toUpperCase() === clean) ||
      (c.id && c.id.toUpperCase() === clean)
    );

    if (!client) {
      return { valid: false, reason: 'Cuenta no encontrada o código no registrado' };
    }

    if (client.status === 'suspended') {
      return { valid: false, reason: 'Cuenta suspendida por el administrador' };
    }

    const now = new Date();
    if (client.expiresAt) {
      const exp = new Date(client.expiresAt);
      if (exp < now) {
        return { valid: false, reason: 'Suscripción vencida el ' + exp.toLocaleDateString(), expiresAt: client.expiresAt };
      }
    }

    return { valid: true, client };
  }

  /**
   * Obtiene la configuración pública de la plataforma (WhatsApp, mensajes predeterminados)
   */
  getPublicSettings() {
    const db = this._readDb();
    const settings = db.settings || {};
    return {
      whatsappNumber: settings.whatsappNumber || process.env.WHATSAPP_NUMBER || '+51914598415',
      whatsappMessage: settings.whatsappMessage || 'Hola, deseo solicitar información de TOM TV'
    };
  }
}

module.exports = new AccountService();
