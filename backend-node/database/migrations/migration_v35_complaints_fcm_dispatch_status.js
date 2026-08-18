/**
 * Migrasi v35 — Kolom fcm_dispatch_status dan fcm_last_response_dispatch pada complaints untuk Durable FCM Idempotency.
 *
 * ===================================================================
 * Idempotensi Tahan Restart & Multi-Instance (Modul Pengaduan)
 * ===================================================================
 *
 * - `fcm_dispatch_status`: 'unsent' (default), 'pending', 'sent', 'failed' (untuk event pengaduan baru ke pengurus)
 * - `fcm_last_response_dispatch`: Melacak status & tanggapan terakhir yang sudah disiarkan ke pelapor
 *   (mencegah notifikasi berulang saat update status dipanggil tanpa perubahan data atau diproses ulang)
 *
 * Idempoten & Safety Guard dilindungi oleh assertCanRunMigration.
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v35_complaints_fcm_dispatch_status');

const { pool } = require('../../src/config/database');

async function jalankan() {
  console.log(`\n${'═'.repeat(56)}`);
  console.log('Migrasi v35 — Kolom fcm_dispatch_status pada complaints');
  console.log('═'.repeat(56));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE public.complaints
        ADD COLUMN IF NOT EXISTS fcm_dispatch_status character varying(20) DEFAULT 'unsent',
        ADD COLUMN IF NOT EXISTS fcm_last_response_dispatch text
    `);
    console.log('   OK — Kolom fcm_dispatch_status dan fcm_last_response_dispatch dipastikan ada.');

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_complaints_fcm_status ON public.complaints(fcm_dispatch_status)
    `);
    console.log('   OK — Indeks idx_complaints_fcm_status dipastikan ada.');

    await client.query('COMMIT');
    console.log('═'.repeat(56));
    console.log('Migrasi v35 selesai dengan sukses.');
    console.log(`${'═'.repeat(56)}\n`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v35 GAGAL:', err.message);
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  jalankan()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
}

module.exports = { jalankan };
