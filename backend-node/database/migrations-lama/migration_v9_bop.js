require('dotenv').config();
const { pool } = require('../../src/config/database');

/**
 * Migrasi v9 — Modul Dana BOP.
 *
 * Dana BOP berbeda dari Kas RT: ada pagu/alokasi dari pemerintah yang harus
 * dipertanggungjawabkan, sehingga butuh tabel alokasi tersendiri. Kategori
 * belanjanya juga diatur terpisah dari kategori_kas karena peruntukannya beda.
 *
 * Selain itu bop_finances selama ini TIDAK punya kolom kategori sama sekali,
 * padahal layar menampilkan kolom KATEGORI — nilainya selalu 'Umum' bawaan
 * model. Kolomnya ditambahkan di sini.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS kategori_bop (
        id SERIAL PRIMARY KEY,
        nama_kategori VARCHAR(100) NOT NULL UNIQUE,
        tipe VARCHAR(3) NOT NULL CHECK (tipe IN ('IN','OUT')),
        is_aktif BOOLEAN DEFAULT true,
        keterangan TEXT
      );
    `);

    // UNIQUE (tahun, termin) mencegah satu termin dicatat pagunya dua kali.
    await client.query(`
      CREATE TABLE IF NOT EXISTS alokasi_bop (
        id SERIAL PRIMARY KEY,
        tahun INT NOT NULL,
        termin VARCHAR(30) NOT NULL DEFAULT 'Tahunan',
        nominal NUMERIC NOT NULL,
        sumber_dana VARCHAR(100),
        keterangan TEXT,
        created_by UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (tahun, termin)
      );
    `);

    // Kolom kategori (VARCHAR) berperan sebagai snapshot nama, sama seperti
    // finances.kategori: catatan lama tidak ikut berubah bila master di-rename.
    await client.query(`
      ALTER TABLE bop_finances
        ADD COLUMN IF NOT EXISTS kategori VARCHAR(50) DEFAULT 'Umum',
        ADD COLUMN IF NOT EXISTS kategori_id INT REFERENCES kategori_bop(id),
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS bop_finances_tanggal_idx ON bop_finances (tanggal DESC);
    `);

    // Kategori khas belanja BOP agar fitur langsung terpakai.
    const seed = await client.query(`
      INSERT INTO kategori_bop (nama_kategori, tipe) VALUES
        ('Pencairan Dana BOP', 'IN'),
        ('Bantuan Lain', 'IN'),
        ('Honor Pengurus RT', 'OUT'),
        ('ATK & Administrasi', 'OUT'),
        ('Kegiatan Warga', 'OUT'),
        ('Pemeliharaan Sarana', 'OUT'),
        ('Konsumsi Rapat', 'OUT')
      ON CONFLICT (nama_kategori) DO NOTHING
      RETURNING id
    `);

    await client.query('COMMIT');
    console.log(`Migrasi v9 berhasil: modul Dana BOP siap (${seed.rowCount} kategori baru ditambahkan).`);
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v9 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
