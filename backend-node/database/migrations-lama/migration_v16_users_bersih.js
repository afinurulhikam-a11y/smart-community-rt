require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v16_users_bersih');

const { pool } = require('../../src/config/database');

/**
 * Migrasi v16 — membereskan sisa desain lama di tabel `users`.
 *
 * Tabel ini menyimpan DUA desain sekaligus: `username`/`password` dari skema
 * awal, dan `nama`/`email`/`password_hash` yang sebenarnya dipakai kode.
 * Keduanya bertanda NOT NULL, dan itu menimbulkan cacat nyata:
 *
 *   POST /api/auth/register SELALU GAGAL.
 *
 * `auth.controller.js` menyisipkan `nama, email, password_hash, …` tanpa
 * menyentuh `username` maupun `password`, sehingga setiap registrasi ditolak
 * "null value in column username violates not-null constraint". Cacat ini
 * tersembunyi karena satu-satunya jalur pembuatan akun yang dipakai selama ini
 * adalah `warga.controller.js`, yang kebetulan mengisi kedua kolom itu.
 *
 * Dua koreksi:
 *
 *  - Kolom `password` DIJATUHKAN. Ia hanya pernah ditulis (diisi salinan
 *    password_hash oleh warga.controller) dan tidak pernah dibaca satu query
 *    pun — duplikasi murni yang justru berisiko menyimpan kredensial dua kali.
 *
 *  - `username` dijadikan NULLABLE. Kolom ini masih load-bearing: akun warga
 *    memakainya untuk menyimpan NIK, dan `login` menerima `email = $1 OR
 *    username = $1`. Yang keliru hanyalah kewajibannya — akun pengurus dan
 *    akun hasil registrasi mandiri tidak punya NIK untuk diisikan.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const kolom = await client.query(
      `SELECT column_name, is_nullable FROM information_schema.columns
       WHERE table_name = 'users' AND column_name IN ('username', 'password')`
    );
    const punya = Object.fromEntries(kolom.rows.map((r) => [r.column_name, r.is_nullable]));

    await client.query('ALTER TABLE users DROP COLUMN IF EXISTS password;');
    await client.query('ALTER TABLE users ALTER COLUMN username DROP NOT NULL;');

    await client.query('COMMIT');

    console.log('Migrasi v16 berhasil.');
    console.log(punya.password
      ? '  Kolom users.password dijatuhkan (duplikat password_hash, tidak pernah dibaca).'
      : '  Kolom users.password sudah tidak ada.');
    console.log(punya.username === 'NO'
      ? '  users.username kini boleh NULL — registrasi mandiri tidak lagi gagal.'
      : '  users.username sudah boleh NULL.');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v16 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
