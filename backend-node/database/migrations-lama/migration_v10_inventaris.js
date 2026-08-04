require('dotenv').config();
const { pool } = require('./src/config/database');

/**
 * Migrasi v10 — Modul Data Barang & Peminjaman.
 *
 * Menyiapkan dua hal yang selama ini tidak punya tempat di database:
 *  - nilai_barang, supaya kartu "Total Nilai" tidak lagi selalu Rp 0
 *  - tanggal_rencana_kembali, supaya status "Terlambat" bisa dihitung
 *
 * Perhatikan bahwa kolom inventory.jumlah TIDAK diubah di sini. Maknanya yang
 * diperbaiki di controller: jumlah adalah total barang yang dimiliki dan tidak
 * pernah dikurangi saat dipinjam. Jumlah tersedia dihitung saat dibaca.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE inventory
        ADD COLUMN IF NOT EXISTS nilai_barang NUMERIC DEFAULT 0,
        ADD COLUMN IF NOT EXISTS tanggal_perolehan DATE;
    `);

    await client.query(`
      ALTER TABLE borrowings
        ADD COLUMN IF NOT EXISTS tanggal_rencana_kembali DATE,
        ADD COLUMN IF NOT EXISTS dicatat_oleh UUID REFERENCES users(id),
        ADD COLUMN IF NOT EXISTS nama_peminjam VARCHAR(255),
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    `);

    // Dipakai subquery penghitung "sedang dipinjam" pada setiap pembacaan
    // daftar barang.
    await client.query(`
      CREATE INDEX IF NOT EXISTS borrowings_status_idx ON borrowings (status, inventory_id);
    `);

    await client.query('COMMIT');
    console.log('Migrasi v10 berhasil: modul inventaris & peminjaman siap.');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v10 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
