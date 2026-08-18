/**
 * Migrasi v23 — wajibkan pergantian kata sandi untuk akun warga baru.
 *
 * ===================================================================
 * Kenapa ada
 * ===================================================================
 *
 * Akun warga dibuat oleh pengurus dengan kata sandi awal yang sama untuk
 * semua (atau sandi acak yang terpaksa dicatat/disebutkan). Kata sandi ini
 * sudah diketahui beberapa orang selama proses pendaftaran, sehingga warga
 * yang pertama kali masuk dengan kata sandi itu berada pada risiko akunnya
 * dimasuki orang lain.
 *
 * Kolom `must_change_password` menandai akun yang belum mengganti kata
 * sandinya. Setelah login dengan akun seperti itu, aplikasi mewajibkan
 * pergantian kata sandi sebelum dipakai — bukan sekadar menyarankan.
 *
 * Idempoten: aman dijalankan berulang, dan perlu dijalankan terhadap SETIAP
 * database yang sudah ada (termasuk Railway).
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v23');

const { pool } = require('../../src/config/database');

async function jalankan() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const ada = await client.query(
      `SELECT 1 FROM information_schema.columns
       WHERE table_name = 'users' AND column_name = 'must_change_password'`
    );

    if (ada.rows.length > 0) {
      console.log('  ✔️  users.must_change_password sudah ada');
    } else {
      await client.query(
        `ALTER TABLE users ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE`
      );
      console.log('  ➕ users.must_change_password DITAMBAHKAN');
    }

    await client.query('COMMIT');
    console.log('\n✅ Kolom siap. Jalankan sekuel kode backend + Flutter untuk melengkapi fungsinya.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi dibatalkan:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

jalankan();