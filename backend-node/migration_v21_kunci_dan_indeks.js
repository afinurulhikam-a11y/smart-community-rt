/**
 * Migrasi v21 — jaring pengaman konkurensi dan indeks kolom panas.
 *
 * ===================================================================
 * Bagian 1: constraint yang menjadi jaring pengaman
 * ===================================================================
 *
 * Kode aplikasi sudah diperbaiki (kunci baris `FOR UPDATE` pada payBill,
 * pemeriksaan ulang status di dalam transaksi). Constraint di bawah ini bukan
 * pengganti perbaikan itu — ia lapisan yang tetap berlaku ketika perbaikannya
 * kelak tidak sengaja terhapus, atau ketika jalur baru ditulis tanpa mengingat
 * aturannya.
 *
 * Pola "periksa dulu lalu tulis" tidak pernah aman sendirian. Dua permintaan
 * bisa sama-sama lolos pemeriksaan sebelum salah satunya sempat menulis.
 * Satu-satunya yang benar-benar mengakhiri perlombaan itu adalah database.
 *
 * ===================================================================
 * Bagian 2: indeks
 * ===================================================================
 *
 * `visitors` sama sekali tidak punya indeks selain primary key, padahal ia
 * tumbuh paling cepat — satu baris per tamu per hari — dan disaring pada setiap
 * pemakaian. Tidak terasa pada puluhan baris; menjadi sumber lambat yang
 * dominan setelah setahun.
 *
 * (`patrol_attendances` dulu disebut di sini dengan alasan yang sama. Modul
 * ronda dihapus total pada commit `dd9104a`; bagiannya ikut dibuang dari berkas
 * ini, karena kueri ke tabel yang tidak ada menghentikan seluruh migrasi.)
 *
 * Idempoten: aman dijalankan berulang.
 */
require('dotenv').config();
const { pool } = require('./src/config/database');

async function jalankan() {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // -----------------------------------------------------------------
    // 1. Satu pembayaran per tagihan
    // -----------------------------------------------------------------
    //
    // `bill_payments` tidak punya batasan apa pun pada `bill_id`, sementara
    // `payment_transaction_bills` sudah lama punya `payment_bill_pending_uniq`
    // untuk jalur Midtrans. Sisi tunai justru yang tidak dijaga.
    //
    // Baris ganda yang mungkin sudah terlanjur ada dibiarkan — menghapusnya
    // berarti menghapus catatan uang, dan itu keputusan yang harus diambil
    // manusia dengan bukti di tangan, bukan oleh skrip migrasi. Indeksnya
    // dibuat CONCURRENTLY-tidak, tetapi kalau gagal karena duplikat, pesannya
    // memberi tahu persis baris mana yang harus diperiksa lebih dulu.
    const ganda = await client.query(`
      SELECT bill_id, COUNT(*)::int AS jumlah
      FROM bill_payments
      GROUP BY bill_id
      HAVING COUNT(*) > 1
    `);

    if (ganda.rows.length > 0) {
      console.log(`  ⚠️  ${ganda.rows.length} tagihan punya lebih dari satu pembayaran:`);
      for (const r of ganda.rows) console.log(`      bill_id ${r.bill_id} — ${r.jumlah} pembayaran`);
      console.log('      Constraint TIDAK dipasang. Periksa baris di atas lebih dulu;');
      console.log('      kemungkinan besar itu dobel-posting ke Kas RT yang perlu dikoreksi.');
    } else {
      await client.query(`
        CREATE UNIQUE INDEX IF NOT EXISTS bill_payments_satu_per_tagihan
          ON bill_payments (bill_id)
      `);
      console.log('  ✅ bill_payments: satu pembayaran per tagihan');
    }

    // -----------------------------------------------------------------
    // 2. Satu absensi ronda aktif per petugas per hari
    // -----------------------------------------------------------------
    //
    // `submitAttendance` memeriksa "sudah absen masuk hari ini?" dengan SELECT
    // biasa lalu INSERT terpisah. Dua ketukan beruntun — QR yang gagal terbaca
    // lalu dicoba lagi — bisa menghasilkan dua baris "Aktif Ronda" sekaligus.
    // Indeks parsial ini hanya membatasi yang BELUM pulang, sehingga absensi
    // hari-hari sebelumnya tetap bisa berdampingan.
    // Di sini dulu dipasang `patrol_absensi_aktif_uniq` pada
    // `patrol_attendances`. Modul ronda dihapus total pada commit `dd9104a`,
    // tabelnya ikut di-DROP, dan kueri ini menjadi penyebab migrasi berhenti
    // di tengah — bukan sekadar baris mati.

    // -----------------------------------------------------------------
    // 3. Indeks kolom panas
    // -----------------------------------------------------------------
    const indeks = [
      // Dikorelasikan pada setiap baris daftar tagihan lewat LEFT JOIN LATERAL.
      ['idx_bill_payments_bill', 'bill_payments (bill_id)'],

      // visitors: nol indeks sebelumnya. Tabel dengan laju tulis tertinggi.
      // `jam_masuk::DATE` disaring dengan cast, jadi indeksnya pun harus atas
      // ekspresi yang sama — indeks biasa pada jam_masuk tidak akan terpakai.
      ['idx_visitors_status', 'visitors (status)'],
      ['idx_visitors_tipe', 'visitors (tipe_keperluan)'],
      ['idx_visitors_tanggal', 'visitors ((jam_masuk::date))'],
      ['idx_visitors_pembuat', 'visitors (created_by)'],

      // Dua indeks patrol_attendances dihapus bersama modul ronda (dd9104a).

      // Penyempitan baris untuk warga di masing-masing modul.
      ['idx_complaints_user', 'complaints (user_id)'],
      ['idx_complaints_status', 'complaints (status)'],
      ['idx_letters_user', 'letters (user_id)'],
      ['idx_letters_status', 'letters (status)'],
      ['idx_borrowings_user', 'borrowings (user_id)'],
      ['idx_payment_trx_user', 'payment_transactions (user_id)'],

      // Setiap pencarian anggota sebuah kartu keluarga.
      ['idx_anggota_keluarga_kk', 'anggota_keluarga (keluarga_id)'],

      // getPolling mengambil opsi per polling.
      ['idx_polling_options_polling', 'polling_options (polling_id)'],
    ];

    for (const [nama, definisi] of indeks) {
      await client.query(`CREATE INDEX IF NOT EXISTS ${nama} ON ${definisi}`);
    }
    console.log(`  ✅ ${indeks.length} indeks siap`);

    await client.query('COMMIT');
    console.log('\nMigrasi v21 selesai.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v21 dibatalkan:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

jalankan();
