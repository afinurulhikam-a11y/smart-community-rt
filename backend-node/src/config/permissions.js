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
const VCD = { view: true, create: true, update: false, delete: true }; // lihat + ajukan + batal
const VU = { view: true, create: false, update: true, delete: false };  // lihat + setujui
const VCU = { view: true, create: true, update: true, delete: false }; // lihat + buat + checkout
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
  // ===================================================================
  // URUTAN ARRAY INI ADALAH URUTAN LAYAR MENU & AKSES
  // ===================================================================
  //
  // `auto-setup.js` menyimpan index array sebagai kolom `urutan`, dan
  // `getMenuAkses` mengurutkan dengan `ORDER BY urutan`. Jadi memindahkan baris
  // di sini benar-benar memindahkan barisnya di layar — bukan sekadar merapikan
  // berkas. Urutannya mengikuti sidebar supaya administrator membaca daftar
  // yang sama dengan yang dilihat pemakainya.
  //
  // ===================================================================
  // Dua entri sidebar SENGAJA tidak ada di daftar ini
  // ===================================================================
  //
  // Daftar ini adalah daftar hal yang IZINNYA BISA DIATUR. Entri sidebar yang
  // tidak bisa diatur tidak boleh muncul di Menu & Akses, karena saklar yang
  // tidak mengubah apa pun lebih berbahaya daripada tidak ada saklar — ia
  // membuat administrator yakin sudah menutup sesuatu.
  //
  //   index 0  Dashboard    — beranda setiap peran, tampil tanpa syarat.
  //                           Dulu punya baris `dashboard` di sini, tetapi
  //                           TIDAK ADA satu pun rute yang menjaganya dan
  //                           tidak ada kode klien yang membacanya, sehingga
  //                           20 saklar (4 aksi x 5 peran) tidak berpengaruh
  //                           sama sekali. Dihapus lewat migrasi v31.
  //
  //   index 81 Profil Saya  — data diri pemakai sendiri, bukan modul RT.
  //                           Mencabutnya berarti seseorang tidak bisa
  //                           mengganti kata sandinya sendiri.

  // --- Kependudukan --------------------------------------------------
  { kode: 'kependudukan.warga', nama: 'Data Warga', grup: 'Kependudukan', menu_index: 12 },
  // Data KK kini izin tersendiri, menjaga SELURUH `/api/families`.
  //
  // Sebelumnya ia menumpang `kependudukan.warga`. Dipisah karena keduanya
  // memang dua kewenangan yang berbeda: mengubah anggota keluarga tidak sama
  // dengan mengubah susunan kartu keluarganya. Konsekuensinya harus disadari —
  // Iuran Warga membaca `/api/families` untuk menagih per kartu keluarga, jadi
  // peran yang mengelola iuran WAJIB memegang minimal `view` di sini.
  { kode: 'kependudukan.kk', nama: 'Data KK', grup: 'Kependudukan', menu_index: 15 },
  { kode: 'kependudukan.bansos', nama: 'Bantuan Sosial', grup: 'Kependudukan', menu_index: 13 },
  { kode: 'kependudukan.statistik', nama: 'Statistik & Grafik', grup: 'Kependudukan', menu_index: 14 },

  // --- Keuangan ------------------------------------------------------
  { kode: 'keuangan.iuran', nama: 'Iuran Warga', grup: 'Keuangan', menu_index: 21 },
  { kode: 'keuangan.kas', nama: 'Kas RT', grup: 'Keuangan', menu_index: 22 },
  { kode: 'keuangan.bop', nama: 'Dana BOP', grup: 'Keuangan', menu_index: 23 },

  // --- Layanan Warga -------------------------------------------------
  { kode: 'layanan.visitor', nama: 'E-Visitor', grup: 'Layanan Warga', menu_index: 43 },
  { kode: 'layanan.surat', nama: 'Surat Menyurat', grup: 'Layanan Warga', menu_index: 44 },

  // --- Kegiatan & Info -----------------------------------------------
  // Pengumuman TIDAK lagi izin tersendiri. Ia sudah menjadi tab di dalam
  // Agenda & Kegiatan, dan `announcement.routes.js` kini dijaga
  // `kegiatan.agenda`. Penggabungannya tidak mengubah kewenangan siapa pun:
  // pada matriks bawaan, setiap peran memegang nilai yang SAMA persis untuk
  // agenda dan pengumuman, jadi tidak ada akses yang bertambah atau berkurang.
  { kode: 'kegiatan.agenda', nama: 'Agenda & Kegiatan', grup: 'Kegiatan & Info', menu_index: 50 },

  // --- Aspirasi & Partisipasi ----------------------------------------
  { kode: 'aspirasi.pengaduan', nama: 'Pengaduan', grup: 'Aspirasi & Partisipasi', menu_index: 61 },
  { kode: 'aspirasi.polling', nama: 'Polling Warga', grup: 'Aspirasi & Partisipasi', menu_index: 62 },
  { kode: 'aspirasi.darurat', nama: 'Status Darurat', grup: 'Aspirasi & Partisipasi', menu_index: 60 },

  // --- Inventaris ----------------------------------------------------
  { kode: 'inventaris.barang', nama: 'Data Barang', grup: 'Inventaris', menu_index: 31 },
  { kode: 'inventaris.peminjaman', nama: 'Peminjaman', grup: 'Inventaris', menu_index: 32 },

  // --- Pengaturan ----------------------------------------------------
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
    'kependudukan.warga': F,
    'kependudukan.kk': F,
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
    'kependudukan.warga': F,
    'kependudukan.kk': F,
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
    // Iuran ditagihkan per kartu keluarga, jadi bendahara perlu melihat
    // data warga untuk mencocokkan pembayaran — tetapi tidak mengubahnya.
    'kependudukan.warga': V,
    // WAJIB minimal `view`: Iuran Warga memuat `/api/families` untuk menagih
    // per kartu keluarga. Menutupnya di sini akan membuat layar Iuran gagal
    // memuat daftar KK-nya, padahal izin iurannya sendiri penuh.
    'kependudukan.kk': V,
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

  /**
   * Ketua RW mengawasi seluruh RT dalam RW-nya, dan itulah batas wewenangnya.
   *
   * Seluruh modul operasional diberi LIHAT saja. Alasannya bukan kehati-hatian
   * berlebihan melainkan pembagian tugas yang nyata: uang, data warga, dan
   * inventaris adalah tanggung jawab pengurus RT masing-masing. Ketua RW yang
   * bisa menyunting kas RT membuat pertanyaan "siapa yang mencatat ini"
   * kehilangan jawabannya.
   *
   * Satu pengecualian: Pengumuman boleh ia terbitkan, karena pengumuman
   * setingkat RW memang tidak punya pemilik RT.
   *
   * Modul bertanda `is_sistem` tetap tertutup — sama seperti peran lain, dan
   * penjaganya bukan baris ini melainkan middleware.
   */
  ketua_rw: {
    'kependudukan.warga': V,
    'kependudukan.kk': V,
    'kependudukan.bansos': V,
    'kependudukan.statistik': V,
    'keuangan.iuran': V,
    'keuangan.kas': V,
    'keuangan.bop': V,
    'inventaris.barang': V,
    'inventaris.peminjaman': V,
    'layanan.visitor': V,
    'layanan.surat': V,
    // Satu-satunya modul yang boleh ia isi: pengumuman lintas RT.
    'kegiatan.agenda': VC,
    'aspirasi.darurat': V,
    'aspirasi.pengaduan': V,
    'aspirasi.polling': V,
    'pengaturan.log': V,
    'pengaturan.akses': N,
    'pengaturan.reset': N,
  },

  warga: {
    'kependudukan.warga': N,
    // Warga tidak mengelola kartu keluarga RT. Tagihannya sendiri disaring
    // controller lewat `users.no_kk`, bukan lewat izin modul ini.
    'kependudukan.kk': N,
    'kependudukan.bansos': N,
    'kependudukan.statistik': N,
    // Controller sudah menyaring per user; izin ini cukup di tingkat modul.
    'keuangan.iuran': V,
    'keuangan.kas': V,
    'keuangan.bop': N,
    // Warga meminjam barang, bukan mengelola daftar inventarisnya.
    'inventaris.barang': N,
    'inventaris.peminjaman': VCD,
    'layanan.visitor': VCU,
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
const ROLES = ['admin', 'ketua_rw', 'ketua_rt', 'sekretaris', 'bendahara', 'warga'];

const ROLE_LABEL = {
  admin: 'Administrator',
  ketua_rw: 'Ketua RW',
  ketua_rt: 'Ketua RT',
  sekretaris: 'Sekretaris',
  bendahara: 'Bendahara',
  warga: 'Warga',
};

module.exports = { MENU_ITEMS, DEFAULT_PERMISSIONS, ROLES, ROLE_LABEL };
