/**
 * Pencabutan sesi — `users.token_versi`.
 *
 * ===================================================================
 * Masalah yang ditutup
 * ===================================================================
 *
 * Sampai sebelum migrasi ini, menekan "Keluar" tidak mencabut apa pun. Tidak
 * ada endpoint logout, tidak ada jti, blacklist, maupun revoke di seluruh
 * `src/`. Klien hanya menghapus token dari perangkatnya sendiri — dan token
 * yang sempat disalin sebelum itu tetap dijawab 200 sampai kedaluwarsa
 * alaminya.
 *
 * Umurnya sudah dipersingkat menjadi 24 jam (Fase A), tetapi "24 jam tanpa
 * satu pun cara menghentikan" tetap bukan jawaban untuk kekhawatiran yang
 * ditulis proyek ini sendiri: pengurus yang ketahuan menyalahgunakan wewenang
 * harus bisa dihentikan SEKETIKA.
 *
 * `token_versi` adalah tombol itu. JWT membawa klaim `tv`; middleware menolak
 * bila `tv` tidak sama dengan `users.token_versi`; logout menaikkannya satu.
 *
 * ===================================================================
 * Kenapa INTEGER, bukan `token_valid_sejak TIMESTAMP`
 * ===================================================================
 *
 * Rancangan timestamp membandingkan `iat` token dengan sebuah waktu di
 * database. Dua nilai itu berasal dari DUA JAM YANG BERBEDA — `iat` dari jam
 * proses Node, `NOW()` dari jam Postgres. Di satu mesin selisihnya terukur
 * 15 ms; di Railway keduanya kontainer terpisah dan tidak ada yang menjamin
 * keduanya sinkron. `iat` juga berpresisi DETIK sementara `NOW()` mikrodetik.
 *
 * Akibatnya ada satu cacat yang tidak bisa ditambal tanpa menukarnya dengan
 * cacat lain: seseorang yang logout lalu LOGIN ULANG PADA DETIK YANG SAMA
 * mendapat token ber-`iat` sama dengan detik pencabutan — dan tokennya yang
 * sah ikut tertolak. Menambal dengan `date_trunc + 1 detik` justru membuat
 * seluruh login pada detik itu gagal.
 *
 * Perbandingan bilangan bulat menghapus seluruh kelas masalah itu. Versi baru
 * dibaca dari database tepat pada saat token diterbitkan, jadi token sah yang
 * baru lahir tidak mungkin tertolak. Nol ketergantungan pada jam mana pun.
 *
 * Yang hilang: kolom ini tidak menyimpan KAPAN pencabutan terjadi. Itu
 * diterima — jejaknya sudah ada di `activity_logs`, yang append-only.
 *
 * ===================================================================
 * Baris lama dan token yang sedang beredar
 * ===================================================================
 *
 * Kolomnya lahir `0` untuk semua orang, dan middleware membaca token tanpa
 * klaim `tv` sebagai `0` juga. Keduanya cocok, jadi MIGRASI INI TIDAK
 * MENGELUARKAN SIAPA PUN. Token Fase A yang sedang beredar tetap berlaku
 * sampai pemiliknya menekan Keluar, atau sampai kedaluwarsa sendiri.
 *
 * Idempoten: aman dijalankan berulang.
 *
 *   node migration_v29_token_versi.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v29');

const { pool } = require('../../src/config/database');

const TABEL = 'users';
const KOLOM = 'token_versi';

async function adaKolom(tabel, kolom) {
  const r = await pool.query(
    `SELECT data_type, is_nullable, column_default
     FROM information_schema.columns
     WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rows[0] || null;
}

async function jalankan() {
  let perubahan = 0;

  console.log('\n── Kolom versi token ───────────────────────────────');

  const kolom = await adaKolom(TABEL, KOLOM);
  if (kolom) {
    console.log(`  ✔️  ${TABEL}.${KOLOM} sudah ada`
      + ` (${kolom.data_type}, nullable=${kolom.is_nullable}, default=${kolom.column_default})`);
  } else {
    // NOT NULL DEFAULT 0 sekaligus: tidak ada baris yang boleh berakhir NULL,
    // karena `tv !== null` selalu benar dan itu akan mengeluarkan semua orang.
    await pool.query(
      `ALTER TABLE ${TABEL} ADD COLUMN ${KOLOM} INTEGER NOT NULL DEFAULT 0`
    );
    console.log(`  ➕  ${TABEL}.${KOLOM} ditambahkan (INTEGER NOT NULL DEFAULT 0)`);
    perubahan += 1;
  }

  // Pemeriksaan yang benar-benar penting: tidak boleh ada satu pun NULL, dan
  // seluruh baris lama harus berada di versi 0 supaya token yang beredar
  // sekarang (tanpa klaim `tv`, dibaca sebagai 0) tetap cocok.
  const ringkas = await pool.query(
    `SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE ${KOLOM} IS NULL)::int AS kosong,
            COUNT(*) FILTER (WHERE ${KOLOM} <> 0)::int AS bukan_nol
     FROM ${TABEL}`
  );
  const { total, kosong, bukan_nol: bukanNol } = ringkas.rows[0];

  console.log('\n── Dampak ke sesi yang sedang berjalan ─────────────');
  console.log(`  Akun          : ${total}`);
  console.log(`  ${KOLOM} NULL : ${kosong}  (harus 0)`);
  console.log(`  ${KOLOM} ≠ 0  : ${bukanNol}  (akun yang pernah logout)`);

  if (kosong > 0) {
    throw new Error(`${kosong} baris ber-${KOLOM} NULL — token siapa pun akan tertolak.`);
  }
  console.log('  → Token yang sedang beredar tetap berlaku. Tidak ada yang dikeluarkan.');

  console.log(`\n${'═'.repeat(52)}`);
  console.log(perubahan === 0
    ? '✅ Skema sudah sesuai. Tidak ada yang perlu diubah.'
    : `✅ Selesai — ${perubahan} perubahan diterapkan.`);
  console.log('═'.repeat(52));
}

jalankan()
  .catch((e) => {
    console.error('❌ Migrasi v29 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
