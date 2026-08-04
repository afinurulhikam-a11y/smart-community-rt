require('dotenv').config();
const { pool } = require('./src/config/database');

/**
 * Migrasi v8 — Modul Kas RT.
 *
 * Menyambungkan buku kas ke master kategori, dan menyiapkan jejak asal-usul
 * transaksi supaya pembayaran iuran bisa otomatis tercatat sebagai pemasukan
 * tanpa bisa tercatat dua kali atau diubah dengan tangan.
 *
 * Tabel kategori_kas dipakai ulang, bukan dibuat baru: bentuknya sudah sesuai
 * (nama_kategori, tipe IN/OUT), sudah berisi 5 kategori, dan tidak punya FK ke
 * tabel mati mana pun.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE kategori_kas
        ADD COLUMN IF NOT EXISTS is_aktif BOOLEAN DEFAULT true,
        ADD COLUMN IF NOT EXISTS keterangan TEXT;
    `);

    // Kolom kategori (VARCHAR) sengaja dipertahankan sebagai snapshot nama:
    // catatan lama tidak ikut berubah bila master di-rename, dan FinanceModel
    // yang dipakai enam layar lain tetap bekerja tanpa perubahan.
    await client.query(`
      ALTER TABLE finances
        ADD COLUMN IF NOT EXISTS kategori_id INT REFERENCES kategori_kas(id),
        ADD COLUMN IF NOT EXISTS sumber VARCHAR(20) DEFAULT 'manual',
        ADD COLUMN IF NOT EXISTS ref_id UUID,
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    `);

    // Satu pembayaran iuran hanya boleh menghasilkan satu baris kas.
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS finances_ref_uniq
        ON finances (ref_id) WHERE ref_id IS NOT NULL;
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS finances_tanggal_idx ON finances (tanggal DESC);
    `);

    await client.query('COMMIT');
    console.log('Migrasi v8 berhasil: modul Kas RT siap (kategori + jejak asal transaksi).');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v8 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
