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
const { siapkanMasterRt } = require('../src/services/master-rt.service');

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
const {
  getBantuanSosial, getBantuanSosialStats, exportBantuanSosial,
} = require('../src/controllers/bantuan_sosial.controller');
const { getAlerts } = require('../src/controllers/emergency.controller');

// --- Bagian B: kartu ringkasan ------------------------------------------
const { getSummary: ringkasanKas, getBulanan: bulananKas } = require('../src/controllers/finance.controller');
const { getSummary: ringkasanBop, getBulanan: bulananBop } = require('../src/controllers/bop.controller');
const { getComplaintStats } = require('../src/controllers/complaint.controller');
const { getVisitorStats } = require('../src/controllers/visitor.controller');
const { getBillStats } = require('../src/controllers/bill.controller');
const {
  getInventoryStats, getBorrowingStats, getInventoryDetail,
} = require('../src/controllers/inventory.controller');
const { getDemographicsSummary } = require('../src/controllers/demographics.controller');

// --- Bagian C & D: detail dan ekspor ------------------------------------
const { getFamilyDetail, exportFamiliesExcel } = require('../src/controllers/family.controller');
const { exportWargaExcel } = require('../src/controllers/warga.controller');
const ExcelJS = require('exceljs');
const { PassThrough } = require('stream');

// --- Bagian E: tabel master per RT --------------------------------------
const { getJenisIuran } = require('../src/controllers/jenis_iuran.controller');
const { getKategoriKas } = require('../src/controllers/kategori_kas.controller');
const { getKategoriBop } = require('../src/controllers/kategori_bop.controller');

// --- Bagian F: reset per RT ---------------------------------------------
const { pratinjauReset } = require('../src/controllers/reset.controller');
const { GRUP_TOTAL, TABEL_TANPA_RT, polaLingkupRt } = require('../src/config/reset-groups');

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

/**
 * ===================================================================
 * Bagian B — kartu ringkasan
 * ===================================================================
 *
 * Bagian A memindahkan SATU baris. Untuk kartu itu tidak cukup: memindahkan
 * satu dari dua puluh transaksi memang mengubah saldo, tetapi memindahkan satu
 * pengaduan berstatus "Selesai" tidak mengubah kartu "Menunggu" sama sekali,
 * dan ujinya akan melaporkan bocor pada endpoint yang sebenarnya benar.
 *
 * Jadi di sini SELURUH baris milik RT asal dipindahkan sekaligus, dan yang
 * diperiksa adalah apakah kartunya ikut kosong. Endpoint yang dilingkupi akan
 * melaporkan nol; yang tidak, melaporkan angka yang sama persis seperti
 * sebelumnya — dan angka yang tidak bergerak ketika seluruh datanya pindah RT
 * adalah definisi kebocoran ini.
 *
 * Kenapa bukan sekadar "berbeda": lihat `adaIsi`. Tabel yang memang kosong
 * sejak awal akan "sama sebelum dan sesudah" dengan benar, jadi kasus itu
 * harus dilaporkan TIDAK TERUJI, bukan bocor.
 */
const RINGKASAN = [
  { nama: 'Kartu Kas RT', fn: ringkasanKas, tabel: 'finances' },
  { nama: 'Grafik Kas RT', fn: bulananKas, tabel: 'finances' },
  // Dua tabel sekaligus: kartu BOP menampilkan pagu (alokasi_bop) DAN
  // realisasinya (bop_finances). Memindahkan salah satu saja menyisakan angka
  // yang memang masih milik RT ini, dan ujinya akan melaporkan bocor pada
  // endpoint yang justru sudah benar.
  { nama: 'Kartu Dana BOP', fn: ringkasanBop, tabel: ['bop_finances', 'alokasi_bop'], abaikan: ['tahun', 'periode'] },
  { nama: 'Grafik Dana BOP', fn: bulananBop, tabel: 'bop_finances' },
  { nama: 'Kartu Pengaduan', fn: getComplaintStats, tabel: 'complaints' },
  { nama: 'Kartu E-Visitor', fn: getVisitorStats, tabel: 'visitors' },
  { nama: 'Kartu Barang', fn: getInventoryStats, tabel: 'inventory' },
  { nama: 'Kartu Peminjaman', fn: getBorrowingStats, tabel: 'borrowings' },
  { nama: 'Kartu Bansos', fn: getBantuanSosialStats, tabel: 'bantuan_sosial' },
  { nama: 'Kartu Iuran', fn: getBillStats, tabel: 'keluarga' },
  { nama: 'Statistik Warga', fn: getDemographicsSummary, tabel: 'keluarga' },
];

