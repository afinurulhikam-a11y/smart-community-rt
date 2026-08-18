#!/usr/bin/env node
/**
 * Test Harness: Pengujian Runtime Push Notification FCM Tunggal (Aman & Zero-Leak)
 * =================================================================================
 *
 * Tujuan:
 * 1. Menguji pengiriman push notification FCM ke 1 token perangkat tertentu secara runtime.
 * 2. TIDAK PERNAH menyimpan token ke source code, database, log, atau Git.
 * 3. Token dimasking pada seluruh output konsol (contoh: "fcm_to...1234").
 * 4. Tidak mengubah data bisnis warga apa pun dan tidak mengirim notifikasi massal.
 *
 * Cara Penggunaan:
 *   node test-fcm-runtime.js <FCM_TOKEN>
 *   node test-fcm-runtime.js --token <FCM_TOKEN> --title "Judul Kustom" --body "Isi Pesan"
 *   FCM_TARGET_TOKEN=<FCM_TOKEN> node test-fcm-runtime.js
 * =================================================================================
 */

require('dotenv').config();
const { sendToToken, maskToken } = require('./src/services/fcm.service');
const { getFirebaseDiagnostic } = require('./src/config/firebase');

function parseArgs() {
  const args = process.argv.slice(2);
  let token = process.env.FCM_TARGET_TOKEN || null;
  let title = '🧪 Uji Coba FCM Smart Community RT';
  let body = 'Pesan uji coba push notification langsung dari server Smart Community RT.';

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--token' && args[i + 1]) {
      token = args[i + 1];
      i++;
    } else if (arg === '--title' && args[i + 1]) {
      title = args[i + 1];
      i++;
    } else if (arg === '--body' && args[i + 1]) {
      body = args[i + 1];
      i++;
    } else if (!arg.startsWith('--') && !token) {
      token = arg;
    }
  }

  return { token, title, body };
}

async function runRuntimeFcmTest() {
  console.log('\n================================================================');
  console.log('🧪 TEST HARNESS: RUNTIME SINGLE-TOKEN FCM PUSH NOTIFICATION');
  console.log('================================================================\n');

  // 1. Periksa status diagnostik Firebase Admin SDK
  const diagnostic = getFirebaseDiagnostic();
  console.log('1. Status Diagnostik Firebase Admin SDK:');
  console.log(`   - Configured        : ${diagnostic.configured ? '✅ Ya' : '⚠️ Tidak'}`);
  console.log(`   - Simulation Mode   : ${diagnostic.simulation_mode ? '⚠️ Aktif (Simulasi)' : '🔥 Tidak Aktif (Real FCM Dispatch)'}`);
  console.log(`   - Project ID        : ${diagnostic.project_id || '(Belum disetel / default)'}`);
  console.log(`   - Credential Source : ${diagnostic.credential_source}`);
  console.log(`   - App Name          : ${diagnostic.app_name || 'None'}\n`);

  const { token, title, body } = parseArgs();

  // 2. Jika token tidak diberikan, tampilkan panduan penggunaan
  if (!token || typeof token !== 'string' || token.trim() === '') {
    console.log('ℹ️  PANDUAN PENGGUNAAN (Token belum disertakan):');
    console.log('   Jalankan script ini dengan menyertakan token FCM perangkat Anda:\n');
    console.log('   node test-fcm-runtime.js <TOKEN_FCM_PERANGKAT>');
    console.log('   node test-fcm-runtime.js --token <TOKEN_FCM> --title "Info RT" --body "Test Pesan"');
    console.log('\n   Catatan Keamanan:');
    console.log('   - Token hanya dibaca di memori saat eksekusi dan TIDAK disimpan ke file/database.');
    console.log('   - Log akan otomatis memasking token demi privasi.\n');
    console.log('================================================================\n');
    return;
  }

  const cleanToken = token.trim();
  console.log('2. Menyiapkan Pengiriman Test FCM Tunggal:');
  console.log(`   - Target Token (Masked) : ${maskToken(cleanToken)}`);
  console.log(`   - Judul Notifikasi      : ${title}`);
  console.log(`   - Isi Notifikasi        : ${body}`);
  console.log(`   - Data Payload          : { type: "test_runtime", timestamp: "${new Date().toISOString()}" }\n`);

  console.log('3. Mengirimkan notifikasi via sendToToken()...');
  const startTime = Date.now();

  try {
    const result = await sendToToken(cleanToken, {
      title,
      body,
      data: {
        type: 'test_runtime',
        source: 'test-fcm-runtime',
        timestamp: new Date().toISOString(),
      },
      priority: 'high',
    });

    const elapsed = Date.now() - startTime;
    console.log(`\n4. Hasil Pengiriman (${elapsed} ms):`);
    if (result.success) {
      if (result.simulated) {
        console.log('   ⚠️ HASIL: SIMULASI BERHASIL (Kredensial Firebase belum terpasang di env).');
        console.log(`   Message ID Simulasi : ${result.messageId}`);
      } else {
        console.log('   🎉 HASIL: BERHASIL TERKIRIM KE FIREBASE CLOUD MESSAGING!');
        console.log(`   FCM Message ID      : ${result.messageId}`);
      }
    } else {
      console.log('   ❌ HASIL: PENGIRIMAN GAGAL.');
      console.log(`   Error Code / Pesan  : ${result.error}`);
    }

    console.log('\n================================================================');
    console.log('PENGUJIAN HARNESS SELESAI.');
    console.log('================================================================\n');
  } catch (err) {
    console.error('\n❌ Terjadi kesalahan tak terduga saat pengiriman:', err.message);
  }
}

if (require.main === module) {
  runRuntimeFcmTest()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Fatal Test Harness Error:', err);
      process.exit(1);
    });
}

module.exports = { runRuntimeFcmTest, parseArgs };
