/**
 * Uji isolasi antar-RT.
 *
 * ===================================================================
 * Kenapa berkas ini ada
 * ===================================================================
 *
 * Sejak migrasi v43 sistem melayani beberapa RT dalam satu RW. Ada 527 kueri
 * SQL di 28 pengendali, dan setiap satu di antaranya yang lupa menyaring
 * `rt_id` membocorkan data warga RT lain.
 *
 * Kebocoran seperti itu **tidak punya gejala**. Tidak ada galat, tidak ada
 * baris log, dan daftarnya terlihat wajar — hanya isinya milik orang lain.
 * Membacanya satu per satu bukan jaring pengaman; berkas inilah jaringnya.
 *
 * ===================================================================
 * Cara kerjanya: memindahkan baris, bukan membuat baris
 * ===================================================================
 *
 * Menyusun INSERT untuk lima belas tabel berarti menuliskan daftar kolom yang
 * akan basi begitu skema berubah. Sebagai gantinya, uji ini MEMINDAHKAN satu
 * baris yang sudah ada ke RT kedua, memeriksa, lalu mengembalikannya. Barisnya
 * dijamin sah dan dijamin terjangkau endpoint-nya.
 *
 * ===================================================================
 * Barisnya diambil DARI TANGGAPAN endpoint, bukan dari tabel
 * ===================================================================
 *
 * Versi pertama uji ini memilih baris dengan `ORDER BY id LIMIT 1` langsung
 * dari tabel, lalu mencari id itu di dalam tanggapan. Tiga endpoint dilaporkan
 * "tidak teruji" karenanya — Agenda mengurutkan menurut tanggal, jadi baris
 * ber-id terkecil memang tidak pernah muncul di halaman pertama.
 *
 * Sekarang urutannya dibalik: endpoint dipanggil lebih dulu, baris PERTAMA
 * pada tanggapannyalah yang dipindahkan. Dengan begitu kendali positifnya
 * dijamin — barisnya pasti terlihat sebelum dipindahkan, apa pun urutan,
 * penyaringan, dan paging yang dipakai endpoint itu.
 *
 * ===================================================================
 * Kenapa ada pemeriksaan "sebelum"
 * ===================================================================
 *
 * Tanpa itu seluruh uji tidak membuktikan apa pun: endpoint yang mengembalikan
 * daftar KOSONG akan lolos setiap pemeriksaan kebocoran, karena memang tidak
 * ada apa-apa untuk bocor. Endpoint yang daftarnya kosong sejak awal
 * dilaporkan TIDAK TERUJI, bukan LULUS.
 *
 * Aman dijalankan berulang: seluruh perubahan dikembalikan pada blok finally,
 * termasuk bila ada assert yang gagal di tengah.
 *
 *   node tests/test-isolasi-rt.js
 */
require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-isolasi-rt');

const assert = require('assert');
const { pool } = require('../src/config/database');

const { getFamilies } = require('../src/controllers/family.controller');
const { getWarga } = require('../src/controllers/warga.controller');
const { getBills } = require('../src/controllers/bill.controller');
const { getTransactions: getKas } = require('../src/controllers/finance.controller');
const { getTransactions: getBop } = require('../src/controllers/bop.controller');
const { getInventory, getBorrowings } = require('../src/controllers/inventory.controller');
const { getAgenda } = require('../src/controllers/agenda.controller');
const { getAnnouncements } = require('../src/controllers/announcement.controller');
const { getPolling } = require('../src/controllers/polling.controller');
const { getVisitors } = require('../src/controllers/visitor.controller');
const { getComplaints } = require('../src/controllers/complaint.controller');
const { getLetters } = require('../src/controllers/letter.controller');
const { getBantuanSosial } = require('../src/controllers/bantuan_sosial.controller');
const { getAlerts } = require('../src/controllers/emergency.controller');

const KODE_RT_UJI = '902';

