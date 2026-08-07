require('dotenv').config();
const { pool } = require('./src/config/database');
const { SUMBER_WARGA } = require('./src/utils/lingkup-warga');

/**
 * Pemeriksaan kesehatan setelah sesi pengujian.
 *
 * HANYA MEMBACA. Tidak ada satu pun perintah yang mengubah data, jadi aman
 * dijalankan kapan saja — termasuk pada pemasangan sungguhan.
 *
 * Dibuat setelah sebuah sesi pengujian panjang: memeriksa keutuhan data satu
 * per satu lewat query manual memakan waktu lama dan mudah terlewat. Semua
 * pemeriksaan itu dikumpulkan di sini supaya bisa diulang dalam hitungan detik.
 *
 *   node periksa-kesehatan.js
 *
 * Keluar dengan kode 1 bila ada temuan, sehingga bisa dipakai di skrip lain.
 */

const BASE = `http://localhost:${process.env.PORT || 3001}/api`;

/** Akun bawaan seed-master. Dipakai menyapu endpoint per role. */
const AKUN = [
  ['admin', 'admin123'],
  ['ketua', 'ketua123'],
  ['sekretaris', 'sekretaris123'],
  ['bendahara', 'bendahara123'],
  ['warga', 'warga123'],
];

/** Endpoint baca yang harus selalu hidup. 403 itu wajar (izin), 404/5xx tidak. */
const ENDPOINT = [
  '/warga', '/families', '/demographics/summary', '/bills', '/bills/stats',
  '/finances', '/finances/summary', '/bop', '/bop/summary', '/alokasi-bop',
  '/kategori-kas', '/kategori-bop', '/jenis-iuran', '/inventory',
  '/inventory/borrowings', '/letters', '/complaints', '/agenda', '/announcements',
  '/polling', '/visitors', '/bantuan-sosial', '/emergency/alerts',
  '/emergency/active', '/activity-logs', '/menu-akses', '/reset/ringkasan',
  '/sensors/logs', '/users',
];

/**
 * Pemeriksaan keutuhan. Setiap query HARUS mengembalikan nol baris bila sehat —
 * jadi baris yang muncul selalu berarti masalah, tidak perlu ditafsirkan.
 */
