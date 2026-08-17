require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v12_reset_sistem');

const { pool } = require('../../src/config/database');

/**
 * Migrasi v12 — Reset Sistem.
 *
 * Dua pekerjaan:
 *
 * 1. Menjatuhkan tujuh tabel warisan yang sudah tidak dipakai kode mana pun.
 *    Sebelum ditulis, ini diverifikasi: nol statement SQL di seluruh
 *    backend-node menyentuh mereka, `users.warga_id` terisi 0 dari 48 baris,
 *    dan tidak ada view yang bergantung. Klasternya tertutup — satu-satunya
 *    penunjuk dari luar adalah kolom mati `users.warga_id` itu.
 *
 *    Data warga yang hidup ada di `keluarga` + `anggota_keluarga` sejak
 *    migrasi v6/v7; tabel `warga` dan `kartu_keluarga` adalah desain lama yang
 *    ditinggalkan setengah jalan.
 *
 * 2. Membuat `reset_logs`. Kelompok reset "Log Aktivitas" menghapus isi
 *    `activity_logs`, jadi jejak bahwa reset pernah dilakukan tidak boleh
 *    disimpan di sana — ia akan menghapus catatannya sendiri.
 *
 * PERINGATAN: penjatuhan tabel tidak bisa dibatalkan. Ambil pg_dump lebih dulu.
 */

/** Urutan anak → induk. Sengaja tanpa CASCADE agar kejutan memicu error. */
const TABEL_WARISAN = [
  'pengaduan',        // -> warga
  'surat_pengantar',  // -> warga
  'tagihan_iuran',    // -> kartu_keluarga, jenis_iuran, users
  'buku_kas',         // -> kategori_kas, users
  'pengumuman',       // -> users
  'warga',            // -> kartu_keluarga, master_pendidikan, master_pekerjaan
  'kartu_keluarga',
];

async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Laporkan apa yang hilang, supaya angkanya terlihat di terminal sebelum
    // benar-benar lenyap.
    const sebelum = {};
    for (const t of TABEL_WARISAN) {
      const ada = await client.query('SELECT to_regclass($1) AS ada', [`public.${t}`]);
      if (!ada.rows[0].ada) continue;
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM ${t}`);
      sebelum[t] = c.rows[0].n;
    }

    // Kolom mati. Dijatuhkan lebih dulu agar DROP TABLE warga tidak perlu
    // CASCADE, sehingga ketergantungan tak terduga tetap memicu error.
    await client.query('ALTER TABLE users DROP COLUMN IF EXISTS warga_id;');

    for (const t of TABEL_WARISAN) {
      await client.query(`DROP TABLE IF EXISTS ${t};`);
    }

    await client.query(`
      CREATE TABLE IF NOT EXISTS reset_logs (
        id SERIAL PRIMARY KEY,
        grup_kode   VARCHAR(60) NOT NULL,
        grup_nama   VARCHAR(100) NOT NULL,
        rincian     JSONB NOT NULL,
        total_baris INT NOT NULL DEFAULT 0,
        dicadangkan BOOLEAN DEFAULT false,
        user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
        user_nama   VARCHAR(100),
        user_role   VARCHAR(30),
        ip_address  VARCHAR(45),
        created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS reset_logs_waktu
        ON reset_logs (created_at DESC);
    `);

    await client.query('COMMIT');

    const dijatuhkan = Object.keys(sebelum);
    console.log('Migrasi v12 berhasil.');
    if (dijatuhkan.length) {
      console.log(`  Tabel warisan dijatuhkan (${dijatuhkan.length}):`);
      for (const t of dijatuhkan) console.log(`    - ${t} (${sebelum[t]} baris)`);
    } else {
      console.log('  Tabel warisan sudah tidak ada, tidak ada yang dijatuhkan.');
    }
    console.log('  Tabel reset_logs siap.');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v12 gagal:', err.message);
    console.error('Tidak ada perubahan yang diterapkan.');
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
