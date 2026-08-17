/**
 * Tiket unduh sekali pakai — mengeluarkan token sesi dari URL.
 *
 * ===================================================================
 * Masalah yang ditutup
 * ===================================================================
 *
 * Setiap tombol Export/Unduh di aplikasi ini membuka URL lewat `launchUrl`,
 * dan sebuah NAVIGASI TIDAK BISA MEMBAWA HEADER. Karena itu klien menempelkan
 * `?token=<jwt>` ke URL-nya — sembilan tempat, pola seragam.
 *
 * Akibatnya kredensial sesi berumur 24 jam ikut tercatat di:
 *   - log akses server dan setiap proxy di jalur (Railway mencatat URL penuh),
 *   - riwayat browser,
 *   - header `Referer` bila halaman hasilnya memuat tautan keluar.
 *
 * Tiket menggantikannya: satu nilai acak, berumur 60 detik, sekali pakai, dan
 * tidak memberi akses ke apa pun selain satu unduhan yang sudah ditentukan.
 * Yang bocor ke log menjadi tiket mati, bukan sesi.
 *
 * ===================================================================
 * Kenapa yang disimpan hash, bukan tiketnya
 * ===================================================================
 *
 * Sama seperti kata sandi. Bila isi tabel ini bocor — dump, backup yang salah
 * taruh, atau `GET /reset/cadangan` yang jatuh ke tangan keliru — pemegangnya
 * tidak mendapat satu unduhan pun, karena yang ada padanya SHA-256, sedangkan
 * yang diminta endpoint adalah pra-citranya.
 *
 * Tiket mentah karena itu hanya sekali dikembalikan ke klien, dan tidak pernah
 * bisa ditampilkan ulang.
 *
 * ===================================================================
 * Kenapa `token_versi` ikut disalin ke sini
 * ===================================================================
 *
 * Tanpa kolom ini, tiket berumur 60 detik bisa HIDUP LEBIH LAMA DARIPADA
 * SESINYA SENDIRI: pengguna menekan Keluar, seluruh tokennya mati, tetapi
 * tautan unduhan yang terlanjur dibuat masih menyerahkan berkas berisi data
 * warga. Enam puluh detik memang pendek — tetapi "pendek" bukan alasan
 * membiarkan satu jalur mengabaikan pencabutan yang baru saja diminta.
 *
 * Penukaran membandingkan `tiket_unduh.token_versi` dengan `users.token_versi`
 * saat itu juga. Berbeda → tiket mati.
 *
 * ===================================================================
 * Kenapa `dipakai_pada` NULLABLE, bukan `sudah_dipakai BOOLEAN`
 * ===================================================================
 *
 * Alasan yang sama seperti v28: timestamp menjawab "sudah atau belum" (NULL =
 * belum) sekaligus menyimpan kapan, tanpa kolom kedua. Dan yang menjadikannya
 * sekali pakai bukan kolomnya melainkan `UPDATE … WHERE dipakai_pada IS NULL`
 * — pola atomik yang sama dengan `payBill`: dua permintaan bersamaan, hanya
 * satu yang mendapat baris.
 *
 * Idempoten: aman dijalankan berulang.
 *
 *   node migration_v30_tiket_unduh.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v30');

const { pool } = require('./src/config/database');

const TABEL = 'tiket_unduh';
const INDEKS_SAPU = 'tiket_unduh_kedaluwarsa_idx';

async function adaTabel(nama) {
  const r = await pool.query(
    `SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = $1`,
    [nama]
  );
  return r.rowCount > 0;
}

async function adaIndeks(nama) {
  const r = await pool.query('SELECT 1 FROM pg_indexes WHERE indexname = $1', [nama]);
  return r.rowCount > 0;
}

async function jalankan() {
  let perubahan = 0;

  console.log('\n── Tabel tiket unduh ───────────────────────────────');

  if (await adaTabel(TABEL)) {
    console.log(`  ✔️  ${TABEL} sudah ada`);
  } else {
    await pool.query(`
      CREATE TABLE ${TABEL} (
        tiket_hash   VARCHAR(64) PRIMARY KEY,
        user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token_versi  INTEGER NOT NULL,
        jenis        VARCHAR(60) NOT NULL,
        parameter    JSONB NOT NULL DEFAULT '{}'::jsonb,
        kedaluwarsa  TIMESTAMPTZ NOT NULL,
        dipakai_pada TIMESTAMPTZ,
        created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log(`  ➕  ${TABEL} dibuat`);
    perubahan += 1;
  }

  // ON DELETE CASCADE dipilih sadar: menghapus akun harus tetap mungkin.
  // `users` sudah dipegang delapan tabel ber-RESTRICT (lihat reset-groups.js);
  // menambah yang kesembilan berarti satu tautan unduhan berumur 60 detik bisa
  // menghalangi penghapusan akun selamanya. Tiket bukan catatan yang perlu
  // diawetkan — jejak siapa mengunduh apa ada di `activity_logs`.

  console.log('\n── Indeks penyapuan ────────────────────────────────');

  if (await adaIndeks(INDEKS_SAPU)) {
    console.log(`  ✔️  ${INDEKS_SAPU} sudah ada`);
  } else {
    // Satu-satunya kueri selain lookup primary key adalah pembersihan baris
    // mati. Tidak ada indeks untuk `user_id` karena tidak ada yang pernah
    // bertanya "tiket milik siapa" — penukaran selalu datang dengan hash-nya.
    await pool.query(`CREATE INDEX ${INDEKS_SAPU} ON ${TABEL} (kedaluwarsa)`);
    console.log(`  ➕  ${INDEKS_SAPU} ditambahkan`);
    perubahan += 1;
  }

  const sisa = await pool.query(
    `SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE dipakai_pada IS NULL AND kedaluwarsa > NOW())::int AS hidup
     FROM ${TABEL}`
  );
  console.log(`\n  Baris tiket: ${sisa.rows[0].total} (masih bisa ditukar: ${sisa.rows[0].hidup})`);

  console.log(`\n${'═'.repeat(52)}`);
  console.log(perubahan === 0
    ? '✅ Skema sudah sesuai. Tidak ada yang perlu diubah.'
    : `✅ Selesai — ${perubahan} perubahan diterapkan.`);
  console.log('═'.repeat(52));
}

jalankan()
  .catch((e) => {
    console.error('❌ Migrasi v30 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
