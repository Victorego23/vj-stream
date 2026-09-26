require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const streamingRoutes = require('./routes/streamingRoutes');
const authRoutes = require('./routes/authRoutes');
const adminRoutes = require('./routes/adminRoutes');

const app = express();
const PORT = process.env.PORT || 3000;

// ====================================================================
// CONFIGURACIÓN DE MIDDLEWARES GLOBALES
// ====================================================================

// Habilitar CORS para permitir solicitudes desde clientes frontend
app.use(cors());

// Parseo de bodies en formato JSON y URL-Encoded
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Logger básico para peticiones entrantes en modo desarrollo
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
    app: 'VJ STREAM API',
    version: '2.0.0',
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

// Endpoints universales directos de descarga de APK
app.get('/download-apk', (req, res) => {
  res.redirect('/api/streaming/download-apk');
});
app.get('/api/download-apk', (req, res) => {
  res.redirect('/api/streaming/download-apk');
});

// Servir archivos estáticos de la Web App / PWA pública
app.use(express.static(path.join(__dirname, 'public')));

// Servir la Web App / PWA oficial de VJ STREAM en la raíz
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Servir el Panel de Administrador Web
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Rutas de autenticación de dispositivos y licencias
app.use('/api/auth', authRoutes);

// Rutas del Panel de Administrador
app.use('/api/admin', adminRoutes);

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
    app: 'VJ STREAM',
    error: err.message || 'Error interno del servidor',
    ...(process.env.NODE_ENV !== 'production' && { details: err.originalError?.response?.data || null })
  });
});

// ====================================================================
// INICIALIZACIÓN DEL SERVIDOR
// ====================================================================
const server = app.listen(PORT, () => {
  console.log(`====================================================`);
  console.log(`🔥 VJ STREAM - Servidor Backend Premium Iniciado`);
  console.log(`🛡️  Filtro Anti-CAM: ACTIVO (CAM, TS, HDCAM descartados)`);
  console.log(`🇪🇸 Audio en Español: PRIORIDAD MÁXIMA (Latino / Castellano)`);
  console.log(`📡 URL local: http://localhost:${PORT}`);
  console.log(`🩺 Health check: http://localhost:${PORT}/health`);
  console.log(`🎬 API Endpoints: http://localhost:${PORT}/api/streaming`);
  console.log(`====================================================`);
});

// ====================================================================
// SERVICIO DE AUTODESCUBRIMIENTO LAN (UDP BROADCAST)
// ====================================================================
const dgram = require('dgram');
const udpServer = dgram.createSocket('udp4');

udpServer.on('message', (msg, rinfo) => {
  const messageStr = msg.toString();
  if (messageStr.includes('VJ_STREAM_PING') || messageStr.includes('DISCOVER_VJ_STREAM')) {
    const response = JSON.stringify({
      app: 'VJ STREAM',
      port: PORT,
      version: '2.2.6'
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
