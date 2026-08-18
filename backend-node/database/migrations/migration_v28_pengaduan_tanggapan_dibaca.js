/**
 * Penanda "tanggapan pengaduan sudah dibaca warga".
 *
 * ===================================================================
 * Kenapa satu kolom NULLABLE, bukan boolean `sudah_dibaca`
 * ===================================================================
 *
 * Boolean hanya bisa menjawab "sudah atau belum". Timestamp menjawab itu juga
 * — NULL berarti belum — sekaligus menyimpan KAPAN, yang berguna saat pengurus
 * bertanya "apakah warga sudah membaca jawaban saya?" tanpa perlu kolom kedua.
 *
 * ===================================================================
 * Kenapa dikosongkan ulang setiap kali pengurus menanggapi
 * ===================================================================
 *
 * Sebuah pengaduan bisa ditanggapi berkali-kali: "Diproses" hari ini, lalu
 * "Selesai" minggu depan dengan penjelasan berbeda. Kalau penandanya sekali
 * pasang seumur hidup baris, tanggapan kedua tidak akan pernah terlihat baru —
 * warga sudah membaca yang pertama, dan aplikasinya menganggap urusan selesai.
 *
 * Karena itu `updateComplaintStatus` menyetelnya kembali ke NULL setiap kali ia
 * menulis tanggapan. "Belum dibaca" berarti: ADA tanggapan, dan warga belum
 * membukanya SEJAK tanggapan terakhir.
 *
 * Turunannya tidak disimpan. Belum-dibaca selalu bisa dihitung dari
 * `response IS NOT NULL AND tanggapan_dibaca_pada IS NULL`, dan menyimpan
 * turunan berarti membuka kemungkinan ia berbeda dari bahan penyusunnya.
 *
 * ===================================================================
 * Baris lama
 * ===================================================================
 *
 * Kolomnya lahir NULL untuk semua baris — termasuk pengaduan yang sudah
 * ditanggapi jauh sebelum migrasi ini. Artinya tanggapan lama akan muncul
 * sebagai "baru" satu kali. Itu disengaja dan dipilih sadar: kebalikannya
 * (menganggap semuanya sudah dibaca) akan MENYEMBUNYIKAN tanggapan yang
 * mungkin memang belum pernah dilihat warga — dan penanda yang diam ketika
 * seharusnya menyala lebih buruk daripada penanda yang sekali muncul berlebih.
 *
 * Idempoten: aman dijalankan berulang.
 *
 *   node migration_v28_pengaduan_tanggapan_dibaca.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v28');

const { pool } = require('../../src/config/database');

const TABEL = 'complaints';
const KOLOM = 'tanggapan_dibaca_pada';
const INDEKS = 'complaints_tanggapan_belum_dibaca_idx';

async function adaKolom(tabel, kolom) {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rowCount > 0;
}

async function adaIndeks(nama) {
  const r = await pool.query('SELECT 1 FROM pg_indexes WHERE indexname = $1', [nama]);
  return r.rowCount > 0;
}

async function jalankan() {
  let perubahan = 0;

  console.log('\n── Kolom penanda tanggapan dibaca ──────────────────');

  if (await adaKolom(TABEL, KOLOM)) {
    console.log(`  ✔️  ${TABEL}.${KOLOM} sudah ada`);
  } else {
    await pool.query(`ALTER TABLE ${TABEL} ADD COLUMN ${KOLOM} TIMESTAMP`);
    console.log(`  ➕  ${TABEL}.${KOLOM} ditambahkan`);
    perubahan += 1;
  }

  console.log('\n── Indeks parsial untuk lencana dasbor ─────────────');

  if (await adaIndeks(INDEKS)) {
    console.log(`  ✔️  ${INDEKS} sudah ada`);
  } else {
    // Parsial, bukan indeks biasa: dasbor hanya pernah menanyakan baris yang
    // PUNYA tanggapan dan BELUM dibaca. Itu bagian terkecil dari tabel, dan
    // indeks parsial membuat ukurannya sepadan dengan pertanyaannya — bukan
    // dengan besarnya tabel.
    await pool.query(`
      CREATE INDEX ${INDEKS} ON ${TABEL} (user_id)
      WHERE response IS NOT NULL AND ${KOLOM} IS NULL AND deleted_at IS NULL
    `);
    console.log(`  ➕  ${INDEKS} ditambahkan`);
    perubahan += 1;
  }

  const belum = await pool.query(
    `SELECT COUNT(*)::int AS n FROM ${TABEL}
     WHERE response IS NOT NULL AND ${KOLOM} IS NULL AND deleted_at IS NULL`
  );
  console.log(`\n  Tanggapan yang akan tampil sebagai baru: ${belum.rows[0].n}`);
  console.log('  (baris lama sengaja dianggap belum dibaca — lihat catatan di kepala berkas)');

  console.log(`\n${'═'.repeat(52)}`);
  console.log(perubahan === 0
    ? '✅ Skema sudah sesuai. Tidak ada yang perlu diubah.'
    : `✅ Selesai — ${perubahan} perubahan diterapkan.`);
  console.log('═'.repeat(52));
}

jalankan()
  .catch((e) => {
    console.error('❌ Migrasi v28 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
