/**
 * Script independiente para sincronizar canales de televisión en vivo
 * desde el repositorio oficial iptv-org/iptv.
 *
 * Ejecución:
 *   node scripts/syncIptv.js
 */
const iptvSyncService = require('../services/iptvSyncService');
const channelService = require('../services/channelService');

async function main() {
  console.log('====================================================');
  console.log('📺 VJ STREAM - Sincronizador de Canales IPTV-ORG');
  console.log('====================================================');

  try {
    const result = await iptvSyncService.syncAndSave();
    console.log('Resultado de sincronización:', result);

    // Recargar memoria de channelService
    channelService.reload();
    console.log('✅ Canales cargados en memoria. Total activos:', channelService.getChannels().length);
    process.exit(0);
  } catch (error) {
    console.error('❌ Error sincronizando canales:', error);
    process.exit(1);
  }
}

main();
