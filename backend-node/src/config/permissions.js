/**
 * Daftar menu dan matriks izin bawaan.
 *
 * Berkas ini adalah SATU-SATUNYA sumber kebenaran untuk struktur menu dan
 * pembagian akses awal. Dipakai oleh migrasi v11 untuk mengisi tabel, dan oleh
 * endpoint reset untuk mengembalikan matriks ke keadaan semula.
 *
 * Setelah di-seed, admin bisa mengubah izinnya lewat layar Menu & Akses;
 * berkas ini hanya menentukan titik awalnya.
 */

// Aksi ditulis ringkas agar matriksnya terbaca sebagai tabel.
const N = { view: false, create: false, update: false, delete: false }; // tidak ada akses
const V = { view: true, create: false, update: false, delete: false };  // lihat saja
const VC = { view: true, create: true, update: false, delete: false };  // lihat + ajukan
const VU = { view: true, create: false, update: true, delete: false };  // lihat + setujui
const F = { view: true, create: true, update: true, delete: true };     // penuh

/**
 * Menu mengikuti sidebar_menu.dart. `menu_index` adalah index yang dipakai
 * main_dashboard untuk memilih layar; null berarti modulnya punya endpoint
 * tetapi belum punya entri sidebar.
 *
 * `is_sistem: true` = hanya admin, tidak bisa diberikan ke role lain bahkan
 * lewat layar. Inilah yang mencegah admin kehilangan kendali.
 */
const MENU_ITEMS = [
  { kode: 'dashboard', nama: 'Dashboard', grup: 'Umum', menu_index: 0 },

  { kode: 'kependudukan.warga', nama: 'Data Warga', grup: 'Kependudukan', menu_index: 12 },
  { kode: 'kependudukan.bansos', nama: 'Bantuan Sosial', grup: 'Kependudukan', menu_index: 13 },
  { kode: 'kependudukan.statistik', nama: 'Statistik & Grafik', grup: 'Kependudukan', menu_index: 14 },

  { kode: 'keuangan.iuran', nama: 'Iuran Warga', grup: 'Keuangan', menu_index: 21 },
  { kode: 'keuangan.kas', nama: 'Kas RT', grup: 'Keuangan', menu_index: 22 },
  { kode: 'keuangan.bop', nama: 'Dana BOP', grup: 'Keuangan', menu_index: 23 },

  { kode: 'inventaris.barang', nama: 'Data Barang', grup: 'Inventaris', menu_index: 31 },
  { kode: 'inventaris.peminjaman', nama: 'Peminjaman', grup: 'Inventaris', menu_index: 32 },

  { kode: 'layanan.visitor', nama: 'E-Visitor', grup: 'Layanan Warga', menu_index: 43 },
  { kode: 'layanan.surat', nama: 'Surat Menyurat', grup: 'Layanan Warga', menu_index: 44 },

  { kode: 'kegiatan.agenda', nama: 'Agenda & Kegiatan', grup: 'Kegiatan & Info', menu_index: 50 },

  { kode: 'aspirasi.darurat', nama: 'Status Darurat', grup: 'Aspirasi & Partisipasi', menu_index: 60 },
  { kode: 'aspirasi.pengaduan', nama: 'Pengaduan', grup: 'Aspirasi & Partisipasi', menu_index: 61 },
  { kode: 'aspirasi.polling', nama: 'Polling Warga', grup: 'Aspirasi & Partisipasi', menu_index: 62 },

  { kode: 'pengaturan.log', nama: 'Log Aktivitas', grup: 'Pengaturan', menu_index: 84 },
  { kode: 'pengaturan.akses', nama: 'Menu & Akses', grup: 'Pengaturan', menu_index: 85, is_sistem: true },
  { kode: 'pengaturan.reset', nama: 'Reset Sistem', grup: 'Pengaturan', menu_index: 86, is_sistem: true },
];

/**
 * Matriks izin bawaan.
 *
 * Baris admin tetap disimpan agar terlihat di layar, tetapi middleware tidak
 * pernah membacanya — admin selalu lolos lebih dulu.
 */
