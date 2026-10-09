#!/usr/bin/env node
/**
 * Script CLI para que el Administrador genere códigos de activación con vigencia configurada.
 * Uso:
 *   node scripts/generate-license.js --name "Cliente Sala" --days 30 --devices 1
 *   node scripts/generate-license.js --demo
 *   node scripts/generate-license.js --name "Familia Gomez" --days 90 --devices 2 --code "VJ-7788"
 */

const path = require('path');
const accountService = require('../services/accountService');

// Parsear argumentos de línea de comandos simples
const args = process.argv.slice(2);
function getArg(flag, defaultVal = null) {
  const index = args.indexOf(flag);
  if (index !== -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return defaultVal;
}

const isDemo = args.includes('--demo') || args.includes('-d');
const name = getArg('--name') || getArg('-n') || (isDemo ? 'Cliente Demo (1 Hora)' : 'Cliente Smart TV');
const days = isDemo ? 0 : (parseInt(getArg('--days') || getArg('-D'), 10) || 30);
const devices = parseInt(getArg('--devices') || getArg('-m'), 10) || 1;
const customCode = getArg('--code') || getArg('-c');

try {
  const client = accountService.createClient({
    name,
    planDays: isDemo ? '1h' : days,
    planHours: isDemo ? 1 : null,
    maxDevices: devices,
    customCode: customCode ? customCode.toUpperCase() : null,
    isDemo
  });

  const expiresDate = new Date(client.expiresAt);
  const formattedExp = isDemo
    ? '1 Hora (60 minutos)'
    : `${days} Días (Vence: ${expiresDate.toLocaleDateString('es-ES', { day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' })})`;

  console.log('\n========================================================');
  console.log('   🎉 ¡CÓDIGO DE LICENCIA GENERADO CON ÉXITO! (TOM TV)   ');
  console.log('========================================================');
  console.log(`🔑 Código TV:         \x1b[1;32m${client.code}\x1b[0m`);
  console.log(`👤 Nombre Cliente:    \x1b[1;37m${client.name}\x1b[0m`);
  console.log(`⏳ Vigencia:          \x1b[1;33m${formattedExp}\x1b[0m`);
  console.log(`📺 Pantallas Máx:     \x1b[1;36m${client.maxDevices}\x1b[0m`);
  console.log(`🆔 ID de Cliente:     ${client.id}`);
  console.log('--------------------------------------------------------');
  console.log('\n📲 MENSAJE PARA ENVIAR AL CLIENTE POR WHATSAPP:');
  console.log('--------------------------------------------------------');
  console.log(
    `🎬 *¡BIENVENIDO A TOM TV OFICIAL!*\n\n` +
    `Tu acceso a la mejor programación sin límites está listo:\n` +
    `👤 *Cliente:* ${client.name}\n` +
    `🔑 *Código de Activación:* *${client.code}*\n` +
    `⏳ *Vigencia:* ${formattedExp}\n` +
    `📺 *Pantallas permitidas:* ${client.maxDevices}\n\n` +
    `📲 *En Smart TV:* Abre TOM TV e ingresa tu código *${client.code}*\n` +
    `💻 *En Navegador / PC / Celular:* https://tomtv.lat/play\n` +
    `📥 *Descargar APK para TV Box / Firestick:* tomtv.lat/apk\n\n` +
    `¡Que disfrutes del mejor entretenimiento! ⭐`
  );
  console.log('========================================================\n');
} catch (error) {
  console.error('\n❌ Error generando la licencia:', error.message);
  process.exit(1);
}
