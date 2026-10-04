/**
 * Middleware ligero de Rate Limiting en memoria para protección contra ataques de fuerza bruta.
 * No requiere paquetes externos y protege endpoints críticos como Login y Activación.
 */

function createRateLimiter(options = {}) {
  const windowMs = options.windowMs || 10 * 60 * 1000; // 10 minutos por defecto
  const maxAttempts = options.max || 5;                // 5 intentos permitidos
  const message = options.message || 'Demasiados intentos fallidos. Por favor espera unos minutos antes de volver a intentar.';

  // Almacén en memoria: ip -> { count, resetTime }
  const store = new Map();

  // Limpieza periódica cada 5 minutos de registros expirados para no consumir memoria
  setInterval(() => {
    const now = Date.now();
    for (const [key, record] of store.entries()) {
      if (record.resetTime <= now) {
        store.delete(key);
      }
    }
  }, 5 * 60 * 1000).unref();

  return function rateLimiter(req, res, next) {
    const ip = req.ip || req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
    const now = Date.now();

    let record = store.get(ip);
    if (!record || record.resetTime <= now) {
      record = { count: 0, resetTime: now + windowMs };
      store.set(ip, record);
    }

    if (record.count >= maxAttempts) {
      const remainingSeconds = Math.ceil((record.resetTime - now) / 1000);
      return res.status(429).json({
        success: false,
        error: message,
        retryAfterSeconds: remainingSeconds
      });
    }

    // Interceptar la respuesta para contar solo intentos fallidos si se especifica
    const originalJson = res.json.bind(res);
    res.json = function (body) {
      // Si la respuesta no es exitosa (código 400, 401, 403 o success: false), sumamos un intento
      if (res.statusCode >= 400 || (body && body.success === false)) {
        record.count++;
      } else if (res.statusCode === 200 && body && body.success === true) {
        // En caso de éxito, reseteamos el contador de la IP
        store.delete(ip);
      }
      return originalJson(body);
    };

    next();
  };
}

module.exports = {
  createRateLimiter,
  loginRateLimiter: createRateLimiter({
    windowMs: 15 * 60 * 1000,
    max: 6,
    message: 'Has superado el límite de intentos de inicio de sesión. Bloqueado temporalmente por 15 minutos.'
  })
};
