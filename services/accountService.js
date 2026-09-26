const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_DIR = path.resolve(__dirname, '..', 'data');
const DB_FILE = path.resolve(DATA_DIR, 'accounts.json');

// Contraseña de administrador por defecto (configurable por variable de entorno)
const DEFAULT_ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin1234';

class AccountService {
  constructor() {
    this._ensureDb();
  }

  _ensureDb() {
    if (!fs.existsSync(DATA_DIR)) {
      fs.mkdirSync(DATA_DIR, { recursive: true });
    }

    if (!fs.existsSync(DB_FILE)) {
      const initialData = {
        admin: {
          password: DEFAULT_ADMIN_PASSWORD,
        },
        settings: {
          whatsappNumber: process.env.WHATSAPP_NUMBER || '+51999999999',
          whatsappMessage: 'Hola, mi código de activación de VJ STREAM es {code}',
        },
        clients: [],
        pendingActivations: []
      };
      fs.writeFileSync(DB_FILE, JSON.stringify(initialData, null, 2), 'utf8');
    }
  }

  _readDb() {
    this._ensureDb();
    try {
      const content = fs.readFileSync(DB_FILE, 'utf8');
      return JSON.parse(content);
    } catch (e) {
      console.error('[AccountService] Error leyendo DB:', e);
      return { admin: { password: DEFAULT_ADMIN_PASSWORD }, settings: {}, clients: [], pendingActivations: [] };
    }
  }

  _writeDb(data) {
    try {
      fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2), 'utf8');
      return true;
    } catch (e) {
      console.error('[AccountService] Error escribiendo en DB:', e);
      return false;
    }
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

    // Actualizar estado dinámicamente según la fecha de expiración
    return db.clients.map(client => {
      const expiresAt = new Date(client.expiresAt);
      const isExpired = expiresAt < now;
      let computedStatus = client.status;

      if (client.status === 'active' && isExpired) {
        computedStatus = 'expired';
      }

      const diffDays = Math.ceil((expiresAt - now) / (1000 * 60 * 60 * 24));

      return {
        ...client,
        status: computedStatus,
        daysRemaining: isExpired ? 0 : diffDays,
        deviceCount: client.devices ? client.devices.length : 0
      };
    });
  }

  getClientById(id) {
    const clients = this.getClients();
    return clients.find(c => c.id === id);
  }

  createClient({ name, username, planDays = 30, maxDevices = 1 }) {
    const db = this._readDb();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + (planDays * 24 * 60 * 60 * 1000));

    const newClient = {
      id: crypto.randomUUID(),
      name: name.trim(),
      username: (username || name.toLowerCase().replace(/\s+/g, '_') + '_' + Math.floor(100 + Math.random() * 900)).trim(),
      code: 'VJ-' + Math.floor(1000 + Math.random() * 9000),
      status: 'active',
      planDays: parseInt(planDays, 10),
      maxDevices: parseInt(maxDevices, 10),
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      devices: []
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

    const newExpiresAt = new Date(baseDate.getTime() + (additionalDays * 24 * 60 * 60 * 1000));
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
  // FLUJO DE ACTIVACIÓN POR CÓDIGO (SMART TV Y MÓVIL)
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

    // 1. Verificar si este dispositivo ya está vinculado a un cliente existente por deviceId
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
          token: this._generateClientToken(client.id, cleanDeviceId)
        };
      }
    }

    // 2. Si no se encontró por deviceId pero la app o el usuario enviaron su código TV (ej: VJ-3166) o token de sesión:
    if (cleanCode || token) {
      for (const client of db.clients) {
        const matchesCode = cleanCode && (normalize(client.code) === cleanCode);
        let matchesToken = false;
        if (token && client.id) {
          const expectedToken = this._generateClientToken(client.id, cleanDeviceId);
          matchesToken = (token === expectedToken) || (token.startsWith(client.id));
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
            token: this._generateClientToken(client.id, cleanDeviceId)
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
          token: this._generateClientToken(client.id, cleanDeviceId)
        };
      }
    }

    // 4. Si es un dispositivo nuevo sin activar, buscar si ya tiene un código pendiente ACTIVO
    // Limpiar códigos pendientes con más de 24 horas de antigüedad
    db.pendingActivations = db.pendingActivations.filter(p => {
      const age = now - new Date(p.createdAt);
      return age < 24 * 60 * 60 * 1000;
    });

    let pending = db.pendingActivations.find(p => normalize(p.deviceId) === cleanDeviceId && p.status === 'pending');

    if (!pending) {
      // Generar código fácil de leer (ej: VJ-7429)
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
   * Consulta el estado de un código pendiente (polling cada 3 segundos desde la TV)
   */
  checkActivationStatus(code, deviceId) {
    const db = this._readDb();
    const pending = db.pendingActivations.find(p => p.code === code);

    if (!pending) {
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
          token: this._generateClientToken(client.id, deviceId)
        };
      }
    }

    return { status: 'pending', code: pending.code };
  }

  getPendingActivations() {
    const db = this._readDb();
    const now = new Date();
    // Solo pendientes en las últimas 24 horas
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
  activateCode(code, { name, planDays = 30, maxDevices = 1 }) {
    const db = this._readDb();
    const pending = db.pendingActivations.find(p => p.code === code && p.status === 'pending');

    if (!pending) {
      return { success: false, error: 'Código de activación no encontrado o ya utilizado.' };
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + (planDays * 24 * 60 * 60 * 1000));

    // Crear el nuevo cliente asociado al dispositivo que generó el código
    const newClient = {
      id: crypto.randomUUID(),
      name: name.trim(),
      username: name.toLowerCase().replace(/\s+/g, '_') + '_' + Math.floor(100 + Math.random() * 900),
      code: pending.code,
      status: 'active',
      planDays: parseInt(planDays, 10),
      maxDevices: parseInt(maxDevices, 10),
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
   * Valida la licencia en cada inicio de la app o reproducción
   */
  verifyLicense(deviceId) {
    const db = this._readDb();
    const now = new Date();

    for (const client of db.clients) {
      const dev = client.devices && client.devices.find(d => d.deviceId === deviceId);
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

    return { active: false, reason: 'unregistered', message: 'Dispositivo no registrado.' };
  }

  _generateClientToken(clientId, deviceId) {
    const data = `${clientId}:${deviceId}`;
    return crypto.createHmac('sha256', DEFAULT_ADMIN_PASSWORD).update(data).digest('hex');
  }
}

module.exports = new AccountService();
