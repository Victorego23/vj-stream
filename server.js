require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const streamingRoutes = require('./routes/streamingRoutes');
const authRoutes = require('./routes/authRoutes');
const adminRoutes = require('./routes/adminRoutes');
const resellerRoutes = require('./routes/resellerRoutes');
const catalogSyncService = require('./services/catalogSyncService');
const channelService = require('./services/channelService');

const app = express();
const PORT = process.env.PORT || 3000;

// Ocultar cabecera de fingerprinting de Express por seguridad
app.disable('x-powered-by');

// ====================================================================
// BLINDAJE DE SEGURIDAD Y MIDDLEWARES GLOBALES
// ====================================================================

// 1. Cabeceras de seguridad HTTP (Hardened Security Headers)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  if (req.secure || req.headers['x-forwarded-proto'] === 'https') {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }
  next();
});

// 2. Habilitar CORS para clientes frontend
app.use(cors());

// 3. Parseo de bodies con límites estrictos contra ataques DoS/Memory-Exhaustion
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// 4. Protección contra Prototype Pollution y caracteres maliciosos en JSON
app.use((req, res, next) => {
  if (req.body && typeof req.body === 'object') {
    const sanitize = (obj) => {
      for (const key of Object.keys(obj)) {
        if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
          delete obj[key];
        } else if (obj[key] && typeof obj[key] === 'object') {
          sanitize(obj[key]);
        }
      }
    };
    sanitize(req.body);
  }
  next();
});