/**
 * Membuang kolom GEMA sebelum diperiksa.
 *
 * `getSummary` BOP mengembalikan `tahun: 2026` dan `periode` apa pun isi
 * datanya — keduanya berasal dari jam, bukan dari basis data. Tanpa ini
 * `adaIsi` melihat 2026 dan menyimpulkan kartunya masih berisi, lalu
 * melaporkan bocor pada endpoint yang justru sudah benar. Kolom gema harus
 * disebutkan per endpoint; menebaknya dari nama akan diam-diam mengabaikan
 * kolom yang sebenarnya bermakna.
 */
function tanpaGema(data, abaikan) {
  if (!abaikan || !abaikan.length || !data || typeof data !== 'object' || Array.isArray(data)) return data;
  const salinan = { ...data };
  for (const k of abaikan) delete salinan[k];
  return salinan;
}

/** Apakah muatan ini memuat sesuatu yang bisa hilang — angka bukan nol atau daftar berisi. */
function adaIsi(nilai) {
  if (nilai === null || nilai === undefined) return false;
  if (typeof nilai === 'number') return nilai !== 0;
  if (typeof nilai === 'string') return /^-?\d+(\.\d+)?$/.test(nilai) ? Number(nilai) !== 0 : false;
  if (Array.isArray(nilai)) return nilai.some(adaIsi);
  if (typeof nilai === 'object') return Object.values(nilai).some(adaIsi);
  return false;
}

async function ringkas(fn, user) {
  const { req, res } = mockReqRes(user);
  await fn(req, res);
  return { kode: res.getStatusCode(), data: res.getBody()?.data ?? null };
}

/**
 * ===================================================================
 * Bagian D — ekspor
 * ===================================================================
 *
 * Berkasnya benar-benar dibuat lalu DIBACA KEMBALI dengan ExcelJS, dan yang
 * dihitung adalah jumlah barisnya. Memeriksa ukuran byte akan lolos ketika
 * jumlah barisnya berubah tetapi isinya tidak — dan yang dipersoalkan justru
 * baris siapa yang ikut terunduh.
 *
 * `res` di Express adalah writable stream, jadi PassThrough sudah cukup;
 * yang perlu ditambahkan hanya tiga metode yang dipakai pengendali ekspor.
 */
