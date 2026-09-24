const crypto = require('crypto');

// Clave secreta compartida entre el backend y la app oficial VJ STREAM
const HMAC_SECRET = process.env.API_SIGNATURE_SECRET || 'VJ_SECURE_STREAM_APP_SIG_KEY_2026_@#!';

/**
 * Middleware de seguridad HMAC-SHA256.
 * Impide que navegadores externos, scrapers, bots o herramientas como Postman
 * consuman los endpoints de streaming y agoten la cuenta de Real-Debrid.
 */
function hmacSecurityMiddleware(req, res, next) {
  // Si en desarrollo se desea deshabilitar temporalmente
  if (process.env.DISABLE_HMAC_SECURITY === 'true') {
    return next();
  }

  // Rutas públicas exentas de firma (OTA Version, descarga directa del instalador, health check)
  const path = req.path || '';
  const publicEndpoints = ['/version', '/download-apk', '/health'];
  const isPublic = publicEndpoints.some(p => path.endsWith(p));

  if (isPublic) {
    return next();
  }

  const timestamp = req.headers['x-vj-timestamp'];
  const signature = req.headers['x-vj-signature'];

  if (!timestamp || !signature) {
    return res.status(403).json({
      success: false,
      app: 'VJ STREAM',
      error: 'Acceso Restringido: Esta API solo responde a la aplicación oficial VJ STREAM.'
    });
  }

  // 1. Protección Anti-Replay: Ventana de validez máxima de 5 minutos (300 segundos)
  const now = Math.floor(Date.now() / 1000);
  const reqTime = parseInt(timestamp, 10);

  if (isNaN(reqTime) || Math.abs(now - reqTime) > 300) {
    return res.status(403).json({
      success: false,
      app: 'VJ STREAM',
      error: 'Firma de seguridad caducada. Por favor sincroniza la hora de tu dispositivo.'
    });
  }

  // 2. Comprobación de firma criptográfica
  // Probamos la ruta completa (ej: /api/streaming/auto-resolve) y la ruta relativa (ej: /auto-resolve)
  const fullPath = (req.originalUrl ? req.originalUrl.split('?')[0] : path).toLowerCase();
  const relativePath = path.toLowerCase();

  const candidates = [
    `${timestamp}:${fullPath}`,
    `${timestamp}:${relativePath}`,
    `${timestamp}:/api/streaming${relativePath}`
  ];

  let isValid = false;

  for (const candidate of candidates) {
    const expected = crypto
      .createHmac('sha256', HMAC_SECRET)
      .update(candidate)
      .digest('hex');

    if (expected.length === signature.length) {
      if (crypto.timingSafeEqual(Buffer.from(expected, 'utf8'), Buffer.from(signature, 'utf8'))) {
        isValid = true;
        break;
      }
    }
  }

  if (!isValid) {
    return res.status(403).json({
      success: false,
      app: 'VJ STREAM',
      error: 'Firma criptográfica inválida. Solicitud externa no autorizada.'
    });
  }

  next();
}

module.exports = hmacSecurityMiddleware;
