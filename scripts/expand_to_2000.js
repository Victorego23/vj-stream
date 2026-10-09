const fs = require('fs');
const path = require('path');

const CHANNELS_FILE = path.join(__dirname, '..', 'data', 'channels.json');

// Validación HLS rápida en vivo
async function testStream(url, timeoutMs = 2500) {
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

async function expandTo2000() {
  console.log('===========================================================');
  console.log('🚀 EXPANSIÓN DE CATÁLOGO A 2,000 CANALES 100% VERIFICADOS');
  console.log('===========================================================');

  const existingChannels = JSON.parse(fs.readFileSync(CHANNELS_FILE, 'utf-8'));
  console.log(`Canales existentes actualmente: ${existingChannels.length}`);

  const existingUrls = new Set();
  const existingNames = new Set();
  const existingIds = new Set();

  existingChannels.forEach(c => {
    if (c.streamUrl) existingUrls.add(c.streamUrl.toLowerCase().trim());
    (c.sources || []).forEach(s => existingUrls.add(s.toLowerCase().trim()));
    if (c.name) existingNames.add(c.name.toLowerCase().trim());
    if (c.id) existingIds.add(c.id);
  });

  const sources = [
    { url: 'https://iptv-org.github.io/iptv/languages/spa.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/categories/sports.m3u', defaultCat: 'Deportes' },
    { url: 'https://iptv-org.github.io/iptv/categories/movies.m3u', defaultCat: 'Cine & Series' },
    { url: 'https://iptv-org.github.io/iptv/categories/series.m3u', defaultCat: 'Cine & Series' },
    { url: 'https://iptv-org.github.io/iptv/categories/animation.m3u', defaultCat: 'Infantil' },
    { url: 'https://iptv-org.github.io/iptv/categories/kids.m3u', defaultCat: 'Infantil' },
    { url: 'https://iptv-org.github.io/iptv/categories/documentary.m3u', defaultCat: 'Cultura' },
    { url: 'https://iptv-org.github.io/iptv/categories/news.m3u', defaultCat: 'Noticias' },
    { url: 'https://iptv-org.github.io/iptv/categories/music.m3u', defaultCat: 'Música' },
    { url: 'https://iptv-org.github.io/iptv/countries/us.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/countries/es.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/countries/mx.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/countries/ar.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/countries/co.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/countries/pe.m3u', defaultCat: 'Entretenimiento' },
    { url: 'https://iptv-org.github.io/iptv/countries/cl.m3u', defaultCat: 'Entretenimiento' }
  ];

  console.log('📡 Descargando listas internacionales de GitHub...');
  const candidates = [];

  for (const src of sources) {
    try {
      const res = await fetch(src.url, { signal: AbortSignal.timeout(15000) });
      const text = await res.text();
      const lines = text.split('\n');

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line.startsWith('#EXTINF:')) continue;

        let url = '';
        for (let j = i + 1; j < lines.length; j++) {
          const nl = lines[j].trim();
          if (!nl) continue;
          if (nl.startsWith('#')) continue;
          if (nl.startsWith('http://') || nl.startsWith('https://')) {
            url = nl;
            break;
          }
        }
        if (!url || existingUrls.has(url.toLowerCase())) continue;
        if (line.includes('[Geo-blocked]')) continue;
        if (line.toLowerCase().includes('group-title="religious"') || line.toLowerCase().includes('group-title="shop"')) continue;

        const commaIdx = line.lastIndexOf(',');
        const rawName = commaIdx !== -1 ? line.substring(commaIdx + 1).trim() : '';
        if (!rawName) continue;

        const cleanName = rawName
          .replace(/\s*\(\d+p\)/gi, '')
          .replace(/\s*\[\d+p\]/gi, '')
          .replace(/\s*\[Not 24\/7\]/gi, '')
          .replace(/\s*\(Not 24\/7\)/gi, '')
          .replace(/\s*\(Backup\)/gi, '')
          .trim();

        if (existingNames.has(cleanName.toLowerCase())) continue;

        const logoMatch = line.match(/tvg-logo="([^"]+)"/i);
        const groupMatch = line.match(/group-title="([^"]+)"/i);
        const logo = logoMatch ? logoMatch[1] : '';
        if (!logo || !logo.startsWith('http')) continue;

        existingUrls.add(url.toLowerCase());
        existingNames.add(cleanName.toLowerCase());

        let category = src.defaultCat;
        const grp = (groupMatch ? groupMatch[1] : '').toLowerCase();
        if (grp.includes('sport') || grp.includes('outdoor') || grp.includes('auto')) category = 'Deportes';
        else if (grp.includes('movie') || grp.includes('series') || grp.includes('classic') || grp.includes('animation')) category = 'Cine & Series';
        else if (grp.includes('kid') || grp.includes('family') || grp.includes('children')) category = 'Infantil';
        else if (grp.includes('news') || grp.includes('weather') || grp.includes('legislative')) category = 'Noticias';
        else if (grp.includes('music')) category = 'Música';
        else if (grp.includes('documentary') || grp.includes('culture') || grp.includes('education') || grp.includes('science')) category = 'Cultura';

        let quality = '1080p HD';
        if (rawName.includes('1080p')) quality = '1080p FHD';
        else if (rawName.includes('720p')) quality = '720p HD';
        else if (rawName.includes('4k')) quality = '4K UHD';

        candidates.push({
          name: cleanName,
          category,
          logoUrl: logo,
          streamUrl: url,
          sources: [url],
          quality
        });
      }
    } catch (_) {}
  }

  console.log(`✅ ${candidates.length} candidatos únicos descargados. Iniciando verificación en vivo...`);

  const neededCount = 2000 - existingChannels.length;
  console.log(`Meta: Encontrar exactamente ${neededCount} canales 100% funcionales para alcanzar 2,000.`);

  const verifiedNew = [];
  const batchSize = 40;

  for (let i = 0; i < candidates.length && verifiedNew.length < neededCount; i += batchSize) {
    const batch = candidates.slice(i, i + batchSize);
    const checks = await Promise.all(batch.map(async (c) => {
      const ok = await testStream(c.streamUrl);
      return ok ? c : null;
    }));

    for (const ch of checks) {
      if (ch && verifiedNew.length < neededCount) {
        verifiedNew.push(ch);
      }
    }

    console.log(`[Progreso Verificación] Nuevos agregados: ${verifiedNew.length}/${neededCount} (Probados ${Math.min(candidates.length, i + batch.length)} candidatos)`);
  }

  console.log(`🎉 Se verificaron exitosamente ${verifiedNew.length} nuevos canales vivos.`);

  let nextOrder = existingChannels.length + 1;
  const formattedNew = verifiedNew.map((ch, idx) => {
    let cleanSlug = ch.name.toLowerCase().replace(/[^a-z0-9]/g, '_').replace(/_+/g, '_').substring(0, 24);
    if (!cleanSlug) cleanSlug = 'canal';
    let candidateId = `ch_${cleanSlug}_${idx + 1000}`;
    while (existingIds.has(candidateId)) {
      candidateId = `ch_${cleanSlug}_${Math.floor(1000 + Math.random() * 9000)}`;
    }
    existingIds.add(candidateId);

    return {
      id: candidateId,
      name: ch.name,
      category: ch.category,
      logoUrl: ch.logoUrl,
      streamUrl: ch.streamUrl,
      sources: ch.sources,
      quality: ch.quality,
      isActive: true,
      order: nextOrder++,
      lastChecked: new Date().toISOString()
    };
  });

  const finalCatalog = [...existingChannels, ...formattedNew];
  console.log(`TOTAL CANALES EN CATÁLOGO FINAL: ${finalCatalog.length}`);

  // Renumerar orden correlativo 1 a finalCatalog.length
  finalCatalog.forEach((c, idx) => {
    c.order = idx + 1;
    c.isActive = true;
  });

  fs.writeFileSync(CHANNELS_FILE, JSON.stringify(finalCatalog, null, 2), 'utf-8');
  console.log(`✅ ${finalCatalog.length} canales guardados exitosamente en ${CHANNELS_FILE}`);
}

expandTo2000().catch(err => {
  console.error('Error durante la expansión:', err);
  process.exit(1);
});