async function barisEkspor(fn, user, query = {}) {
  const aliran = new PassThrough();
  const potongan = [];
  aliran.on('data', (c) => potongan.push(c));
  const selesai = new Promise((r) => aliran.on('end', r));

  const res = Object.assign(aliran, {
    setHeader() {},
    status() { return res; },
    json(d) { res.badan = d; return res; },
    headersSent: false,
  });
  const { req } = mockReqRes(user, query);
  await fn(req, res);
  await selesai;

  if (!potongan.length) return -1;
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(Buffer.concat(potongan));
  // -1 untuk baris judul kolom.
  return Math.max(0, (wb.worksheets[0]?.rowCount ?? 1) - 1);
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

    // ============================================================ BAGIAN B
    console.log(`\n  ── Kartu ringkasan (${RINGKASAN.length}) ──\n`);

    for (const p of RINGKASAN) {
      const sebelum = await ringkas(p.fn, KETUA_A);
      if (sebelum.kode !== 200 || !adaIsi(tanpaGema(sebelum.data, p.abaikan))) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — kartunya sudah nol sejak awal (status ${sebelum.kode})`);
        takTeruji += 1;
        continue;
      }

      // Seluruh baris RT asal dipindahkan sekaligus — lihat catatan di atas
      // RINGKASAN untuk alasan "seluruhnya", bukan satu baris.
      //
      // Dipilih lewat `rt_id`, bukan lewat daftar id: `id` bertipe uuid pada
      // sebagian tabel dan integer pada sebagian lain, sehingga satu bentuk
      // `ANY($2::uuid[])` pasti salah di salah satunya. Pemulihannya pun
      // menjadi kebalikan yang persis, karena RT uji tidak dipakai apa pun.
      const tabelP = Array.isArray(p.tabel) ? p.tabel : [p.tabel];
      let jumlahPindah = 0;
      for (const t of tabelP) {
        const r = await pool.query(`UPDATE ${t} SET rt_id = $1 WHERE rt_id = $2`, [rtUji, RT_A.id]);
        jumlahPindah += r.rowCount;
      }
      dipindah.push({ tabel: tabelP, dariRtUji: true, rtAsal: RT_A.id, rtUji });
      if (jumlahPindah === 0) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — ${tabelP.join('/')} kosong untuk RT ini`);
        takTeruji += 1;
        dipindah.pop();
        continue;
      }

      const sesudah = await ringkas(p.fn, KETUA_A);
      if (sesudah.kode !== 200) {
        console.log(`  X  ${p.nama.padEnd(18)} GALAT — status ${sesudah.kode}`);
        bocor += 1;
      } else if (adaIsi(tanpaGema(sesudah.data, p.abaikan))) {
        console.log(`  X  ${p.nama.padEnd(18)} BOCOR — angkanya tetap ada padahal seluruh datanya sudah pindah RT`);
        bocor += 1;
      } else {
        console.log(`  v  ${p.nama.padEnd(18)} terisolasi`);
      }

      for (const t of tabelP) {
        await pool.query(`UPDATE ${t} SET rt_id = $1 WHERE rt_id = $2`, [RT_A.id, rtUji]);
      }
      dipindah.pop();
    }

    // ============================================================ BAGIAN C
    //
    // Jalur `:id`. Idnya datang dari URL, bukan dari daftar yang sudah
    // tersaring, jadi penjagaan daftar tidak berlaku sama sekali di sini —
    // dan sebelum `pastikanDalamRt` ada, `GET /api/families/:id` memang
    // mengembalikan HTTP 200 untuk kartu keluarga milik RT lain.
    const DETAIL = [
      { nama: 'Detail KK', fn: getFamilyDetail, tabel: 'keluarga' },
      { nama: 'Detail Barang', fn: getInventoryDetail, tabel: 'inventory' },
    ];
    console.log(`\n  ── Jalur :id (${DETAIL.length}) ──\n`);

    for (const p of DETAIL) {
      const baris = await pool.query(
        `SELECT id FROM ${p.tabel} WHERE rt_id = $1 LIMIT 1`, [RT_A.id]
      );
      if (!baris.rows.length) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — tidak ada baris di RT ini`);
        takTeruji += 1;
        continue;
      }
      const id = baris.rows[0].id;

      // Kendali positif: sebelum dipindah, pengurusnya HARUS bisa membukanya.
      // Tanpa ini, endpoint yang selalu 404 karena sebab lain akan lolos.
      const { req: rq1, res: rs1 } = mockReqRes(KETUA_A);
      rq1.params = { id };
      await p.fn(rq1, rs1);
      if (rs1.getStatusCode() !== 200) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — barisnya sendiri pun tidak terbuka (status ${rs1.getStatusCode()})`);
        takTeruji += 1;
        continue;
      }

      await pool.query(`UPDATE ${p.tabel} SET rt_id = $1 WHERE id = $2`, [rtUji, id]);
      dipindah.push({ tabel: p.tabel, id, rtAsal: RT_A.id });

      const { req: rq2, res: rs2 } = mockReqRes(KETUA_A);
      rq2.params = { id };
      await p.fn(rq2, rs2);
      if (rs2.getStatusCode() === 200) {
        console.log(`  X  ${p.nama.padEnd(18)} BOCOR — membuka baris milik RT ${KODE_RT_UJI} lewat id`);
        bocor += 1;
      } else {
        console.log(`  v  ${p.nama.padEnd(18)} ditolak ${rs2.getStatusCode()}`);
      }

      await pool.query(`UPDATE ${p.tabel} SET rt_id = $1 WHERE id = $2`, [RT_A.id, id]);
      dipindah.pop();
    }

    // ============================================================ BAGIAN D
    //
    // Berkas ekspornya benar-benar dibuat lalu dibaca kembali, dan jumlah
    // barisnya dibandingkan dengan hitungan RT ini di basis data. Perbedaan
    // 36 lawan 41 yang pernah terukur pada jalur tiket unduh persis berbentuk
    // ini: daftarnya benar, berkasnya memuat seluruh RW.
    const EKSPOR = [
      {
        nama: 'Ekspor Data KK',
        fn: exportFamiliesExcel,
        sql: 'SELECT COUNT(*)::int c FROM keluarga WHERE deleted_at IS NULL',
        tabelPindah: 'keluarga',
      },
      {
        nama: 'Ekspor Data Warga',
        fn: exportWargaExcel,
        sql: `SELECT COUNT(*)::int c FROM anggota_keluarga ak
                JOIN keluarga k ON k.id = ak.keluarga_id
               WHERE k.deleted_at IS NULL`,
        kolomRt: 'k.rt_id',
        tabelPindah: 'keluarga',
      },
      {
        nama: 'Ekspor Bansos',
        fn: exportBantuanSosial,
        sql: `SELECT COUNT(*)::int c FROM bantuan_sosial bs
                JOIN users u ON u.id = bs.user_id`,
        kolomRt: 'bs.rt_id',
        tabelPindah: 'bantuan_sosial',
      },
    ];
    console.log(`\n  ── Ekspor berkas (${EKSPOR.length}) ──\n`);

    for (const p of EKSPOR) {
      const kolom = p.kolomRt || 'rt_id';
      const sambung = /WHERE/i.test(p.sql) ? 'AND' : 'WHERE';

      // Satu baris dititipkan ke RT uji lebih dulu, supaya RW-nya PASTI berisi
      // lebih dari satu RT. Tanpa ini, basis data yang datanya kebetulan
      // terkumpul di satu RT membuat "seluruh RW" dan "RT ini" bernilai sama,
      // dan ekspor yang bocor pun akan lolos dengan angka yang cocok.
      const titip = await pool.query(
        `SELECT id FROM ${p.tabelPindah} WHERE rt_id = $1 LIMIT 1`, [RT_A.id]
      );
      if (!titip.rows.length) {
        console.log(`  ?  ${p.nama.padEnd(18)} TIDAK TERUJI — ${p.tabelPindah} kosong untuk RT ini`);
        takTeruji += 1;
        continue;
      }
      const idTitip = titip.rows[0].id;
      await pool.query(`UPDATE ${p.tabelPindah} SET rt_id = $1 WHERE id = $2`, [rtUji, idTitip]);
      dipindah.push({ tabel: p.tabelPindah, id: idTitip, rtAsal: RT_A.id });

      const seRw = (await pool.query(p.sql)).rows[0].c;
      const seRt = (await pool.query(`${p.sql} ${sambung} ${kolom} = $1`, [RT_A.id])).rows[0].c;

      const terunduh = await barisEkspor(p.fn, KETUA_A);
      await pool.query(`UPDATE ${p.tabelPindah} SET rt_id = $1 WHERE id = $2`, [RT_A.id, idTitip]);
      dipindah.pop();

      if (terunduh === seRt) {
        console.log(`  v  ${p.nama.padEnd(18)} ${terunduh} baris (RT ini ${seRt}, se-RW ${seRw})`);
      } else {
        console.log(`  X  ${p.nama.padEnd(18)} BOCOR — ${terunduh} baris terunduh, seharusnya ${seRt} (se-RW ${seRw})`);
        bocor += 1;
      }
    }

    // ============================================================ BAGIAN E
    //
    // Tabel master. Sebelum v45 ketiganya satu untuk seluruh RW, dan yang
    // menahannya bukan pengendali melainkan indeks unik atas NAMA saja —
    // sehingga RT kedua tidak mungkin punya "Biaya Keamanan" sendiri.
    //
    // Yang diperiksa bukan sekadar "isinya berbeda" melainkan bahwa TIDAK ADA
    // SATU PUN id yang sama di antara keduanya. Dua daftar bisa berbeda
    // panjangnya sambil tetap berbagi baris, dan satu baris yang dipakai
    // bersama sudah cukup: menaikkan tarif air di RT 001 akan menaikkan
    // tagihan warga RT 002.
    const MASTER = [
      { nama: 'Jenis Iuran', fn: getJenisIuran, tabel: 'jenis_iuran' },
      { nama: 'Kategori Kas', fn: getKategoriKas, tabel: 'kategori_kas' },
      { nama: 'Kategori BOP', fn: getKategoriBop, tabel: 'kategori_bop' },
    ];
    console.log(`\n  ── Tabel master (${MASTER.length}) ──\n`);

    const KETUA_UJI = { ...KETUA_A, rt_id: rtUji };
    for (const m of MASTER) {
      // RT uji baru dibuat dan belum punya masternya. Diisi dari sumber yang
      // sama dengan yang dipakai layar Kelola RT, bukan dari INSERT yang
      // ditulis ulang di sini — daftar kolom yang disalin akan basi diam-diam.
      await siapkanMasterRt(pool, rtUji);

      const a = await daftar(m.fn, KETUA_A);
      const b = await daftar(m.fn, KETUA_UJI);
      if (!a.baris.length || !b.baris.length) {
        console.log(`  ?  ${m.nama.padEnd(18)} TIDAK TERUJI — salah satu daftarnya kosong`);
        takTeruji += 1;
        continue;
      }
      const idA = new Set(a.baris.map((r) => String(r.id)));
      const beririsan = b.baris.filter((r) => idA.has(String(r.id)));
      if (beririsan.length) {
        console.log(`  X  ${m.nama.padEnd(18)} BOCOR — ${beririsan.length} baris dipakai berdua`);
        bocor += 1;
      } else {
        console.log(`  v  ${m.nama.padEnd(18)} ${a.baris.length} vs ${b.baris.length} baris, tidak ada yang dipakai berdua`);
      }
    }

    // ============================================================ BAGIAN F
    //
    // Reset per RT. Yang diperiksa adalah sebuah kesamaan yang harus selalu
    // berlaku: jumlah baris yang terlihat oleh SETIAP RT, dijumlahkan, sama
    // dengan jumlah baris tanpa pelingkupan.
    //
    // Kesamaan ini menangkap ketiga cara ekspresi pelingkupan bisa salah
    // sekaligus — join yang keliru (jumlahnya kurang), penyaring yang tidak
    // mengikat (jumlahnya berlipat), dan tabel yang terlewat dari registry —
    // tanpa perlu menghapus satu baris pun. Menghapus untuk mengujinya berarti
    // uji yang tidak akan pernah dijalankan orang terhadap data sungguhan.
    const semuaRt = (await pool.query(
      'SELECT id FROM rt WHERE deleted_at IS NULL'
    )).rows.map((r) => r.id);

    const tabelReset = GRUP_TOTAL.tabel.filter((t) => !TABEL_TANPA_RT.includes(t.tabel));
    console.log(`\n  ── Pelingkupan reset (${tabelReset.length} tabel) ──\n`);

    let resetBocor = 0;
    for (const entri of tabelReset) {
      const hitung = async (rt) => {
        const params = [];
        const bagian = [];
        if (entri.where) bagian.push(entri.where);
        if (rt) {
          const pola = polaLingkupRt(entri.tabel, params.length + 1);
          params.push(rt);
          bagian.push(pola);
        }
        const where = bagian.length ? ` WHERE ${bagian.join(' AND ')}` : '';
        const r = await pool.query(`SELECT COUNT(*)::int n FROM ${entri.tabel}${where}`, params);
        return r.rows[0].n;
      };

      const seluruh = await hitung(null);
      let jumlah = 0;
      for (const id of semuaRt) jumlah += await hitung(id);

      if (jumlah !== seluruh) {
        console.log(`  X  ${entri.tabel.padEnd(26)} BOCOR — per RT berjumlah ${jumlah}, tanpa lingkup ${seluruh}`);
        resetBocor += 1;
      }
    }
    if (resetBocor === 0) {
      console.log(`  v  ${String(tabelReset.length).padStart(2)} tabel: jumlah per RT = jumlah tanpa lingkup`);
    }
    bocor += resetBocor;

    // Kelompok yang tidak punya dimensi RT harus DITOLAK, bukan dijalankan
    // menyeluruh dan bukan pula dilaporkan "berhasil, 0 baris".
    const rSensor = mockReqRes(
      { ...KETUA_A, role: 'admin' },
      { rt: rtUji }
    );
    rSensor.req.body = { grup: 'sensor' };
    await pratinjauReset(rSensor.req, rSensor.res);
    if (rSensor.res.getStatusCode() === 400) {
      console.log('  v  kelompok Sensor    ditolak saat sebuah RT dipilih');
    } else {
      console.log(`  X  kelompok Sensor    TIDAK ditolak (status ${rSensor.res.getStatusCode()})`);
      bocor += 1;
    }

    // Frasa konfirmasi harus menyebut RT-nya. Ia satu-satunya tempat di
    // seluruh alur ini yang dijamin dibaca sebelum data hilang.
    const rFrasa = mockReqRes({ ...KETUA_A, role: 'admin' }, { rt: rtUji });
    rFrasa.req.body = { grup: 'total' };
    await pratinjauReset(rFrasa.req, rFrasa.res);
    const frasa = rFrasa.res.getBody()?.data?.konfirmasi ?? '';
    if (frasa.includes(KODE_RT_UJI)) {
      console.log(`  v  frasa konfirmasi   menyebut RT: "${frasa}"`);
    } else {
      console.log(`  X  frasa konfirmasi   TIDAK menyebut RT: "${frasa}"`);
      bocor += 1;
    }

    const total = PERIKSA.length + RINGKASAN.length + DETAIL.length + EKSPOR.length
      + MASTER.length + tabelReset.length + 2;
    console.log('\n----------------------------------------------------------------');
    console.log(`  terisolasi   : ${total - bocor - takTeruji} dari ${total}`);
    console.log(`  BOCOR        : ${bocor}`);
    console.log(`  tidak teruji : ${takTeruji}`);
    console.log('----------------------------------------------------------------\n');

    assert.strictEqual(bocor, 0, `${bocor} endpoint masih membocorkan data RT lain.`);
    assert.strictEqual(takTeruji, 0,
      `${takTeruji} endpoint tidak dapat diuji — isi datanya kosong, jadi isolasinya belum terbukti.`);
    console.log('✅ Daftar, kartu, jalur :id, ekspor, master, dan reset semuanya terisolasi per RT.\n');
  } finally {
    // Pemulihan menangani dua bentuk: satu baris (Bagian A dan C) dan
    // seluruh baris sekaligus (Bagian B). Blok ini berjalan juga ketika ada
    // assert yang gagal di tengah, jadi basis data tidak pernah ditinggalkan
    // dengan data yang masih berada di RT uji.
    for (const d of dipindah) {
      if (d.dariRtUji) {
        for (const t of d.tabel) {
          await pool.query(`UPDATE ${t} SET rt_id = $1 WHERE rt_id = $2`, [d.rtAsal, d.rtUji]);
        }
      } else {
        await pool.query(`UPDATE ${d.tabel} SET rt_id = $1 WHERE id = $2`, [d.rtAsal, d.id]);
      }
    }
    if (rtUji) {
      // Master RT uji dibuang lebih dulu: FK-nya ke `rt` ber-ON DELETE
      // RESTRICT, jadi menghapus RT-nya lebih dulu akan gagal dan
      // meninggalkan RT uji hidup di basis data sungguhan.
      for (const t of ['jenis_iuran', 'kategori_kas', 'kategori_bop']) {
        await pool.query(`DELETE FROM ${t} WHERE rt_id = $1`, [rtUji]);
      }
      await pool.query('DELETE FROM rt WHERE id = $1 AND kode = $2', [rtUji, KODE_RT_UJI]);
    }
    await pool.end();
  }
})().catch((e) => {
  console.error('\n❌', e.message, '\n');
  process.exit(1);
});
