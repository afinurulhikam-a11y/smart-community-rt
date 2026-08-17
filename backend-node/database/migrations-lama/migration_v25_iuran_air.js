/**
 * Migrasi v25 — memisahkan bacaan meteran dari tagihan.
 *
 * ===================================================================
 * Kenapa bacaan meteran butuh tabelnya sendiri
 * ===================================================================
 *
 * Warga mengisi meteran tanggal 1–5. Tagihan baru diterbitkan tanggal 25.
 * Kalau bacaannya ditulis ke `bills`, warga membutuhkan baris yang belum ada
 * saat ia mengisi — ayam dan telur.
 *
 * Keduanya memang hal yang berbeda, dan siklus hidupnya berbeda:
 *
 *   bacaan  : lahir tgl 1, catatan pemakaian, tidak pernah jadi tunggakan,
 *             tidak boleh hilang walau tagihannya dihapus
 *   tagihan : lahir tgl 25, kewajiban membayar, muncul di tunggakan,
 *             boleh dihapus dan dibuat ulang
 *
 * Proyek ini SUDAH memakai pemisahan yang sama untuk uang:
 * `payment_transactions` mencatat percobaan, `bill_payments` mencatat uang yang
 * benar-benar diterima. Justru pemisahan itu yang membuat tagihan bisa tetap
 * belum lunas sementara pembayaran sedang berjalan.
 *
 * Pilihan lain — menerbitkan tagihan "draf" tanggal 1 lalu memfinalisasinya —
 * ditolak. Draf itu akan bocor ke setiap kueri yang sudah ada: getBillStats
 * (kartu Tunggakan), daftar warga, kartu dashboard, export Excel dan PDF, serta
 * penagihan WhatsApp. Semuanya perlu `AND status <> 'draf'`, dan satu saja yang
 * terlewat menghasilkan angka salah tanpa gejala apa pun.
 *
 * ===================================================================
 * Kenapa bacaan mundur BOLEH tersimpan di sini
 * ===================================================================
 *
 * `bills` dijaga CHECK `bills_meteran_maju` sejak v24 — tagihan tidak boleh
 * pernah memuat angka tidak wajar. Tabel ini justru sebaliknya: bacaan mundur
 * harus bisa tersimpan supaya bisa DIPERIKSA pengurus. Yang menandainya adalah
 * `status = 'anomali'`, bukan penolakan database.
 *
 * Menolaknya di sini berarti warga yang salah ketik tidak punya cara melapor,
 * dan angkanya hilang begitu saja.
 *
 * Idempoten: memeriksa dulu, aman dijalankan berulang, tidak menyentuh satu
 * baris data pun. Jalankan terhadap SETIAP database — termasuk Railway.
 *
 *   node migration_v25_iuran_air.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v25_iuran_air');

const { pool } = require('../../src/config/database');

/** Kolom tambahan pada tabel yang sudah ada. */
const KOLOM_TAMBAHAN = [
  // Referensi UI menampilkan "Blok Rumah C54". Diambil dari data pelanggan,
  // BUKAN dari `visitors.blok_tujuan` yang milik modul tamu dan tidak
  // berhubungan dengan pelanggan air.
  ['keluarga', 'blok', 'VARCHAR(20)'],

  // Layanan sampah opsional per rumah. Bawaan `true` menjaga perilaku sekarang:
  // seluruh tagihan yang sudah ada memang memuat biaya sampah.
  ['keluarga', 'langganan_sampah', 'BOOLEAN NOT NULL DEFAULT true'],

  // Snapshot langganan saat tagihan terbit. Tanpa ini, warga yang berhenti
  // berlangganan bulan depan akan membuat tagihan bulan ini ikut berubah saat
  // dibaca ulang — riwayat menulis ulang dirinya sendiri.
  ['bills', 'langganan_sampah', 'BOOLEAN'],
];

async function adaKolom(tabel, kolom) {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rowCount > 0;
}