// 5. Logger básico para peticiones entrantes
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${req.method} ${req.originalUrl}`);
  next();
});

// ====================================================================
// RUTAS DE LA APLICACIÓN
// ====================================================================

// Endpoint de verificación de estado y salud del servidor
app.get('/health', (req, res) => {
  res.json({
    app: 'TOM TV API',
    version: '3.0.0',
    status: 'ok',
    features: {
      antiCamFilter: true,
      spanishAudioPriority: true,
      forcedSpanishTMDB: true
    },
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    services: {
      realDebrid: Boolean(process.env.REALDEBRID_API_KEY),
      tmdb: Boolean(process.env.TMDB_API_KEY)
    }
  });
});

// Endpoints universales de versión OTA para máxima tolerancia de URLs
app.get('/version', (req, res) => {
  res.redirect('/api/streaming/version');
});
app.get('/api/version', (req, res) => {
  res.redirect('/api/streaming/version');
});

// URLs directas de release del APK para descarga inmediata sin saltos en Smart TV y navegadores
let currentApkDownloadUrl = 'https://github.com/Victorego23/vj-stream/releases/download/v4.1.0/TOM-TV-release.apk';

const updateLatestApkUrl = () => {
  try {
    const https = require('https');
    https.get('https://api.github.com/repos/Victorego23/vj-stream/releases/latest', {
      headers: { 'User-Agent': 'TOM-TV-Server' }
    }, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const apkAsset = json.assets && json.assets.find(a => a.name && a.name.endsWith('.apk'));
          if (apkAsset && apkAsset.browser_download_url) {
            currentApkDownloadUrl = apkAsset.browser_download_url;
          }
        } catch (_) {}
      });
    }).on('error', () => {});
  } catch (_) {}
};

// Actualizar periódicamente en background
setInterval(updateLatestApkUrl, 60 * 60 * 1000);
updateLatestApkUrl();

// Controlador unificado para servir el APK directamente sin redirecciones intermedias
const serveApkDirect = (req, res) => {
  if (req.query.source === 'local') {
    const fs = require('fs');
    const tomReleasePath = path.resolve(__dirname, 'TOM-TV-release.apk');
    if (fs.existsSync(tomReleasePath)) {
      const stat = fs.statSync(tomReleasePath);
      res.setHeader('Content-Type', 'application/vnd.android.package-archive');
      res.setHeader('Content-Length', stat.size);
      res.setHeader('Content-Disposition', 'attachment; filename="TOM-TV.apk"');
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      return res.sendFile(tomReleasePath);
    }
  }

  // Redirigir directamente al binario de release sin pasar por el resolve intermedio de /latest/
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  return res.redirect(302, currentApkDownloadUrl);
};

// Endpoints universales directos de descarga de APK (200 OK directo para Downloader TV y Navegadores)
app.get(['/download-apk', '/api/download-apk', '/apk', '/tv'], serveApkDirect);

// Endpoints universales de lista M3U para Smart TV / IBO Player / IPTV Smarters
app.get('/playlist.m3u', (req, res) => {
  const query = req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : '';
  res.redirect(`/api/streaming/playlist.m3u${query}`);
});
app.get('/m3u', (req, res) => {
  const query = req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : '';
  res.redirect(`/api/streaming/playlist.m3u${query}`);
});
app.get('/get.php', (req, res) => {
  const query = req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : '';
  res.redirect(`/api/streaming/playlist.m3u${query}`);
});

// Servir archivos estáticos de la Web App / PWA pública
app.use(express.static(path.join(__dirname, 'public')));

// Servir la Landing Page oficial de TOM TV en la raíz
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Servir el Reproductor Web / PWA oficial de TOM TV
app.get(['/play', '/web', '/app'], (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'play.html'));
});

// Servir el Panel de Administrador Web
app.get('/admin', (req, res) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Servir el Sub-Panel para Revendedores Web
app.get(['/reseller', '/revendedor', '/distribuidor', '/revendedores'], (req, res) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.sendFile(path.join(__dirname, 'public', 'reseller.html'));
});

// Servir el Simulador y Vista Previa Móvil interactiva
app.get(['/mobile-preview', '/preview', '/celular', '/movil'], (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'mobile-preview.html'));
});

// Rutas de autenticación de dispositivos y licencias
app.use('/api/auth', authRoutes);

// Rutas del Panel de Administrador Master
app.use('/api/admin', adminRoutes);

// Rutas del Sub-Panel de Revendedores y Gestión de Créditos
app.use('/api/reseller', resellerRoutes);

// Montaje de las rutas modulares de streaming con soporte dual (/api y /api/streaming)
app.use('/api/streaming', streamingRoutes);
app.use('/api', streamingRoutes);

// Manejador para rutas no encontradas (404)
app.use((req, res, next) => {
  res.status(404).json({
    success: false,
    error: `Ruta no encontrada en VJ STREAM API: ${req.method} ${req.originalUrl}`
  });
});

// ====================================================================
// MANEJADOR CENTRALIZADO DE ERRORES
// ====================================================================
app.use((err, req, res, next) => {
  const statusCode = err.statusCode || err.status || 500;
  console.error(`[VJ STREAM ERROR] [${statusCode}] ${err.message}`);

  if (process.env.NODE_ENV !== 'production' && err.stack) {
    console.error(err.stack);
  }

  res.status(statusCode).json({
    success: false,
    app: 'TOM TV',
    error: err.message || 'Error interno del servidor',
    ...(process.env.NODE_ENV !== 'production' && { details: err.originalError?.response?.data || null })
  });
});

// ====================================================================
// INICIALIZACIÓN DEL SERVIDOR
// ====================================================================
const server = app.listen(PORT, () => {
  console.log(`====================================================`);
  console.log(`🔥 TOM TV - Servidor Backend Premium Iniciado`);
  console.log(`🛡️  Filtro Anti-CAM: ACTIVO (CAM, TS, HDCAM descartados)`);
  console.log(`🇪🇸 Audio en Español: PRIORIDAD MÁXIMA (Latino / Castellano)`);
  console.log(`📡 URL local: http://localhost:${PORT}`);
  console.log(`🩺 Health check: http://localhost:${PORT}/health`);
  console.log(`🎬 API Endpoints: http://localhost:${PORT}/api/streaming`);
  console.log(`====================================================`);

  // Iniciar motor autónomo de actualización continua del catálogo
  catalogSyncService.startBackgroundWorker();

  // Iniciar monitor autónomo de canales de TV en vivo 24/7 (Auditoría continua cada 6h)
  channelService.startBackgroundMonitor(6);

  // Iniciar base de datos masiva de películas e ingesta programada (50,000+ títulos)
  const movieDatabaseService = require('./services/movieDatabaseService');
  const movieIngestionService = require('./services/movieIngestionService');
  movieDatabaseService.init().then(() => {
    movieIngestionService.startScheduledSync();
  }).catch(err => {
    console.warn('[Server] Advertencia al iniciar MovieDatabaseService:', err.message);
  });
});

// ====================================================================
// SERVICIO DE AUTODESCUBRIMIENTO LAN (UDP BROADCAST)
// ====================================================================
const dgram = require('dgram');
const udpServer = dgram.createSocket('udp4');

udpServer.on('message', (msg, rinfo) => {
  const messageStr = msg.toString();
  if (messageStr.includes('TOM_TV_PING') || messageStr.includes('VJ_STREAM_PING') || messageStr.includes('DISCOVER_VJ_STREAM')) {
    const response = JSON.stringify({
      app: 'TOM TV',
      port: PORT,
      version: '3.0.0'
    });
    udpServer.send(response, rinfo.port, rinfo.address, (err) => {
      if (err) console.error('[UDP Discovery] Error respondiendo ping:', err);
    });
  }
});

udpServer.on('error', (err) => {
  console.warn('[UDP Discovery] Advertencia socket UDP:', err.message);
});

try {
  udpServer.bind(3001, () => {
    console.log(`📡 Baliza de autodescubrimiento LAN activa en puerto UDP 3001`);
  });
} catch (e) {
  console.warn('[UDP Discovery] Socket no disponible:', e.message);
}

// Manejo elegante de cierres y errores no capturados
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection detectado:', reason);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception detectado:', err);
  process.exit(1);
});

module.exports = { app, server };
