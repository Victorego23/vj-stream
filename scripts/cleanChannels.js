const fs = require('fs');
const path = require('path');

const CHANNELS_FILE = path.join(__dirname, '..', 'data', 'channels.json');
const BACKUP_FILE = path.join(__dirname, '..', 'data', 'channels.backup.json');

const CONCURRENCY = 30; // 30 verificaciones concurrentes
const TIMEOUT_MS = 4000; // 4.0 segundos para dar margen a CDNs internacionales

/**
 * Prueba con alta velocidad si una URL de streaming M3U8 responde con señal activa de video.
 */
async function testStream(url) {
  if (!url || typeof url !== 'string' || !url.startsWith('http')) return false;

  // Descartar dominios conocidos que están permanentemente caídos o muertos
  if (url.includes('tvpass.org') || url.includes('rtvelivestream.akamaized.net')) {
    return false;
  }

  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': '*/*'
      }
    });

    if (res.status >= 200 && res.status < 400) {
      const ct = (res.headers.get('content-type') || '').toLowerCase();
      // Si responde con HTML o JSON de error, no es un stream válido
      if (ct.includes('text/html') || ct.includes('application/json')) return false;

      const txt = await res.text().catch(() => '');
      if (
        txt.includes('#EXTM3U') || 
        txt.includes('#EXTINF') || 
        ct.includes('mpegurl') || 
        ct.includes('video') || 
        ct.includes('application/vnd.apple.mpegurl') ||
        ct.includes('application/x-mpegurl') ||
        (res.status === 200 && txt.length > 20 && !txt.toLowerCase().includes('error') && !txt.toLowerCase().includes('forbidden'))
      ) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

async function cleanChannels() {
  console.log('====================================================');
  console.log('📺 VJ STREAM - Depurador y Auditor de Canales en Vivo');
  console.log('====================================================');

  if (!fs.existsSync(CHANNELS_FILE)) {
    console.error('❌ No se encontró channels.json');
    return;
  }

  const raw = fs.readFileSync(CHANNELS_FILE, 'utf8');
  const allChannels = JSON.parse(raw);
  console.log(`📡 Canales cargados para auditar: ${allChannels.length}`);

  // 1. Guardar copia de respaldo si no existe ya
  if (!fs.existsSync(BACKUP_FILE)) {
    fs.writeFileSync(BACKUP_FILE, raw, 'utf8');
    console.log(`💾 Respaldo de seguridad creado en: ${BACKUP_FILE}`);
  }

  const activeChannels = [];
  let deadCount = 0;
  let processed = 0;

  for (let i = 0; i < allChannels.length; i += CONCURRENCY) {
    const chunk = allChannels.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      chunk.map(async (ch) => {
        const sources = Array.isArray(ch.sources) && ch.sources.length > 0 ? ch.sources : [ch.streamUrl];
        let workingUrl = null;

        for (const src of sources) {
          const isWorking = await testStream(src);
          if (isWorking) {
            workingUrl = src;
            break;
          }
        }

        return { channel: ch, workingUrl };
      })
    );

    for (const r of results) {
      processed++;
      if (r.workingUrl) {
        const reorderedSources = [
          r.workingUrl,
          ...(Array.isArray(r.channel.sources) ? r.channel.sources.filter(s => s !== r.workingUrl) : [])
        ];
        activeChannels.push({
          ...r.channel,
          streamUrl: r.workingUrl,
          sources: reorderedSources,
          isActive: true,
          order: activeChannels.length + 1
        });
      } else {
        deadCount++;
      }
    }

    const pct = Math.round((processed / allChannels.length) * 100);
    console.log(`⏳ [${pct}%] Auditados: ${processed}/${allChannels.length} | ✅ Funcionales: ${activeChannels.length} | ❌ Eliminados: ${deadCount}`);
  }

  console.log('\n====================================================');
  console.log(`✅ Auditoría finalizada con éxito.`);
  console.log(`🎯 Canales con señal 100% activa conservados: ${activeChannels.length}`);
  console.log(`🗑️ Canales sin señal eliminados permanentemente: ${deadCount}`);

  // Desglose por categorías
  const categories = {};
  activeChannels.forEach(c => {
    const cat = c.category || 'Entretenimiento';
    categories[cat] = (categories[cat] || 0) + 1;
  });
  console.log('\n📊 Resumen de canales funcionales por categoría:');
  console.table(categories);

  // 2. Guardar lista depurada y limpia
  fs.writeFileSync(CHANNELS_FILE, JSON.stringify(activeChannels, null, 2), 'utf8');
  console.log(`\n💾 Archivo data/channels.json actualizado con canales 100% operativos.`);
  console.log('====================================================');
}

cleanChannels().catch(err => console.error('Error:', err));
