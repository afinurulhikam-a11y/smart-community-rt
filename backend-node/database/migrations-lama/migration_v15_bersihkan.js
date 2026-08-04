require('dotenv').config();
const { pool } = require('./src/config/database');

/**
 * Migrasi v15 — membuang tabel yang tidak pernah disentuh kode.
 *
 * Kelimanya diverifikasi lebih dulu dengan menyapu seluruh `backend-node/src`:
 * tidak ada satu pun FROM / JOIN / INSERT / UPDATE / DELETE yang menyebutnya.
 *
 *  - `roles` — pola yang sama persis dengan `users.warga_id` dulu. Ada FK
 *    `users.role_id → roles`, tetapi terisi hanya 1 dari 48 baris sementara
 *    SELURUH otorisasi membaca `users.role` bertipe VARCHAR. Isinya bahkan
 *    memuat "Seksi Keamanan" yang tidak pernah ada di aplikasi.
 *  - `master_pekerjaan`, `master_pendidikan` — dulu hanya dirujuk tabel
 *    `warga`, yang sendirinya sudah dijatuhkan di migrasi v12. Sejak itu
 *    keduanya yatim sepenuhnya.
 *  - `struktur_rt` — tidak ada rute `/api/struktur` sama sekali; konstanta di
 *    Flutter menunjuk endpoint yang selalu menjawab 404.
 *  - `umkm` — layarnya yatim, providernya hanya dipakai layar itu, dan
 *    tabelnya kosong. Modulnya dibuang seluruhnya bersama migrasi ini.
 *
 * PERINGATAN: penjatuhan tabel tidak bisa dibatalkan. Ambil pg_dump lebih dulu.
 */

/** Urutan anak → induk. Sengaja tanpa CASCADE agar kejutan memicu error. */
const TABEL = [
  'umkm',              // -> users
  'struktur_rt',       // -> users
  'master_pekerjaan',
  'master_pendidikan',
  'roles',
];

async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Laporkan jumlahnya lebih dulu. Kalau ternyata ada isinya di luar
    // dugaan, angkanya terlihat di terminal sebelum benar-benar lenyap.
    const sebelum = {};
    for (const t of TABEL) {
      const ada = await client.query('SELECT to_regclass($1) AS ada', [`public.${t}`]);
      if (!ada.rows[0].ada) continue;
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM ${t}`);
      sebelum[t] = c.rows[0].n;
    }

    // Kolom mati dijatuhkan lebih dulu supaya DROP TABLE roles tidak perlu
    // CASCADE — sama seperti penanganan users.warga_id di migrasi v12.
    await client.query('ALTER TABLE users DROP COLUMN IF EXISTS role_id;');

    for (const t of TABEL) {
      await client.query(`DROP TABLE IF EXISTS ${t};`);
    }

    await client.query('COMMIT');

    const dijatuhkan = Object.keys(sebelum);
    console.log('Migrasi v15 berhasil.');
    console.log('  Kolom users.role_id dijatuhkan.');
    if (dijatuhkan.length) {
      console.log(`  Tabel dijatuhkan (${dijatuhkan.length}):`);
      for (const t of dijatuhkan) console.log(`    - ${t} (${sebelum[t]} baris)`);
    } else {
      console.log('  Tabel-tabel itu sudah tidak ada.');
    }
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v15 gagal:', err.message);
    console.error('Tidak ada perubahan yang diterapkan.');
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
