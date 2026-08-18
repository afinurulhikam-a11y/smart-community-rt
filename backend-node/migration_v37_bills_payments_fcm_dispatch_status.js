/**
 * Migrasi v37 — Kolom fcm_dispatch_status pada bills, payment_transactions, dan bill_payments untuk Durable FCM Idempotency.
 *
 * ===================================================================
 * Idempotensi Tahan Restart & Multi-Instance (Modul Iuran & Pembayaran)
 * ===================================================================
 *
 * - `bills.fcm_dispatch_status`: 'unsent' (default), 'pending', 'sent', 'failed' (untuk event penerbitan tagihan baru)
 * - `payment_transactions.fcm_dispatch_status`: 'unsent' (default), 'pending', 'sent', 'failed' (untuk event pembayaran sukses via Midtrans)
 * - `bill_payments.fcm_dispatch_status`: 'unsent' (default), 'pending', 'sent', 'failed' (untuk event pembayaran sukses tunai/manual)
 *
 * Idempoten & Safety Guard dilindungi oleh assertCanRunMigration.
 */
require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v37_bills_payments_fcm_dispatch_status');

const { pool } = require('./src/config/database');

async function jalankan() {
  console.log(`\n${'═'.repeat(56)}`);
  console.log('Migrasi v37 — Kolom fcm_dispatch_status pada bills & payments');
  console.log('═'.repeat(56));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE public.bills
        ADD COLUMN IF NOT EXISTS fcm_dispatch_status character varying(20) DEFAULT 'unsent';
      CREATE INDEX IF NOT EXISTS idx_bills_fcm_status ON public.bills(fcm_dispatch_status);
    `);
    console.log('   OK — Kolom fcm_dispatch_status pada bills dipastikan ada.');

    await client.query(`
      ALTER TABLE public.payment_transactions
        ADD COLUMN IF NOT EXISTS fcm_dispatch_status character varying(20) DEFAULT 'unsent';
      CREATE INDEX IF NOT EXISTS idx_payment_trx_fcm_status ON public.payment_transactions(fcm_dispatch_status);
    `);
    console.log('   OK — Kolom fcm_dispatch_status pada payment_transactions dipastikan ada.');

    await client.query(`
      ALTER TABLE public.bill_payments
        ADD COLUMN IF NOT EXISTS fcm_dispatch_status character varying(20) DEFAULT 'unsent';
      CREATE INDEX IF NOT EXISTS idx_bill_payments_fcm_status ON public.bill_payments(fcm_dispatch_status);
    `);
    console.log('   OK — Kolom fcm_dispatch_status pada bill_payments dipastikan ada.');

    await client.query('COMMIT');
    console.log('═'.repeat(56));
    console.log('Migrasi v37 selesai dengan sukses.');
    console.log(`${'═'.repeat(56)}\n`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v37 GAGAL:', err.message);
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
