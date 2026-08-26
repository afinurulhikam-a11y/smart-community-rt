/**
 * Migrasi v46 — membuang tagihan yang jenis iurannya milik RT lain.
 *
 * ===================================================================
 * Cacat yang dibersihkan migrasi ini
 * ===================================================================
 *
 * v45 memberi tiap RT satu `jenis_iuran` sendiri. Yang tidak ikut disesuaikan
 * adalah `terbitkanTagihanPeriode()`, yang sejak awal menagih SELURUH kartu
 * keluarga — jawaban yang benar sewaktu jenis iuran hanya ada satu untuk
 * seluruh RW, dan menjadi cacat mahal begitu ada dua.
 *
 * Penjadwal melooping setiap jenis bermeteran yang aktif, dan tiap putaran
 * menagih seluruh RW. Pada dua RT hasilnya: 14 kartu keluarga menerima 28
 * tagihan, separuhnya memakai TARIF PER M3 milik RT tetangga.
 *
 * Ia tidak berbunyi sama sekali. `bills_kk_jenis_bulan_uniq` menjaga keunikan
 * per (keluarga, JENIS, bulan), sehingga dua jenis berbeda memang sah punya
 * dua baris — idempotensinya bekerja sempurna sambil menagih dua kali. Dan ia
 * berjalan sendiri: penjadwal terbit tiap tanggal 25 tanpa ada yang menekan
 * tombol.
 *
 * Pencegahannya ada di `tagihan-air.service.js` (kartu keluarga disaring ke
 * RT pemilik jenis iurannya). Berkas ini membersihkan yang terlanjur terbit.
 *
 * ===================================================================
 * Tagihan yang sudah ada uangnya TIDAK disentuh
 * ===================================================================
 *
 * Menghapusnya berarti menghilangkan tagihan sementara pembayarannya tetap
 * ada — pembayaran tanpa tagihan, persis bentuk kerusakan yang
 * `periksa-kesehatan.js` dibuat untuk menemukan. Migrasi ini berhenti dan
 * menyebutkan barisnya satu per satu supaya diputuskan manusia; mana yang
 * benar bergantung pada uang siapa yang sudah berpindah, dan itu bukan
 * pertanyaan yang boleh dijawab sebuah skrip.
 *
 * Idempoten: dijalankan ulang tidak menemukan apa-apa lagi.
 *
 *   node database/migrations/migration_v46_bersihkan_tagihan_lintas_rt.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v46_bersihkan_tagihan_lintas_rt');

const { pool } = require('../../src/config/database');

/** Tagihan yang jenis iurannya bukan milik RT kartu keluarganya. */
const SQL_LINTAS_RT = `
  SELECT b.id, b.bulan, b.status, b.nominal, k.no_kk,
         rk.kode AS rt_kk, rj.kode AS rt_jenis,
         (SELECT COUNT(*)::int FROM bill_payments bp WHERE bp.bill_id = b.id) AS jumlah_bayar,
         (SELECT COUNT(*)::int FROM payment_transaction_bills ptb WHERE ptb.bill_id = b.id) AS jumlah_trx
    FROM bills b
    JOIN keluarga k     ON k.id  = b.keluarga_id
    JOIN rt rk          ON rk.id = k.rt_id
    JOIN jenis_iuran ji ON ji.id = b.jenis_iuran_id
    JOIN rt rj          ON rj.id = ji.rt_id
   WHERE rk.id IS DISTINCT FROM rj.id
   ORDER BY b.bulan, k.no_kk
`;

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v46: membuang tagihan lintas RT...');
    await client.query('BEGIN');

    const salah = await client.query(SQL_LINTAS_RT);
    if (salah.rowCount === 0) {
      await client.query('COMMIT');
      console.log('✅ Migrasi v46 selesai: tidak ada tagihan lintas RT.');
      return;
    }

    const adaUang = salah.rows.filter(
      (r) => r.status === 'paid' || r.jumlah_bayar > 0 || r.jumlah_trx > 0
    );

    console.log(`  ditemukan ${salah.rowCount} tagihan lintas RT`);
    if (adaUang.length) {
      console.error(`\n❌ ${adaUang.length} di antaranya SUDAH ADA PEMBAYARANNYA:\n`);
      for (const r of adaUang) {
        console.error(
          `   ${r.bulan}  KK ${r.no_kk} (RT ${r.rt_kk})  ditagih pakai jenis RT ${r.rt_jenis}  `
          + `Rp${r.nominal}  status=${r.status}  bayar=${r.jumlah_bayar} trx=${r.jumlah_trx}  id=${r.id}`
        );
      }
      throw new Error(
        'Ada tagihan lintas RT yang sudah ada uangnya. Migrasi dibatalkan seluruhnya — '
        + 'putuskan manual mana yang dipertahankan sebelum menjalankannya lagi.'
      );
    }

    const hapus = await client.query(`
      DELETE FROM bills b
       USING keluarga k, rt rk, jenis_iuran ji, rt rj
       WHERE k.id  = b.keluarga_id
         AND rk.id = k.rt_id
         AND ji.id = b.jenis_iuran_id
         AND rj.id = ji.rt_id
         AND rk.id IS DISTINCT FROM rj.id
    `);

    // Bacaan meteran yang tertaut ke tagihan yang baru dibuang harus ikut
    // dilepas. FK-nya ON DELETE SET NULL sudah melakukannya, tetapi bacaan
    // ber-`bill_id` kosong berarti warga bisa mengubahnya lagi — dan itu
    // memang yang benar di sini: tagihannya salah, jadi bacaannya memang
    // belum pernah ditagihkan dengan sah.
    const lepas = await client.query(
      `SELECT COUNT(*)::int AS n FROM pembacaan_meteran WHERE bill_id IS NULL`
    );

    await client.query('COMMIT');
    console.log(
      `✅ Migrasi v46 selesai: ${hapus.rowCount} tagihan lintas RT dibuang `
      + `(${lepas.rows[0].n} bacaan meteran kini tanpa tagihan).`
    );
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v46:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