const PERIKSA = [
  {
    nama: 'Tagihan lunas tanpa catatan pembayaran',
    kenapa: 'Uang dinyatakan diterima tetapi tidak ada buktinya.',
    sql: `SELECT b.id, b.bulan FROM bills b
          WHERE b.status = 'lunas'
            AND NOT EXISTS (SELECT 1 FROM bill_payments bp WHERE bp.bill_id = b.id)`,
  },
  {
    nama: 'Pembayaran tanpa baris Kas RT',
    kenapa: 'catatKeKasRt() gagal; pemasukan tidak muncul di buku kas.',
    sql: `SELECT bp.id, bp.jumlah_bayar FROM bill_payments bp
          WHERE NOT EXISTS (
            SELECT 1 FROM finances f WHERE f.sumber = 'iuran' AND f.ref_id = bp.id)`,
  },
  {
    nama: 'Baris Kas RT menggantung',
    kenapa: 'Baris kas menunjuk pembayaran yang sudah tidak ada.',
    sql: `SELECT f.id, f.jumlah FROM finances f
          WHERE f.sumber = 'iuran'
            AND NOT EXISTS (SELECT 1 FROM bill_payments bp WHERE bp.id = f.ref_id)`,
  },
  {
    nama: 'Pembayaran tercatat ganda di Kas RT',
    kenapa: 'finances_ref_uniq jebol; pemasukan terhitung dua kali.',
    sql: `SELECT ref_id, COUNT(*)::int AS jumlah FROM finances
          WHERE sumber = 'iuran' GROUP BY ref_id HAVING COUNT(*) > 1`,
  },
  {
    nama: 'Tagihan belum lunas tetapi punya catatan pembayaran',
    kenapa: 'Status tagihan dan catatan uangnya bertentangan.',
    sql: `SELECT b.id, b.bulan FROM bills b
          WHERE b.status <> 'lunas'
            AND EXISTS (SELECT 1 FROM bill_payments bp WHERE bp.bill_id = b.id)`,
  },
  {
    nama: 'Kunci pembayaran tertinggal',
    kenapa: 'is_pending masih true padahal transaksinya sudah selesai — '
      + 'tagihan itu tidak bisa dibayar ulang oleh warga.',
    sql: `SELECT pt.order_id, pt.status, ptb.bill_id
          FROM payment_transaction_bills ptb
          JOIN payment_transactions pt ON pt.id = ptb.transaction_id
          WHERE ptb.is_pending AND pt.status <> 'pending'`,
  },
  {
    nama: 'Tagihan tanpa kartu keluarga',
    kenapa: 'Iuran ditagihkan per KK; tanpa keluarga_id tagihan tak terlihat warga.',
    sql: 'SELECT id, bulan FROM bills WHERE keluarga_id IS NULL',
  },
  {
    nama: 'Jenis kelamin di luar L/P',
    kenapa: 'Statistik menghitung dengan = L / = P, jadi nilai lain hilang diam-diam.',
    sql: `SELECT id, nama, jenis_kelamin FROM anggota_keluarga
          WHERE jenis_kelamin IS NULL OR jenis_kelamin NOT IN ('L','P')`,
  },
  {
    nama: 'Akun warga tanpa no_kk',
    kenapa: 'Tagihan disaring lewat no_kk; tanpa itu Tagihan Saya selalu kosong.',
    sql: `SELECT email FROM users WHERE role = 'warga' AND (no_kk IS NULL OR no_kk = '')`,
  },
  {
    nama: 'Akun tanpa username',
    kenapa: 'login mencocokkan email OR username; kolom kosong menyimpang dari desain.',
    sql: 'SELECT email FROM users WHERE username IS NULL',
  },
  {
    nama: 'Lingkup warga menyimpang dari definisi yang disepakati',
    kenapa:
      'Data Warga dan kartu TOTAL WARGA sama-sama melabeli angkanya "warga" dan ' +
      'tampil di aplikasi yang sama. Selisih sekecil apa pun berarti salah satunya ' +
      'berbohong, dan tidak ada error di mana pun yang akan memberi tahu.',
    // Sisi kiri memakai SUMBER_WARGA — konstanta yang benar-benar dipakai kedua
    // layar. Sisi kanan ditulis tangan di sini sebagai definisi yang disepakati:
    // setiap anggota keluarga yang kartu keluarganya belum dihapus.
    //
    // Membandingkan konstanta itu dengan dirinya sendiri akan selalu lolos,
    // termasuk ketika konstantanya sendiri yang salah — jadi pembandingnya harus
    // ditulis terpisah. Kalau seseorang menambahkan penyaring ke SUMBER_WARGA
    // (`ak.is_aktif = true` adalah yang dulu terjadi, dan itu juga membuang
    // baris ber-NULL), baris temuan akan muncul di sini.
    //
    // BATASNYA, dan ini sudah diuji bukan diperkirakan: pemeriksaan ini buta
    // selama belum ada satu pun warga tidak aktif. Dengan penyaring itu
    // disisipkan pada database tanpa baris tidak-aktif, hasilnya tetap nol
    // temuan; pada database dengan 3 tidak-aktif + 1 NULL, ia langsung
    // melaporkan 32 lawan 36. Pemeriksaan berikutnya menutup separuh celah itu
    // dengan menandai baris NULL sebelum sempat mengurangi angka siapa pun.
    sql: `
      SELECT dipakai.n AS dipakai_aplikasi,
             seharusnya.n AS seharusnya,
             dipakai.n - seharusnya.n AS selisih
      FROM (SELECT COUNT(*)::int AS n ${SUMBER_WARGA}) dipakai,
           (
             SELECT COUNT(*)::int AS n
             FROM anggota_keluarga ak2
             JOIN keluarga k2 ON ak2.keluarga_id = k2.id
             WHERE k2.deleted_at IS NULL
           ) seharusnya
      WHERE dipakai.n <> seharusnya.n`,
  },
  {
    nama: 'Warga dengan is_aktif NULL',
    kenapa:
      'NULL bukan "aktif" maupun "tidak aktif": penyaring `= true` membuangnya diam-diam ' +
      'sementara Data Warga menampilkannya sebagai Aktif. Kolomnya DEFAULT true, jadi ' +
      'baris NULL berarti ada jalur tulis yang mengisinya secara eksplisit.',
    sql: `SELECT ak.id, ak.nama, ak.nik
          FROM anggota_keluarga ak
          JOIN keluarga k ON ak.keluarga_id = k.id
          WHERE k.deleted_at IS NULL AND ak.is_aktif IS NULL`,
  },
];

