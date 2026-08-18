/**
 * Migrasi v34 — Kolom fcm_dispatch_status pada emergency_alerts untuk Durable FCM Idempotency.
 *
 * ===================================================================
 * Idempotensi Tahan Restart & Multi-Instance
 * ===================================================================
 *
 * Menggantikan pelacakan in-memory dengan status persisten di database:
 * - `fcm_dispatch_status`: 'unsent' (default), 'pending', 'sent', 'failed'
 * - `fcm_dispatched_at`: Waktu berhasil dikirim
 * - `fcm_dispatch_error`: Catatan kesalahan jika gagal
 *
 * Eksekusi transisi status menggunakan UPDATE atomik:
 *   UPDATE emergency_alerts
 *   SET fcm_dispatch_status = 'pending'
 *   WHERE id = $1 AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
 *
 * Mengunci peluang race condition saat ada beberapa instance backend atau
 * pemanggilan endpoint bersamaan tanpa membuat tabel baru.
 *
 * ===================================================================
 * Idempoten & Safety Guard
 * ===================================================================
 */
require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v34_emergency_fcm_dispatch_status');

const { pool } = require('./src/config/database');

async function jalankan() {
  console.log(`\n${'═'.repeat(56)}`);
  console.log('Migrasi v34 — Kolom fcm_dispatch_status pada emergency_alerts');
  console.log('═'.repeat(56));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE public.emergency_alerts
        ADD COLUMN IF NOT EXISTS fcm_dispatch_status character varying(20) DEFAULT 'unsent',
        ADD COLUMN IF NOT EXISTS fcm_dispatched_at timestamp with time zone,
        ADD COLUMN IF NOT EXISTS fcm_dispatch_error text
    `);
    console.log('   OK — Kolom fcm_dispatch_status, fcm_dispatched_at, fcm_dispatch_error dipastikan ada.');

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_emergency_alerts_fcm_status ON public.emergency_alerts(fcm_dispatch_status)
    `);
    console.log('   OK — Indeks idx_emergency_alerts_fcm_status dipastikan ada.');

    await client.query('COMMIT');
    console.log('═'.repeat(56));
    console.log('Migrasi v34 selesai dengan sukses.');
    console.log(`${'═'.repeat(56)}\n`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v34 GAGAL:', err.message);
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
