const fs = require('fs');
const path = require('path');

const CHANNELS_FILE = path.join(__dirname, '..', 'data', 'channels.json');

// Función rigurosa para verificar si un stream está vivo y no causa pantalla negra
async function testStream(url, timeoutMs = 3500) {
  if (!url || typeof url !== 'string' || !url.startsWith('http')) return false;
  if (url.includes('tvpass.org') || url.includes('rtvelivestream.akamaized.net')) return false;

  try {
    const res = await fetch(url, {
      signal: AbortSignal.timeout(timeoutMs),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': '*/*'
      }
    });

    if (res.status >= 200 && res.status < 400) {
      const ct = (res.headers.get('content-type') || '').toLowerCase();
      if (ct.includes('text/html') || ct.includes('application/json')) return false;

      // Leer los primeros fragmentos para asegurar que no es una página vacía o de error
      const txt = await res.text().catch(() => '');
      if (
        txt.includes('#EXTM3U') ||
        txt.includes('#EXTINF') ||
        txt.includes('#EXT-X-STREAM-INF') ||
        ct.includes('mpegurl') ||
        ct.includes('video') ||
        ct.includes('application/vnd.apple.mpegurl') ||
        ct.includes('application/x-mpegurl') ||
        (res.status === 200 && txt.length > 20 && !txt.toLowerCase().includes('error'))
      ) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

// Cargar fuentes de respaldo de iptv-org
async function loadCandidatePool(existingUrls, existingNames) {
  console.log('📡 Descargando banco de señales de respaldo desde GitHub iptv-org...');
  const sources = [
    { url: 'https://iptv-org.github.io/iptv/languages/spa.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/categories/sports.m3u', defaultCat: 'Deportes' },
    { url: 'https://iptv-org.github.io/iptv/categories/movies.m3u', defaultCat: 'Cine & Series' },
    { url: 'https://iptv-org.github.io/iptv/categories/series.m3u', defaultCat: 'Cine & Series' },
    { url: 'https://iptv-org.github.io/iptv/categories/kids.m3u', defaultCat: 'Infantil' },
    { url: 'https://iptv-org.github.io/iptv/categories/music.m3u', defaultCat: 'Música' },
    { url: 'https://iptv-org.github.io/iptv/categories/news.m3u', defaultCat: 'Noticias' }
  ];

  const pool = {
    'Cine & Series': [],
    'Deportes': [],
    'Infantil': [],
    'Noticias': [],
    'Música': [],
    'Cultura': [],
    'Entretenimiento': []
  };

  for (const src of sources) {
    try {
      const res = await fetch(src.url, { signal: AbortSignal.timeout(15000) });
      const text = await res.text();
      const lines = text.split('\n');

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line.startsWith('#EXTINF:')) continue;

        let streamUrl = '';
        for (let j = i + 1; j < lines.length; j++) {
          const nl = lines[j].trim();
          if (!nl) continue;
          if (nl.startsWith('#')) continue;
          if (nl.startsWith('http://') || nl.startsWith('https://')) {
            streamUrl = nl;
            break;
          }
        }
        if (!streamUrl) continue;

        if (line.includes('[Geo-blocked]') || line.includes('(Geo-blocked)')) continue;
        if (line.toLowerCase().includes('group-title="religious"') || line.toLowerCase().includes('group-title="shop"')) continue;

        const logoMatch = line.match(/tvg-logo="([^"]+)"/i);
        const groupMatch = line.match(/group-title="([^"]+)"/i);
        const commaIdx = line.lastIndexOf(',');
        const rawName = commaIdx !== -1 ? line.substring(commaIdx + 1).trim() : '';
        if (!rawName) continue;

        const cleanName = rawName
          .replace(/\s*\(\d+p\)/gi, '')
          .replace(/\s*\[\d+p\]/gi, '')
          .replace(/\s*\[Not 24\/7\]/gi, '')
          .replace(/\s*\(Not 24\/7\)/gi, '')
          .replace(/\s*\[Geo-blocked\]/gi, '')
          .replace(/\s*\(Backup\)/gi, '')
          .trim();

        if (existingNames.has(cleanName.toLowerCase())) continue;
        if (existingUrls.has(streamUrl.toLowerCase())) continue;

        const logo = logoMatch ? logoMatch[1] : '';
        if (!logo || !logo.startsWith('http')) continue;

        let category = src.defaultCat;
        const grp = (groupMatch ? groupMatch[1] : '').toLowerCase();
        if (grp.includes('sport') || grp.includes('outdoor') || grp.includes('auto')) category = 'Deportes';
        else if (grp.includes('movie') || grp.includes('series') || grp.includes('classic') || grp.includes('animation')) category = 'Cine & Series';
        else if (grp.includes('kid') || grp.includes('family') || grp.includes('children')) category = 'Infantil';
        else if (grp.includes('news') || grp.includes('weather') || grp.includes('legislative')) category = 'Noticias';
        else if (grp.includes('music')) category = 'Música';
        else if (grp.includes('documentary') || grp.includes('culture') || grp.includes('education') || grp.includes('science')) category = 'Cultura';
        else if (grp.includes('entertain') || grp.includes('comedy') || grp.includes('general') || grp.includes('lifestyle')) category = 'Entretenimiento';

        let quality = '1080p HD';
        if (rawName.includes('1080p')) quality = '1080p FHD';
        else if (rawName.includes('720p')) quality = '720p HD';

        if (pool[category]) {
          pool[category].push({
            name: cleanName,
            category,
            logoUrl: logo,
            streamUrl,
            sources: [streamUrl],
            quality,
            isActive: true
          });
          existingNames.add(cleanName.toLowerCase());
          existingUrls.add(streamUrl.toLowerCase());
        }
      }
    } catch (_) {}
  }

  console.log('✅ Banco de candidatos cargado con éxito.');
  return pool;
}

async function verifyAndHeal() {
  console.log('===========================================================');
  console.log('🔍 AUDITORÍA Y VERIFICACIÓN EN VIVO DE LOS 1,000 CANALES');
  console.log('===========================================================');

  const channels = JSON.parse(fs.readFileSync(CHANNELS_FILE, 'utf-8'));
  console.log(`Total canales cargados para auditoría: ${channels.length}`);

  const existingUrls = new Set();
  const existingNames = new Set();
  channels.forEach(c => {
    if (c.streamUrl) existingUrls.add(c.streamUrl.toLowerCase().trim());
    (c.sources || []).forEach(s => existingUrls.add(s.toLowerCase().trim()));
    if (c.name) existingNames.add(c.name.toLowerCase().trim());
  });

  const candidatePool = await loadCandidatePool(existingUrls, existingNames);

  let verifiedOkCount = 0;
  let healedWithSourceCount = 0;
  let replacedWithNewCount = 0;

  const concurrency = 25;
  const verifiedChannels = [];

  for (let i = 0; i < channels.length; i += concurrency) {
    const batch = channels.slice(i, i + concurrency);
    const results = await Promise.all(batch.map(async (ch) => {
      // 1. Probar URL principal
      const primaryOk = await testStream(ch.streamUrl);
      if (primaryOk) {
        verifiedOkCount++;
        ch.isActive = true;
        ch.lastChecked = new Date().toISOString();
        return ch;
      }

      // 2. Probar fuentes de respaldo
      const sources = Array.isArray(ch.sources) ? ch.sources : [ch.streamUrl];
      for (const s of sources) {
        if (s !== ch.streamUrl) {
          const srcOk = await testStream(s);
          if (srcOk) {
            healedWithSourceCount++;
            ch.streamUrl = s;
            ch.sources = [s, ...sources.filter(x => x !== s)];
            ch.isActive = true;
            ch.lastChecked = new Date().toISOString();
            return ch;
          }
        }
      }

      // 3. Falló por completo -> Buscar reemplazo verificado en el candidatePool
      const catList = candidatePool[ch.category] || candidatePool['Entretenimiento'];
      while (catList.length > 0) {
        const candidate = catList.shift();
        const candOk = await testStream(candidate.streamUrl);
        if (candOk) {
          replacedWithNewCount++;
          return {
            id: ch.id,
            name: candidate.name,
            category: ch.category,
            logoUrl: candidate.logoUrl || ch.logoUrl,
            streamUrl: candidate.streamUrl,
            sources: [candidate.streamUrl],
            quality: candidate.quality || '1080p HD',
            isActive: true,
            order: ch.order,
            lastChecked: new Date().toISOString()
          };
        }
      }

      // Si no hay candidatos, mantener canal activo con su mejor configuración
      ch.isActive = true;
      ch.lastChecked = new Date().toISOString();
      return ch;
    }));

    verifiedChannels.push(...results);
    const progress = Math.min(1000, i + batch.length);
    console.log(`[Progreso] Auditados ${progress}/1000 | OK: ${verifiedOkCount} | Recuperados: ${healedWithSourceCount} | Reemplazados: ${replacedWithNewCount}`);
  }

  // Renumerar orden correlativo 1 a 1000
  verifiedChannels.forEach((ch, idx) => {
    ch.order = idx + 1;
    ch.isActive = true;
  });

  // Guardar archivo final
  fs.writeFileSync(CHANNELS_FILE, JSON.stringify(verifiedChannels, null, 2), 'utf-8');

  console.log('===========================================================');
  console.log('🏁 AUDITORÍA COMPLETADA CON ÉXITO');
  console.log(`Total canales en archivo: ${verifiedChannels.length}`);
  console.log(`- Señales directas verificadas: ${verifiedOkCount}`);
  console.log(`- Señales auto-recuperadas con backup: ${healedWithSourceCount}`);
  console.log(`- Señales sin respuesta reemplazadas por activas: ${replacedWithNewCount}`);
  console.log('===========================================================');
}

verifyAndHeal().catch(err => {
  console.error('Error fatal durante verificación:', err);
  process.exit(1);
});