async function adaTabel(nama) {
  const r = await pool.query('SELECT to_regclass($1) AS t', [`public.${nama}`]);
  return r.rows[0].t !== null;
}

async function adaConstraint(nama) {
  const r = await pool.query('SELECT 1 FROM pg_constraint WHERE conname = $1', [nama]);
  return r.rowCount > 0;
}

async function jalankan() {
  let berubah = 0;

  console.log('\n── Tabel pembacaan_meteran ─────────────────────────');
  if (await adaTabel('pembacaan_meteran')) {
    console.log('  ✔️  pembacaan_meteran sudah ada');
  } else {
    await pool.query(`
      CREATE TABLE pembacaan_meteran (
        id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        keluarga_id       INTEGER NOT NULL REFERENCES keluarga(id) ON DELETE CASCADE,
        periode           VARCHAR(7)  NOT NULL,
        meteran_lalu      INTEGER,
        meteran_sekarang  INTEGER,
        status            VARCHAR(20) NOT NULL DEFAULT 'menunggu',
        catatan           TEXT,
        diisi_oleh        UUID REFERENCES users(id) ON DELETE SET NULL,
        diisi_pada        TIMESTAMP,
        dikoreksi_oleh    UUID REFERENCES users(id) ON DELETE SET NULL,
        dikoreksi_pada    TIMESTAMP,
        bill_id           UUID REFERENCES bills(id) ON DELETE SET NULL,
        created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log('  ➕  pembacaan_meteran dibuat');
    berubah++;
  }

  // Satu bacaan per rumah per periode. Inilah penjaga idempotensi di sisi
  // bacaan, sejajar dengan bills_kk_jenis_bulan_uniq di sisi tagihan — dan yang
  // membuat POST /meteran bisa dipanggil berulang tanpa menggandakan.
  if (await adaConstraint('pembacaan_meteran_kk_periode_uniq')) {
    console.log('  ✔️  pembacaan_meteran_kk_periode_uniq sudah ada');
  } else {
    await pool.query(`
      ALTER TABLE pembacaan_meteran
      ADD CONSTRAINT pembacaan_meteran_kk_periode_uniq UNIQUE (keluarga_id, periode)
    `);
    console.log('  ➕  pembacaan_meteran_kk_periode_uniq ditambahkan');
    berubah++;
  }

  if (await adaConstraint('pembacaan_meteran_status_sah')) {
    console.log('  ✔️  pembacaan_meteran_status_sah sudah ada');
  } else {
    await pool.query(`
      ALTER TABLE pembacaan_meteran
      ADD CONSTRAINT pembacaan_meteran_status_sah
      CHECK (status IN ('menunggu', 'terisi', 'anomali'))
    `);
    console.log('  ➕  pembacaan_meteran_status_sah ditambahkan');
    berubah++;
  }

  // Kolom panas: finalisasi membaca seluruh bacaan satu periode sekaligus, dan
  // pengisian membaca periode sebelumnya milik satu rumah.
  const indeks = await pool.query(
    `SELECT 1 FROM pg_indexes WHERE indexname = 'pembacaan_meteran_periode_idx'`
  );
  if (indeks.rowCount > 0) {
    console.log('  ✔️  pembacaan_meteran_periode_idx sudah ada');
  } else {
    await pool.query(
      'CREATE INDEX pembacaan_meteran_periode_idx ON pembacaan_meteran (periode, status)'
    );
    console.log('  ➕  pembacaan_meteran_periode_idx ditambahkan');
    berubah++;
  }

  console.log('\n── Kolom tambahan ──────────────────────────────────');
  for (const [tabel, kolom, tipe] of KOLOM_TAMBAHAN) {
    if (await adaKolom(tabel, kolom)) {
      console.log(`  ✔️  ${tabel}.${kolom.padEnd(18)} sudah ada`);
      continue;
    }
    await pool.query(`ALTER TABLE ${tabel} ADD COLUMN ${kolom} ${tipe}`);
    console.log(`  ➕  ${tabel}.${kolom.padEnd(18)} ditambahkan`);
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
