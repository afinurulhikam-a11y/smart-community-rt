/**
 * Migrasi v36 — Kolom fcm_dispatch_status dan fcm_last_status_dispatch pada letters untuk Durable FCM Idempotency.
 *
 * ===================================================================
 * Idempotensi Tahan Restart & Multi-Instance (Modul Surat Menyurat)
 * ===================================================================
 *
 * - `fcm_dispatch_status`: 'unsent' (default), 'pending', 'sent', 'failed' (untuk event permohonan surat baru ke pengurus)
 * - `fcm_last_status_dispatch`: Melacak status & catatan terakhir yang sudah disiarkan ke pemohon surat
 *   (mencegah notifikasi berulang saat update status dipanggil tanpa perubahan data atau diproses ulang)
 *
 * Idempoten & Safety Guard dilindungi oleh assertCanRunMigration.
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v36_letters_fcm_dispatch_status');

const { pool } = require('../../src/config/database');

async function jalankan() {
  console.log(`\n${'═'.repeat(56)}`);
  console.log('Migrasi v36 — Kolom fcm_dispatch_status pada letters');
  console.log('═'.repeat(56));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE public.letters
        ADD COLUMN IF NOT EXISTS fcm_dispatch_status character varying(20) DEFAULT 'unsent',
        ADD COLUMN IF NOT EXISTS fcm_last_status_dispatch text
    `);
    console.log('   OK — Kolom fcm_dispatch_status dan fcm_last_status_dispatch dipastikan ada.');

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_letters_fcm_status ON public.letters(fcm_dispatch_status)
    `);
    console.log('   OK — Indeks idx_letters_fcm_status dipastikan ada.');

    await client.query('COMMIT');
    console.log('═'.repeat(56));
    console.log('Migrasi v36 selesai dengan sukses.');
    console.log(`${'═'.repeat(56)}\n`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v36 GAGAL:', err.message);
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