/**
 * Endpoint daftar yang diperiksa.
 *
 * `tabel` adalah yang benar-benar dipindahkan, dan `kunci` menunjuk kolom pada
 * baris tanggapan yang berisi id baris itu.
 *
 * Data Warga dan Iuran Warga menunjuk `keluarga`, bukan tabelnya sendiri:
 * keduanya tidak punya `rt_id` dan memang tidak boleh punya. Yang bertempat
 * tinggal di sebuah RT adalah kartu keluarga; anggota dan tagihan mengikutinya.
 */
const PERIKSA = [
  { nama: 'Data KK', fn: getFamilies, tabel: 'keluarga', kunci: (r) => r.id },
  { nama: 'Data Warga', fn: getWarga, tabel: 'keluarga', kunci: (r) => r.keluarga_id },
  { nama: 'Iuran Warga', fn: getBills, tabel: 'keluarga', kunci: (r) => r.keluarga_id },
  { nama: 'Kas RT', fn: getKas, tabel: 'finances', kunci: (r) => r.id },
  { nama: 'Dana BOP', fn: getBop, tabel: 'bop_finances', kunci: (r) => r.id },
  { nama: 'Data Barang', fn: getInventory, tabel: 'inventory', kunci: (r) => r.id },
  { nama: 'Peminjaman', fn: getBorrowings, tabel: 'borrowings', kunci: (r) => r.id },
  { nama: 'Agenda', fn: getAgenda, tabel: 'agenda', kunci: (r) => r.id },
  { nama: 'Pengumuman', fn: getAnnouncements, tabel: 'announcements', kunci: (r) => r.id },
  { nama: 'Polling', fn: getPolling, tabel: 'polling', kunci: (r) => r.id },
  { nama: 'E-Visitor', fn: getVisitors, tabel: 'visitors', kunci: (r) => r.id },
  { nama: 'Pengaduan', fn: getComplaints, tabel: 'complaints', kunci: (r) => r.id },
  { nama: 'Surat Menyurat', fn: getLetters, tabel: 'letters', kunci: (r) => r.id },
  { nama: 'Bantuan Sosial', fn: getBantuanSosial, tabel: 'bantuan_sosial', kunci: (r) => r.id },
  { nama: 'Status Darurat', fn: getAlerts, tabel: 'emergency_alerts', kunci: (r) => r.id },
];

function mockReqRes(user, query = {}) {
  let kode = 200;
  let isi = null;
  return {
    req: { body: {}, params: {}, query, user, headers: {}, ip: '127.0.0.1', socket: { remoteAddress: '127.0.0.1' } },
    res: {
      status(c) { kode = c; return this; },
      json(d) { isi = d; return this; },
      getStatusCode() { return kode; },
      getBody() { return isi; },
    },
  };
}

/** Menarik array baris dari berbagai bentuk amplop tanggapan. */
function barisDari(body) {
  const d = body?.data;
  if (Array.isArray(d)) return d;
  if (Array.isArray(d?.data)) return d.data;
  if (Array.isArray(body)) return body;
  return [];
}

async function daftar(fn, user) {
  const { req, res } = mockReqRes(user);
  await fn(req, res);
  return { kode: res.getStatusCode(), baris: barisDari(res.getBody()) };
}

