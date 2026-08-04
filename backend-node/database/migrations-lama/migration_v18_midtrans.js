require('dotenv').config();
const { pool } = require('./src/config/database');

/**
 * Migrasi v18 — pembayaran iuran lewat Midtrans.
 *
 * ## Kenapa perlu tabel baru
 *
 * `payBill` menandai tagihan lunas SEKETIKA. Pembayaran lewat gateway tidak
 * begitu: ada jeda antara warga memulai pembayaran dan uang benar-benar
 * diterima, dan sebagian pembayaran gagal atau kedaluwarsa.
 *
 * Karena itu percobaan bayar dan uang yang diterima dipisah tegas:
 *
 *   payment_transactions  = PERCOBAAN, dibuat saat warga menekan Bayar
 *   bill_payments         = uang DITERIMA, hanya diisi setelah Midtrans
 *                           mengonfirmasi settlement
 *
 * Pemisahan ini yang menjaga Kas RT tetap jujur: `catatKeKasRt()` hanya
 * terpanggil dari jalur kedua.
 *
 * ## Kenapa nominal disalin
 *
 * `payment_transaction_bills.nominal` menyalin nilai tagihan saat transaksi
 * dibuat, bukan membacanya ulang dari `bills`. Yang ditagihkan ke warga harus
 * tetap sebesar yang tertera saat ia menekan Bayar, walau pengurus mengubah
 * nominal iuran di tengah jalan.
 *
 * ## Kenapa ada kolom is_pending
 *
 * Satu tagihan tidak boleh punya dua percobaan bayar yang masih berjalan —
 * kalau tidak, warga bisa membuat dua order Midtrans untuk tagihan yang sama
 * lalu membayar keduanya. Indeks unik parsial TIDAK BISA memakai subquery ke
 * tabel lain, jadi status "masih berjalan" disalin ke kolom boolean di tabel
 * penghubung dan dijaga bersama status induknya oleh controller.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS payment_transactions (
        id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        order_id         VARCHAR(64) UNIQUE NOT NULL,
        user_id          UUID REFERENCES users(id),
        keluarga_id      INT REFERENCES keluarga(id) ON DELETE CASCADE,
        gross_amount     NUMERIC NOT NULL,
        status           VARCHAR(20) NOT NULL DEFAULT 'pending',
        snap_token       VARCHAR(255),
        redirect_url     TEXT,
        payment_type     VARCHAR(50),
        midtrans_payload JSONB,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        settled_at       TIMESTAMP
      );
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS payment_transactions_status_idx
        ON payment_transactions (status, created_at DESC);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS payment_transaction_bills (
        transaction_id UUID NOT NULL REFERENCES payment_transactions(id) ON DELETE CASCADE,
        bill_id        UUID NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
        nominal        NUMERIC NOT NULL,
        is_pending     BOOLEAN NOT NULL DEFAULT true,
        PRIMARY KEY (transaction_id, bill_id)
      );
    `);

    // Inti penjagaannya: satu tagihan hanya boleh punya SATU baris pending.
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS payment_bill_pending_uniq
        ON payment_transaction_bills (bill_id) WHERE is_pending;
    `);

    await client.query('COMMIT');

    const t = await pool.query(
      `SELECT COUNT(*)::int n FROM pg_tables
       WHERE schemaname = 'public'
         AND tablename IN ('payment_transactions', 'payment_transaction_bills')`
    );

    console.log('Migrasi v18 berhasil.');
    console.log(`  ${t.rows[0].n} dari 2 tabel pembayaran siap.`);
    console.log('  Indeks payment_bill_pending_uniq terpasang — satu tagihan,');
    console.log('  satu percobaan bayar yang berjalan.');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v18 gagal:', err.message);
    console.error('Tidak ada perubahan yang diterapkan.');
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