async function periksaData() {
  console.log('== Keutuhan data\n');
  let temuan = 0;

  for (const p of PERIKSA) {
    const r = await pool.query(p.sql);
    if (r.rowCount === 0) {
      console.log(`  [ OK ] ${p.nama}`);
    } else {
      temuan++;
      console.log(`  [MASALAH] ${p.nama} — ${r.rowCount} baris`);
      console.log(`           ${p.kenapa}`);
      for (const baris of r.rows.slice(0, 5)) {
        console.log(`           ${JSON.stringify(baris)}`);
      }
      if (r.rowCount > 5) console.log(`           … dan ${r.rowCount - 5} lainnya`);
    }
  }
  return temuan;
}

async function periksaEndpoint() {
  console.log('\n== Kesehatan endpoint per role\n');
  let temuan = 0;

  for (const [nama, sandi] of AKUN) {
    let token;
    try {
      const r = await fetch(`${BASE}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: `${nama}@example.com`, password: sandi }),
      });
      const j = await r.json();
      if (!j.success) {
        console.log(`  [LEWAT] ${nama}: tidak bisa masuk (${j.message})`);
        continue;
      }
      token = j.data.token;
    } catch (err) {
      console.log(`\n  Backend tidak merespons di ${BASE} — bagian ini dilewati.`);
      console.log(`  (${err.message})`);
      return temuan;
    }

    const rusak = [];
    for (const e of ENDPOINT) {
      try {
        const res = await fetch(BASE + e, { headers: { Authorization: `Bearer ${token}` } });
        // 403 berarti role ini memang tidak punya izin — itu bukan kerusakan.
        if (res.status === 404 || res.status >= 500) {
          const body = await res.json().catch(() => ({}));
          rusak.push(`${res.status} ${e} — ${(body.message || '').slice(0, 60)}`);
        }
      } catch (err) {
        rusak.push(`ERROR ${e} — ${err.message}`);
      }
    }

    if (rusak.length === 0) {
      console.log(`  [ OK ] ${nama.padEnd(11)} ${ENDPOINT.length} endpoint sehat`);
    } else {
      temuan += rusak.length;
      console.log(`  [MASALAH] ${nama}`);
      for (const x of rusak) console.log(`           ${x}`);
    }
  }
  return temuan;
}

async function ringkasIsi() {
  console.log('\n== Isi tabel\n');
  const t = await pool.query(
    `SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' ORDER BY table_name`
  );
  const berisi = [];
  for (const r of t.rows) {
    const c = await pool.query(`SELECT COUNT(*)::int AS n FROM "${r.table_name}"`);
    if (c.rows[0].n > 0) berisi.push(`${r.table_name}=${c.rows[0].n}`);
  }
  console.log('  ' + berisi.join(', '));
}

(async () => {
  console.log('\nPemeriksaan kesehatan Smart Community RT');
  console.log('(hanya membaca — tidak ada data yang diubah)\n');

  const a = await periksaData();
  const b = await periksaEndpoint();
  await ringkasIsi();

  const total = a + b;
  console.log('');
  if (total === 0) {
    console.log('Semuanya sehat.\n');
    process.exit(0);
  }
  console.log(`${total} temuan perlu diperiksa.\n`);
  process.exit(1);
})().catch((err) => {
  console.error('\nPemeriksaan gagal dijalankan:', err.message);
  process.exit(1);
});
