require('dotenv').config();
const { pool } = require('../../src/config/database');

/**
 * Migrasi v5 — Melengkapi kolom demografi.
 *
 * Layar Statistik sebelumnya membaca tabel lama (warga / kartu_keluarga) yang
 * tidak pernah diisi aplikasi. Setelah diarahkan ke anggota_keluarga + keluarga,
 * dua kolom berikut belum ada padanannya dan harus ditambahkan.
 *
 * has_ktp sudah dipakai warga.controller.js tetapi tidak pernah dibuat oleh
 * migrasi mana pun — ikut ditambahkan agar setup database baru tidak rusak.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE anggota_keluarga
        ADD COLUMN IF NOT EXISTS status_pernikahan VARCHAR(50),
        ADD COLUMN IF NOT EXISTS has_ktp BOOLEAN DEFAULT false,
        ADD COLUMN IF NOT EXISTS no_hp VARCHAR(20);
    `);

    await client.query(`
      ALTER TABLE keluarga
        ADD COLUMN IF NOT EXISTS status_rumah VARCHAR(50) DEFAULT 'Milik Sendiri';
    `);

    await client.query('COMMIT');
    console.log('Migrasi v5 berhasil: kolom demografi sudah lengkap.');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v5 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
