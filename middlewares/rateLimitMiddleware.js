/**
 * Middleware ligero y de alto rendimiento de Rate Limiting y Blindaje en memoria.
 * Protege endpoints críticos contra ataques de fuerza bruta, enumeración de códigos y DoS.
 */

function createRateLimiter(options = {}) {
  const windowMs = options.windowMs || 10 * 60 * 1000;
  const maxAttempts = options.max || 5;
  const message = options.message || 'Demasiados intentos. Por favor espera unos minutos antes de volver a intentar.';
  const countAll = options.countAll || false; // Si true, cuenta todas las peticiones, no solo errores

  // Almacén en memoria: ip -> { count, resetTime }
  const store = new Map();

  // Limpieza periódica cada 3 minutos de registros expirados para no consumir memoria
  setInterval(() => {
    const now = Date.now();
    for (const [key, record] of store.entries()) {
      if (record.resetTime <= now) {
        store.delete(key);
      }
    }
  }, 3 * 60 * 1000).unref();

  return function rateLimiter(req, res, next) {
    const rawIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || req.ip || 'unknown';
    const ip = String(rawIp).split(',')[0].trim();
    const now = Date.now();

    let record = store.get(ip);
    if (!record || record.resetTime <= now) {
      record = { count: 0, resetTime: now + windowMs };
      store.set(ip, record);
    }

    if (record.count >= maxAttempts) {
      const remainingSeconds = Math.ceil((record.resetTime - now) / 1000);
      res.setHeader('Retry-After', remainingSeconds);
      return res.status(429).json({
        success: false,
        error: message,
        retryAfterSeconds: remainingSeconds
      });
    }

    if (countAll) {
      record.count++;
      return next();
    }

    // Interceptar la respuesta para contar solo intentos fallidos
    const originalJson = res.json.bind(res);
    res.json = function (body) {
      if (res.statusCode >= 400 || (body && body.success === false)) {
        record.count++;
      } else if (res.statusCode === 200 && body && body.success === true) {
        // En login exitoso reducimos o limpiamos
        store.delete(ip);
      }
      return originalJson(body);
    };

    next();
  };
}

module.exports = {
  createRateLimiter,

  // Blindaje 1: Login de Administrador (Máx 6 intentos erróneos cada 15 min)
  adminLoginLimiter: createRateLimiter({
    windowMs: 15 * 60 * 1000,
    max: 6,
    message: '⛔ Has superado el límite de intentos de acceso al Panel. Por seguridad, espera 15 minutos.'
  }),

  // Blindaje 2: Login de Revendedores (Máx 8 intentos erróneos cada 10 min)
  loginRateLimiter: createRateLimiter({
    windowMs: 10 * 60 * 1000,
    max: 8,
    message: 'Demasiados intentos fallidos de inicio de sesión. Por favor espera 10 minutos.'
  }),

  // Blindaje 3: Activación y Verificación de Licencia (Anti-Brute Force de códigos TOM-XXXX)
  activationLimiter: createRateLimiter({
    windowMs: 5 * 60 * 1000,
    max: 12,
    message: 'Demasiadas solicitudes de activación erróneas. Por favor espera 5 minutos.'
  }),

  // Blindaje 4: Solicitud de Demos Gratuitas (Máx 4 por IP cada 2 horas para evitar abusos)
  demoLimiter: createRateLimiter({
    windowMs: 2 * 60 * 60 * 1000,
    max: 4,
    countAll: true,
    message: 'Has alcanzado el límite de solicitudes de pruebas demo por hoy para tu conexión.'
  }),

  // Blindaje 5: Consulta de Radar en Espera (Anti-Spam Polling)
  statusPollLimiter: createRateLimiter({
    windowMs: 1 * 60 * 1000,
    max: 45,
    countAll: true,
    message: 'Demasiadas consultas de estado continuas. Espera un momento.'
  })
};
