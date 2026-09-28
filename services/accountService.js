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
        whatsappNumber: process.env.WHATSAPP_NUMBER || '+51999999999',
        whatsappMessage: 'Hola, mi código de activación de TOM TV es {code}',
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
      pendingActivations: []
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
      // Sincronizar clientes existentes entre DB y Backup para máxima persistencia
      try {
        const dbData = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
        if (fs.existsSync(BACKUP_FILE)) {
          const backupData = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8'));
          if (Array.isArray(backupData.clients) && backupData.clients.length > (dbData.clients || []).length) {
            // Si el backup tiene más clientes que la DB de Git, fusionar
            const clientMap = new Map();
            (dbData.clients || []).forEach(c => clientMap.set(c.id, c));
            backupData.clients.forEach(c => {
              if (!clientMap.has(c.id)) clientMap.set(c.id, c);
            });
            dbData.clients = Array.from(clientMap.values());
            fs.writeFileSync(DB_FILE, JSON.stringify(dbData, null, 2), 'utf8');
          }
        } else {
          fs.writeFileSync(BACKUP_FILE, JSON.stringify(dbData, null, 2), 'utf8');
        }
      } catch (_) {}
    }
  }

  _readDb() {
    this._ensureDb();
    try {
      const content = fs.readFileSync(DB_FILE, 'utf8');
      const data = JSON.parse(content);
      if (!Array.isArray(data.resellers)) {
        data.resellers = [];
      }
      return data;
    } catch (e) {
      console.error('[AccountService] Error leyendo DB:', e);
      if (fs.existsSync(BACKUP_FILE)) {
        try {
          const bData = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8'));
          if (!Array.isArray(bData.resellers)) bData.resellers = [];
          return bData;
        } catch (_) {}
      }
      return { admin: { password: DEFAULT_ADMIN_PASSWORD }, settings: {}, clients: [], pendingActivations: [], resellers: [] };
    }
  }

  _writeDb(data) {
    try {
      const jsonStr = JSON.stringify(data, null, 2);
      fs.writeFileSync(DB_FILE, jsonStr, 'utf8');
      // Guardar copia de seguridad redundante simultáneamente
      fs.writeFileSync(BACKUP_FILE, jsonStr, 'utf8');
      return true;
    } catch (e) {
      console.error('[AccountService] Error escribiendo en DB:', e);
      return false;
    }
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
    const db = this._readDb();
    const adminPass = db.admin?.password || DEFAULT_ADMIN_PASSWORD;
    return password === adminPass;
  }

  updateSettings({ adminPassword, whatsappNumber, whatsappMessage }) {
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
    this._writeDb(db);
    return db.settings;
  }

  getSettings() {
    const db = this._readDb();
    return db.settings || {};
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

  deleteClient(clientId) {
    const db = this._readDb();
    const initialLen = db.clients.length;
    db.clients = db.clients.filter(c => c.id !== clientId);
    const deleted = db.clients.length < initialLen;
    if (deleted) this._writeDb(db);
    return deleted;
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
    if (!username || !password) throw new Error('Usuario y contraseña requeridos.');
    const db = this._readDb();
    const cleanUser = username.trim().toLowerCase();
    const cleanPass = password.trim();

    const reseller = (db.resellers || []).find(r => r.username.toLowerCase() === cleanUser);
    if (!reseller || reseller.password !== cleanPass) {
      throw new Error('Usuario o contraseña de revendedor incorrectos.');
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
    const initialLen = db.clients.length;
    db.clients = db.clients.filter(c => !(c.id === clientId && c.resellerId === resellerId));
    const deleted = db.clients.length < initialLen;
    if (deleted) this._writeDb(db);
    return deleted;
  }

  // -------------------------------------------------------------
  // FLUJO DE ACTIVACIÓN ULTRA-PERSISTENTE (SMART TV, MÓVIL Y IPHONE)
  // -------------------------------------------------------------

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

    // 0. AUTO-RESTAURACIÓN POR TOKEN DE LICENCIA CRIPTOGRÁFICA (A PRUEBA DE REINICIOS DE RENDER)
    if (token) {
      const decoded = this._verifyAndDecodeToken(token);
      if (decoded && decoded.exp) {
        const tokenExpires = new Date(decoded.exp);
        if (tokenExpires > now) {
          // El token es auténtico y no ha vencido
          let targetClient = db.clients.find(c => c.id === decoded.cid || c.code === decoded.code);
          if (!targetClient) {
            // Auto-restaurar al cliente si fue borrado por reinicio de contenedor
            targetClient = {
              id: decoded.cid || crypto.randomUUID(),
              name: decoded.name || 'Cliente Autorizado',
              username: (decoded.name || 'cliente').toLowerCase().replace(/\s+/g, '_') + '_' + Math.floor(100 + Math.random() * 900),
              code: decoded.code || ('VJ-' + Math.floor(1000 + Math.random() * 9000)),
              status: 'active',
              planDays: Math.ceil((tokenExpires - now) / (1000 * 60 * 60 * 24)) || 30,
              maxDevices: decoded.max || 1,
              createdAt: now.toISOString(),
              expiresAt: decoded.exp,
              devices: [
                {
                  deviceId: cleanDeviceId,
                  deviceModel,
                  lastSeen: now.toISOString()
                }
              ]
            };
            db.clients.push(targetClient);
            this._writeDb(db);
          } else {
            // Actualizar o vincular este dispositivo
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
          }

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

    // 1. Búsqueda por deviceId registrado
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

    // 2. Si no se encontró por deviceId pero hay token de licencia firmado (Auto-Sanación tras reinicios)
    if (token) {
      const decoded = this._verifyAndDecodeToken(token);
      if (decoded && decoded.exp) {
        const tokenExpires = new Date(decoded.exp);
        if (tokenExpires > now) {
          let client = db.clients.find(c => c.id === decoded.cid || c.code === decoded.code);
          if (!client) {
            client = {
              id: decoded.cid || crypto.randomUUID(),
              name: decoded.name || 'Cliente Autorizado',
              username: (decoded.name || 'cliente').toLowerCase().replace(/\s+/g, '_'),
              code: decoded.code || ('VJ-' + Math.floor(1000 + Math.random() * 9000)),
              status: 'active',
              planDays: 30,
              maxDevices: decoded.max || 1,
              createdAt: now.toISOString(),
              expiresAt: decoded.exp,
              devices: [
                {
                  deviceId: cleanDeviceId,
                  deviceModel: 'Dispositivo Vinculado',
                  lastSeen: now.toISOString()
                }
              ]
            };
            db.clients.push(client);
          } else {
            if (!client.devices) client.devices = [];
            if (!client.devices.some(d => (d.deviceId || '').trim() === cleanDeviceId)) {
              client.devices.push({
                deviceId: cleanDeviceId,
                deviceModel: 'Dispositivo Vinculado',
                lastSeen: now.toISOString()
              });
            }
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
}

module.exports = new AccountService();
