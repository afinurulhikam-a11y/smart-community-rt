require('dotenv').config();
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

/**
 * Membuat database dan memuat `database/schema.sql`.
 *
 * Langkah pertama pemasangan dari nol; lanjutkan dengan `node seed-master.js`
 * untuk mengisi menu, hak akses, tabel master, dan akun admin pertama.
 *
 * Sebelumnya berkas ini juga mengubah paksa password user postgres — perilaku
 * yang mengejutkan dan tidak ada hubungannya dengan menyiapkan skema, jadi
 * sudah dihilangkan. Kredensial kini sepenuhnya dibaca dari `.env`.
 *
 * PERINGATAN: database lama DIJATUHKAN bila sudah ada.
 */

const DB = process.env.DB_NAME || 'smart_community_rt';

const koneksi = (database) => new Client({
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database,
});

async function run() {
  const admin = koneksi('postgres');
  await admin.connect();
  try {
    const ada = await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [DB]);
    if (ada.rowCount > 0) {
      console.log(`Menjatuhkan database "${DB}" yang sudah ada...`);
      await admin.query(`DROP DATABASE ${DB} WITH (FORCE)`);
    }
    console.log(`Membuat database "${DB}"...`);
    await admin.query(`CREATE DATABASE ${DB}`);
  } finally {
    await admin.end();
  }

  const db = koneksi(DB);
  await db.connect();
  try {
    const berkas = path.join(__dirname, 'database', 'schema.sql');
    console.log('Memuat database/schema.sql...');
    await db.query(fs.readFileSync(berkas, 'utf8'));

    const t = await db.query(
      "SELECT COUNT(*)::int n FROM pg_tables WHERE schemaname = 'public'"
    );
    console.log(`Skema termuat: ${t.rows[0].n} tabel.`);
    console.log('\nLangkah berikutnya:  node seed-master.js');
  } finally {
    await db.end();
  }
}

run().catch((err) => {
  console.error('init-db gagal:', err.message);
  process.exit(1);
});
