require('dotenv').config();
const { pool } = require('./src/config/database');

/**
 * Migrasi v6 — Modul Iuran Warga.
 *
 * Memindahkan satuan tagih dari per-user menjadi per-kartu keluarga.
 * Sebelumnya createBillBatch menyasar semua user ber-role 'warga' (43 akun,
 * 21 di antaranya yatim tanpa data kependudukan, sisanya termasuk balita),
 * padahal iuran RT ditagihkan per KK.
 *
 * Tabel jenis_iuran dipakai ulang, bukan dibuat baru: bentuknya sudah sesuai
 * dan tidak punya FK ke tabel mati mana pun.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE jenis_iuran
        ADD COLUMN IF NOT EXISTS periode VARCHAR(20) DEFAULT 'bulanan',
        ADD COLUMN IF NOT EXISTS is_aktif BOOLEAN DEFAULT true,
        ADD COLUMN IF NOT EXISTS keterangan TEXT;
    `);

    // user_id tetap ada, tapi maknanya berubah menjadi "siapa yang membayar".
    await client.query(`
      ALTER TABLE bills
        ADD COLUMN IF NOT EXISTS keluarga_id INT REFERENCES keluarga(id) ON DELETE CASCADE,
        ADD COLUMN IF NOT EXISTS jenis_iuran_id INT REFERENCES jenis_iuran(id),
        ADD COLUMN IF NOT EXISTS jatuh_tempo DATE;
    `);

    // Satu KK hanya boleh punya satu tagihan per jenis per periode. Indeks ini
    // yang membuat Generate Tagihan aman dijalankan berulang.
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS bills_kk_jenis_bulan_uniq
        ON bills (keluarga_id, jenis_iuran_id, bulan)
        WHERE keluarga_id IS NOT NULL;
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS bills_bulan_status_idx ON bills (bulan, status);
    `);

    await client.query('COMMIT');
    console.log('Migrasi v6 berhasil: modul iuran siap (tagihan per kartu keluarga).');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v6 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
