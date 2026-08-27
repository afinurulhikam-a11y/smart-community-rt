/**
 * Daftar unduhan yang boleh dijangkau lewat tiket sekali pakai.
 *
 * ===================================================================
 * Kenapa daftar tertutup, bukan "jenis" bebas dari klien
 * ===================================================================
 *
 * Klien hanya pernah mengirim `jenis` — sebuah kunci dari tabel ini — dan tidak
 * pernah mengirim nama rute, nama fungsi, atau apa pun yang bisa mengarahkan
 * server ke tempat lain. Pola yang sama sudah dipakai Reset Sistem: controller
 * di sana tidak pernah menerima nama tabel dari klien, hanya kode grup.
 *
 * Sebuah `jenis` yang tidak ada di sini ditolak sebelum apa pun terjadi.
 *
 * ===================================================================
 * Izinnya HARUS sama persis dengan rute aslinya
 * ===================================================================
 *
 * Kolom `izin` di bawah menyalin penjaga yang sudah terpasang di berkas rute
 * masing-masing. Kalau keduanya berbeda, tiket menjadi jalan pintas RBAC —
 * persis hal yang paling berbahaya dari mekanisme ini.
 *
 * `reset.cadangan` sengaja memakai `roleGuard('admin')`, bukan izin modul,
 * karena begitulah `reset.routes.js` menjaganya: wewenang menghapus data tidak
 * boleh bergantung pada tabel izin yang bisa ikut terhapus.
 *
 * Penjaganya dijalankan DUA KALI — saat tiket dibuat dan saat ditukar. Menu &
 * Akses bisa mencabut izin kapan saja, dan jendela 60 detik cukup untuk itu
 * terjadi. Tiket tidak boleh menjadi izin beku.
 *
 * ===================================================================
 * `paramJalur`
 * ===================================================================
 *
 * Nama parameter yang di rute aslinya berada di JALUR (`/bills/:id/receipt`),
 * bukan di query string. Adaptor memisahkan keduanya berdasarkan daftar ini:
 * yang tersebut di sini masuk ke `req.params`, sisanya ke `req.query`. Tanpa
 * pemisahan itu `downloadReceipt` tidak akan pernah menemukan tagihannya.
 */

const JENIS_UNDUH = {
  // Rekap satu baris per RT untuk laporan pertanggungjawaban RW.
  //
  // Dijaga PERAN, bukan izin modul — sama seperti `reset.cadangan`. Berkasnya
  // memuat rekap keuangan SELURUH RT, jadi yang menentukan boleh atau tidak
  // adalah kewenangan lintas RT itu sendiri, bukan izin pada satu modul yang
  // kebetulan dimiliki setiap pengurus RT.
  'rt.rekap': {
    label: 'Rekap Perbandingan RT se-RW',
    peran: ['admin', 'ketua_rw'],
    modul: '../controllers/rt.controller',
    fungsi: 'exportPerbandinganRt',
    paramJalur: [],
  },
  'iuran.export': {
    label: 'Ekspor Iuran',
    izin: { kode: 'keuangan.iuran', aksi: 'view' },
    modul: '../controllers/bill.controller',
    fungsi: 'exportBills',
    paramJalur: [],
  },
  'iuran.kuitansi': {
    label: 'Kwitansi Pembayaran',
    izin: { kode: 'keuangan.iuran', aksi: 'view' },
    modul: '../controllers/bill.controller',
    fungsi: 'downloadReceipt',
    // Kepemilikan diperiksa di dalam controller lewat `bolehMengaksesTagihan`.
    // Ia membaca `req.user.role` dan `req.user.id`, keduanya disediakan adaptor
    // dari baris `users` yang dibaca ulang saat penukaran — jadi warga tetap
    // hanya bisa mengunduh kwitansi keluarganya sendiri, sama seperti jalur
    // bearer.
    paramJalur: ['id'],
  },
  'kas.export': {
    label: 'Ekspor Kas RT',
    izin: { kode: 'keuangan.kas', aksi: 'view' },
    modul: '../controllers/finance.controller',
    fungsi: 'exportFinances',
    paramJalur: [],
  },
  'bop.export': {
    label: 'Ekspor Dana BOP',
    izin: { kode: 'keuangan.bop', aksi: 'view' },
    modul: '../controllers/bop.controller',
    fungsi: 'exportBop',
    paramJalur: [],
  },
  'warga.excel': {
    label: 'Ekspor Data Warga (Excel)',
    izin: { kode: 'kependudukan.warga', aksi: 'view' },
    modul: '../controllers/warga.controller',
    fungsi: 'exportWargaExcel',
    paramJalur: [],
  },
  'warga.pdf': {
    label: 'Ekspor Data Warga (PDF)',
    izin: { kode: 'kependudukan.warga', aksi: 'view' },
    modul: '../controllers/warga.controller',
    fungsi: 'exportWargaPdf',
    paramJalur: [],
  },
  'kk.excel': {
    label: 'Ekspor Data KK (Excel)',
    izin: { kode: 'kependudukan.kk', aksi: 'view' },
    modul: '../controllers/family.controller',
    fungsi: 'exportFamiliesExcel',
    paramJalur: [],
  },
  'kk.pdf': {
    label: 'Ekspor Data KK (PDF)',
    izin: { kode: 'kependudukan.kk', aksi: 'view' },
    modul: '../controllers/family.controller',
    fungsi: 'exportFamiliesPdf',
    paramJalur: [],
  },
  'bansos.export': {
    label: 'Ekspor Bantuan Sosial',
    izin: { kode: 'kependudukan.bansos', aksi: 'view' },
    modul: '../controllers/bantuan_sosial.controller',
    fungsi: 'exportBantuanSosial',
    paramJalur: [],
  },
  'inventaris.export': {
    label: 'Ekspor Inventaris',
    izin: { kode: 'inventaris.barang', aksi: 'view' },
    modul: '../controllers/inventory.controller',
    fungsi: 'exportInventory',
    paramJalur: [],
  },
  'peminjaman.export': {
    label: 'Ekspor Peminjaman',
    izin: { kode: 'inventaris.peminjaman', aksi: 'view' },
    modul: '../controllers/inventory.controller',
    fungsi: 'exportBorrowings',
    paramJalur: [],
  },
  'reset.cadangan': {
    label: 'Cadangan Data',
    // Bukan izin modul — lihat catatan di kepala berkas.
    peran: ['admin'],
    modul: '../controllers/reset.controller',
    fungsi: 'cadanganReset',
    paramJalur: [],
  },
};

/**
 * Pemeriksaan saat berkas dimuat, mengikuti pola `reset-groups.js`: sebuah
 * salah ketik pada nama fungsi harus menghentikan server saat startup, bukan
 * meledak di tangan pengguna yang sedang menekan tombol Export.
 */
for (const [jenis, def] of Object.entries(JENIS_UNDUH)) {
  const modul = require(def.modul);
  if (typeof modul[def.fungsi] !== 'function') {
    throw new Error(
      `jenis-unduh: '${jenis}' menunjuk ${def.modul}.${def.fungsi} yang bukan fungsi.`
    );
  }
  if (!def.izin && !def.peran) {
    throw new Error(`jenis-unduh: '${jenis}' tidak punya penjaga sama sekali.`);
  }
}

/** Handler asli untuk sebuah jenis. Null bila jenisnya tidak dikenal. */
function ambilHandler(jenis) {
  const def = JENIS_UNDUH[jenis];
  if (!def) return null;
  return require(def.modul)[def.fungsi];
}

module.exports = { JENIS_UNDUH, ambilHandler };
