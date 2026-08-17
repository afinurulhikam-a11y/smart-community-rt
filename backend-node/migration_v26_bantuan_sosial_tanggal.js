/**
 * Migrasi v26 — modul Bantuan Sosial dari berbasis tahun ke tanggal/periode.
 *
 * Mengubah tabel `bantuan_sosial` untuk mendukung:
 * - `tanggal_bantuan DATE` untuk bantuan satu kali
 * - `tanggal_mulai DATE` dan `tanggal_selesai DATE` untuk bantuan berperiode
 * - Membuat `tahun INTEGER` menjadi opsional (nullable) agar tidak memaksa data baru
 * - Mengamankan data lama yang hanya memiliki `tahun` tanpa mengarang tanggal palsu
 *
 * Idempoten: aman dijalankan berulang.
 *
 *   node migration_v26_bantuan_sosial_tanggal.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v26');

const { pool } = require('./src/config/database');

const KOLOM_BARU = [
  ['tanggal_bantuan', 'DATE'],
  ['tanggal_mulai', 'DATE'],
  ['tanggal_selesai', 'DATE'],
];

async function adaKolom(tabel, kolom) {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rowCount > 0;
}

async function isNullable(tabel, kolom) {
  const r = await pool.query(
    `SELECT is_nullable FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rows[0]?.is_nullable === 'YES';
}

async function jalankan() {
  let berubah = 0;

  console.log('\n── Memeriksa skema bantuan_sosial ───────────────────');

  for (const [kolom, tipe] of KOLOM_BARU) {
    if (await adaKolom('bantuan_sosial', kolom)) {
      console.log(`  ✔️  bantuan_sosial.${kolom.padEnd(18)} sudah ada`);
    } else {
      await pool.query(`ALTER TABLE bantuan_sosial ADD COLUMN ${kolom} ${tipe}`);
      console.log(`  ➕  bantuan_sosial.${kolom.padEnd(18)} ditambahkan`);
      berubah++;
    }
  }

  // Melepas NOT NULL constraint pada `tahun` jika masih NOT NULL
  if (await adaKolom('bantuan_sosial', 'tahun')) {
    const nullable = await isNullable('bantuan_sosial', 'tahun');
    if (nullable) {
      console.log('  ✔️  bantuan_sosial.tahun sudah NULLABLE');
    } else {
      await pool.query('ALTER TABLE bantuan_sosial ALTER COLUMN tahun DROP NOT NULL');
      console.log('  ➕  bantuan_sosial.tahun diubah menjadi NULLABLE');
      berubah++;
    }
  }

  // Penjaga tanggal selesai >= tanggal mulai
  const cekConstraint = await pool.query(
    `SELECT 1 FROM pg_constraint WHERE conname = 'bantuan_sosial_tanggal_valid'`
  );
  if (cekConstraint.rowCount > 0) {
    console.log('  ✔️  bantuan_sosial_tanggal_valid sudah ada');
  } else {
    await pool.query(`
      ALTER TABLE bantuan_sosial ADD CONSTRAINT bantuan_sosial_tanggal_valid
      CHECK (
        tanggal_selesai IS NULL
        OR tanggal_mulai IS NULL
        OR tanggal_selesai >= tanggal_mulai
      )
    `);
    console.log('  ➕  bantuan_sosial_tanggal_valid ditambahkan');
    berubah++;
  }

  console.log('\n════════════════════════════════════════════════════');
  if (berubah === 0) {
    console.log('✅ Skema bantuan_sosial sudah sesuai. Tidak ada yang perlu diubah.');
  } else {
    console.log(`✅ Selesai — ${berubah} perubahan diterapkan.`);
  }
  console.log('════════════════════════════════════════════════════\n');
}

jalankan()
  .catch((e) => {
    console.error('\n❌ Migrasi v26 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