const DEFAULT_PERMISSIONS = {
  admin: Object.fromEntries(MENU_ITEMS.map((m) => [m.kode, F])),

  ketua_rt: {
    'dashboard': V,
    'kependudukan.warga': F,
    'kependudukan.bansos': F,
    'kependudukan.statistik': V,
    'keuangan.iuran': F,
    'keuangan.kas': F,
    'keuangan.bop': F,
    'inventaris.barang': F,
    'inventaris.peminjaman': F,
    'layanan.visitor': F,
    // Ketua menandatangani surat: boleh menyetujui, tidak menyusun.
    'layanan.surat': VU,
    'kegiatan.agenda': F,
    'aspirasi.darurat': F,
    'aspirasi.pengaduan': F,
    'aspirasi.polling': F,
    'pengaturan.log': V,
    'pengaturan.akses': N,
    'pengaturan.reset': N,
  },

  sekretaris: {
    'dashboard': V,
    'kependudukan.warga': F,
    'kependudukan.bansos': F,
    'kependudukan.statistik': V,
    // Boleh membaca angka untuk laporan, tidak boleh mencatat transaksi.
    'keuangan.iuran': V,
    'keuangan.kas': V,
    'keuangan.bop': V,
    'inventaris.barang': F,
    'inventaris.peminjaman': F,
    'layanan.visitor': F,
    'layanan.surat': F,
    'kegiatan.agenda': F,
    'aspirasi.darurat': F,
    'aspirasi.pengaduan': F,
    'aspirasi.polling': F,
    'pengaturan.log': N,
    'pengaturan.akses': N,
    'pengaturan.reset': N,
  },

  bendahara: {
    'dashboard': V,
    // Iuran ditagihkan per kartu keluarga, jadi bendahara perlu melihat
    // data warga untuk mencocokkan pembayaran — tetapi tidak mengubahnya.
    'kependudukan.warga': V,
    'kependudukan.bansos': V,
    'kependudukan.statistik': V,
    'keuangan.iuran': F,
    'keuangan.kas': F,
    'keuangan.bop': F,
    'inventaris.barang': V,
    'inventaris.peminjaman': V,
    'layanan.visitor': N,
    'layanan.surat': N,
    'kegiatan.agenda': V,
    'aspirasi.darurat': V,
    'aspirasi.pengaduan': V,
    'aspirasi.polling': V,
    'pengaturan.log': N,
    'pengaturan.akses': N,
    'pengaturan.reset': N,
  },

  warga: {
    'dashboard': V,
    'kependudukan.warga': N,
    'kependudukan.bansos': N,
    'kependudukan.statistik': N,
    // Controller sudah menyaring per user; izin ini cukup di tingkat modul.
    'keuangan.iuran': V,
    'keuangan.kas': V,
    'keuangan.bop': N,
    // Warga meminjam barang, bukan mengelola daftar inventarisnya.
    'inventaris.barang': N,
    'inventaris.peminjaman': VC,
    'layanan.visitor': N,
    'layanan.surat': VC,
    'kegiatan.agenda': V,
    'aspirasi.darurat': VC,
    'aspirasi.pengaduan': VC,
    // Tetap `view`. Ikut memilih dijaga 'view' di polling.routes.js, karena
    // 'create' pada modul ini berarti MEMBUAT polling — bukan menyuarakannya.
    'aspirasi.polling': V,
    'pengaturan.log': N,
    'pengaturan.akses': N,
    'pengaturan.reset': N,
  },
};

/** Role yang muncul sebagai kolom di layar Menu & Akses. */
const ROLES = ['admin', 'ketua_rt', 'sekretaris', 'bendahara', 'warga'];

const ROLE_LABEL = {
  admin: 'Administrator',
  ketua_rt: 'Ketua RT',
  sekretaris: 'Sekretaris',
  bendahara: 'Bendahara',
  warga: 'Warga',
};

module.exports = { MENU_ITEMS, DEFAULT_PERMISSIONS, ROLES, ROLE_LABEL };
