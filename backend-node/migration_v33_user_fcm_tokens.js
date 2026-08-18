/**
 * Migrasi v33 — Tabel user_fcm_tokens untuk Registrasi Token Perangkat FCM.
 *
 * ===================================================================
 * Relasi UUID & Pemetaan Multi-Device
 * ===================================================================
 *
 * `users.id` bertipe UUID (v4). Tabel `user_fcm_tokens` berelasi langsung
 * ke `users(id)` via `user_id uuid REFERENCES users(id) ON DELETE CASCADE`.
 *
 * `fcm_token` bernilai UNIQUE: satu token FCM hanya mewakili satu instalasi
 * perangkat aktif. Bila sebuah perangkat berganti pengguna (login akun lain),
 * token akan di-reassign ke `user_id` yang baru secara aman (UPSERT).
 *
 * Entity ID numerik lain di sistem (seperti agenda.id, polling.id, bansos.id)
 * sama sekali TIDAK diubah.
 *
 * ===================================================================
 * Idempoten & Safety Guard
 * ===================================================================
 *
 * Menggunakan `CREATE TABLE IF NOT EXISTS` dan `CREATE INDEX IF NOT EXISTS`.
 * Dilindungi oleh `assertCanRunMigration` agar tidak dijalankan sembarangan
 * di environment yang tidak terotorisasi.
 */
require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v33_user_fcm_tokens');

const { pool } = require('./src/config/database');

async function jalankan() {
  console.log(`\n${'═'.repeat(56)}`);
  console.log('Migrasi v33 — Tabel user_fcm_tokens untuk FCM Token Registry');
  console.log('═'.repeat(56));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
        id uuid DEFAULT public.uuid_generate_v4() PRIMARY KEY,
        user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        fcm_token text NOT NULL UNIQUE,
        device_type character varying(20) DEFAULT 'android',
        device_name character varying(100),
        is_active boolean DEFAULT true,
        last_used_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log('   OK — Tabel public.user_fcm_tokens dipastikan ada.');

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id ON public.user_fcm_tokens(user_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_fcm_token ON public.user_fcm_tokens(fcm_token)
    `);
    console.log('   OK — Indeks user_id dan fcm_token dipastikan ada.');

    await client.query('COMMIT');
    console.log('═'.repeat(56));
    console.log('Migrasi v33 selesai dengan sukses.');
    console.log(`${'═'.repeat(56)}\n`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v33 GAGAL:', err.message);
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
