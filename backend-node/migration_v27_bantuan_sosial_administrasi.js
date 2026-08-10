/**
 * Migrasi v27 — Modul Bantuan Sosial Administrasi RT.
 *
 * Menambahkan kolom pendukung administrasi RT ke tabel `bantuan_sosial`:
 * - `bentuk_bantuan VARCHAR(50) DEFAULT 'Tunai'`
 * - `sumber_bantuan VARCHAR(100) DEFAULT 'Pemerintah Pusat'`
 * - `no_sk VARCHAR(100)`
 *
 * Idempoten: aman dijalankan berulang.
 *
 *   node migration_v27_bantuan_sosial_administrasi.js
 */
require('dotenv').config();
const { pool } = require('./src/config/database');

const KOLOM_BARU = [
  ['bentuk_bantuan', "VARCHAR(50) DEFAULT 'Tunai'"],
  ['sumber_bantuan', "VARCHAR(100) DEFAULT 'Pemerintah Pusat'"],
  ['no_sk', 'VARCHAR(100)'],
];

async function adaKolom(tabel, kolom) {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rowCount > 0;
}

async function jalankan() {
  let berubah = 0;

  console.log('\n── Memeriksa skema bantuan_sosial (v27) ──────────────');

  for (const [kolom, tipe] of KOLOM_BARU) {
    if (await adaKolom('bantuan_sosial', kolom)) {
      console.log(`  ✔️  bantuan_sosial.${kolom.padEnd(18)} sudah ada`);
    } else {
      await pool.query(`ALTER TABLE bantuan_sosial ADD COLUMN ${kolom} ${tipe}`);
      console.log(`  ➕  bantuan_sosial.${kolom.padEnd(18)} ditambahkan`);
      berubah++;
    }
  }

  console.log('════════════════════════════════════════════════════');
  if (berubah === 0) {
    console.log('✅ Skema bantuan_sosial v27 sudah sesuai. Tidak ada yang perlu diubah.');
  } else {
    console.log(`✅ Selesai — ${berubah} perubahan diterapkan.`);
  }
  console.log('════════════════════════════════════════════════════\n');
}

jalankan()
  .catch((e) => {
    console.error('\n❌ Migrasi v27 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
