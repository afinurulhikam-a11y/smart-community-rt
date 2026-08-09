/**
 * Migrasi v24 — tagihan berbasis meteran untuk iuran air sumur bor.
 *
 * ===================================================================
 * Kenapa memperluas `bills`, bukan membuat modul sendiri
 * ===================================================================
 *
 * Tagihan air punya bentuk yang sama persis dengan iuran: satu tagihan per
 * rumah per bulan, dengan status lunas/belum, metode bayar, dan bukti. Yang
 * berbeda hanya CARA nominalnya dihitung — dari selisih meteran, bukan dari
 * angka tetap.
 *
 * Membangunnya sebagai modul terpisah berarti menulis ulang seluruh mesin yang
 * sudah ada dan sudah teruji: pembayaran Midtrans beserta empat penjaga uangnya,
 * `catatKeKasRt` beserta jejak `ref_id`-nya, layar "Tagihan Saya" milik warga,
 * kunci baris pada `payBill`, dan indeks unik `bill_payments (bill_id)`.
 *
 * Karena itu tagihan air TETAP sebuah baris `bills`. Kolom `nominal` tetap
 * menjadi totalnya, sehingga setiap jalur pembayaran bekerja tanpa diubah
 * sedikit pun.
 *
 * ===================================================================
 * Kenapa tarifnya disalin ke tiap tagihan
 * ===================================================================
 *
 * `tarif_per_m3`, `abondement`, dan `biaya_sampah` ada di DUA tempat: di
 * `jenis_iuran` sebagai nilai berlaku saat ini, dan disalin ke `bills` saat
 * tagihan diterbitkan.
 *
 * Itu bukan duplikasi yang lupa dibersihkan. Tarif air bisa naik, dan ketika
 * naik, tagihan tahun lalu TIDAK BOLEH ikut berubah — kalau dibaca ulang dari
 * master, seluruh riwayat tagihan akan menulis ulang dirinya sendiri setiap
 * kali pengurus mengubah tarif, dan warga yang sudah membayar mendadak terlihat
 * kurang bayar. Alasannya sama dengan `payment_transaction_bills.nominal` yang
 * juga disalin: yang ditagihkan harus tetap sebesar yang dijanjikan saat
 * tagihan dibuat.
 *
 * `terpakai` sengaja TIDAK disimpan — ia selalu `meteran_sekarang -
 * meteran_lalu`. Menyimpan turunan berarti membuka kemungkinan ia berbeda dari
 * bahan penyusunnya, dan tidak ada cara mengetahui mana yang benar.
 *
 * Idempoten: memeriksa dulu, aman dijalankan berulang, dan tidak menyentuh satu
 * baris data pun. Jalankan terhadap SETIAP database — termasuk Railway.
 *
 *   node migration_v24_iuran_meteran.js
 */
require('dotenv').config();
const { pool } = require('./src/config/database');

/** Kolom baru pada `jenis_iuran` — aturan tarif yang berlaku saat ini. */
const KOLOM_JENIS = [
  // 'tetap' = nominal pasti seperti iuran biasa. 'meteran' = dihitung dari
  // pemakaian. Bawaannya 'tetap' supaya seluruh jenis iuran yang sudah ada
  // berperilaku persis seperti sebelumnya.
  ['tipe_hitung', "VARCHAR(20) NOT NULL DEFAULT 'tetap'"],
  ['tarif_per_m3', 'INTEGER'],
  ['abondement', 'INTEGER NOT NULL DEFAULT 0'],
  ['biaya_sampah', 'INTEGER NOT NULL DEFAULT 0'],
];

/** Kolom baru pada `bills` — angka yang berlaku untuk tagihan ITU. */
const KOLOM_BILLS = [
  ['meteran_lalu', 'INTEGER'],
  ['meteran_sekarang', 'INTEGER'],
  ['tarif_per_m3', 'INTEGER'],
  ['abondement', 'INTEGER'],
  ['biaya_sampah', 'INTEGER'],
];

async function adaKolom(tabel, kolom) {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rowCount > 0;
}

async function tambahKolom(tabel, daftar) {
  let ditambah = 0;
  for (const [kolom, tipe] of daftar) {
    if (await adaKolom(tabel, kolom)) {
      console.log(`  ✔️  ${tabel}.${kolom.padEnd(17)} sudah ada`);
      continue;
    }
    await pool.query(`ALTER TABLE ${tabel} ADD COLUMN ${kolom} ${tipe}`);
    console.log(`  ➕  ${tabel}.${kolom.padEnd(17)} ditambahkan`);
    ditambah++;
  }
  return ditambah;
}

async function jalankan() {
  let berubah = 0;

  console.log('\n── Aturan tarif pada jenis_iuran ───────────────────');
  berubah += await tambahKolom('jenis_iuran', KOLOM_JENIS);

  console.log('\n── Angka meteran pada bills ────────────────────────');
  berubah += await tambahKolom('bills', KOLOM_BILLS);

  console.log('\n── Penjaga nilai ───────────────────────────────────');

  // Meteran tidak boleh mundur. Tanpa penjaga ini, salah ketik menghasilkan
  // pemakaian negatif, dan tagihannya menjadi lebih kecil daripada biaya tetap
  // — bahkan bisa minus. Ditulis sebagai CHECK, bukan validasi di controller
  // saja, karena impor atau perbaikan lewat SQL langsung tidak melewatinya.
  const cek = await pool.query(
    `SELECT 1 FROM pg_constraint WHERE conname = 'bills_meteran_maju'`
  );
  if (cek.rowCount > 0) {
    console.log('  ✔️  bills_meteran_maju sudah ada');
  } else {
    await pool.query(`
      ALTER TABLE bills ADD CONSTRAINT bills_meteran_maju
      CHECK (
        meteran_lalu IS NULL
        OR meteran_sekarang IS NULL
        OR meteran_sekarang >= meteran_lalu
      )
    `);
    console.log('  ➕  bills_meteran_maju ditambahkan');
    berubah++;
  }

  const cekTipe = await pool.query(
    `SELECT 1 FROM pg_constraint WHERE conname = 'jenis_iuran_tipe_hitung_sah'`
  );
  if (cekTipe.rowCount > 0) {
    console.log('  ✔️  jenis_iuran_tipe_hitung_sah sudah ada');
  } else {
    await pool.query(`
      ALTER TABLE jenis_iuran ADD CONSTRAINT jenis_iuran_tipe_hitung_sah
      CHECK (tipe_hitung IN ('tetap', 'meteran'))
    `);
    console.log('  ➕  jenis_iuran_tipe_hitung_sah ditambahkan');
    berubah++;
  }

  console.log('\n════════════════════════════════════════════════════');
  if (berubah === 0) {
    console.log('✅ Skema sudah sesuai. Tidak ada yang perlu diubah.');
  } else {
    console.log(`✅ Selesai — ${berubah} perubahan diterapkan.`);
  }
  console.log('════════════════════════════════════════════════════\n');
}

jalankan()
  .catch((e) => {
    console.error('\n❌ Migrasi gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