(async () => {
  console.log('\n================================================================');
  console.log('  UJI ISOLASI ANTAR-RT');
  console.log('================================================================\n');

  let rtUji = null;
  const dipindah = [];
  let bocor = 0;
  let takTeruji = 0;

  try {
    const rtA = await pool.query(
      'SELECT id, kode, rw_kode FROM rt WHERE deleted_at IS NULL ORDER BY kode LIMIT 1'
    );
    assert.ok(rtA.rows.length, 'Belum ada satu pun RT — jalankan migrasi v43 lebih dulu.');
    const RT_A = rtA.rows[0];

    const buat = await pool.query(
      `INSERT INTO rt (kode, nama, rw_kode) VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING RETURNING id`,
      [KODE_RT_UJI, 'RT Uji Isolasi', RT_A.rw_kode]
    );
    rtUji = buat.rows[0]?.id ?? (await pool.query(
      'SELECT id FROM rt WHERE kode = $1 AND rw_kode = $2', [KODE_RT_UJI, RT_A.rw_kode]
    )).rows[0].id;

    const pengurus = await pool.query(
      `SELECT id, role FROM users
        WHERE role = 'ketua_rt' AND deleted_at IS NULL AND rt_id = $1 LIMIT 1`,
      [RT_A.id]
    );
    assert.ok(pengurus.rows.length, `Tidak ada akun ketua_rt di RT ${RT_A.kode}.`);
    const KETUA_A = { ...pengurus.rows[0], rt_id: RT_A.id, nama: 'Ketua Uji' };

    console.log(`  RT asal   : ${RT_A.kode} (RW ${RT_A.rw_kode})`);
    console.log(`  RT uji    : ${KODE_RT_UJI}`);
    console.log(`  Diperiksa : ${PERIKSA.length} endpoint daftar\n`);

    for (const p of PERIKSA) {
      // --- sebelum: apa yang terlihat sekarang
      const awal = await daftar(p.fn, KETUA_A);
      if (awal.kode !== 200 || awal.baris.length === 0) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — daftar kosong (status ${awal.kode})`);
        takTeruji += 1;
        continue;
      }
      const tanda = awal.baris[0].id;
      const pindahId = p.kunci(awal.baris[0]);
      if (pindahId === undefined || pindahId === null) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — baris tanggapan tidak memuat kunci RT-nya`);
        takTeruji += 1;
        continue;
      }

      // --- pindahkan ke RT lain
      await pool.query(`UPDATE ${p.tabel} SET rt_id = $1 WHERE id = $2`, [rtUji, pindahId]);
      dipindah.push({ tabel: p.tabel, id: pindahId, rtAsal: RT_A.id });

      // --- sesudah: masih terlihat atau tidak
      const akhir = await daftar(p.fn, KETUA_A);
      const masihAda = akhir.baris.some((r) => String(r.id) === String(tanda));
      if (masihAda) {
        console.log(`  X  ${p.nama.padEnd(18)} BOCOR — masih menampilkan baris milik RT ${KODE_RT_UJI}`);
        bocor += 1;
      } else {
        console.log(`  v  ${p.nama.padEnd(18)} terisolasi`);
      }

      // Dikembalikan segera supaya endpoint berikutnya melihat data utuh.
      await pool.query(`UPDATE ${p.tabel} SET rt_id = $1 WHERE id = $2`, [RT_A.id, pindahId]);
      dipindah.pop();
    }

    console.log('\n----------------------------------------------------------------');
    console.log(`  terisolasi   : ${PERIKSA.length - bocor - takTeruji}`);
    console.log(`  BOCOR        : ${bocor}`);
    console.log(`  tidak teruji : ${takTeruji}`);
    console.log('----------------------------------------------------------------\n');

    assert.strictEqual(bocor, 0, `${bocor} endpoint masih membocorkan data RT lain.`);
    assert.strictEqual(takTeruji, 0,
      `${takTeruji} endpoint tidak dapat diuji — isi datanya kosong, jadi isolasinya belum terbukti.`);
    console.log('✅ Seluruh endpoint daftar terisolasi per RT.\n');
  } finally {
    for (const d of dipindah) {
      await pool.query(`UPDATE ${d.tabel} SET rt_id = $1 WHERE id = $2`, [d.rtAsal, d.id]);
    }
    if (rtUji) {
      await pool.query('DELETE FROM rt WHERE id = $1 AND kode = $2', [rtUji, KODE_RT_UJI]);
    }
    await pool.end();
  }
})().catch((e) => {
  console.error('\n❌', e.message, '\n');
  process.exit(1);
});
