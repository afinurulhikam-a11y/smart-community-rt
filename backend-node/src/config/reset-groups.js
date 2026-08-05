/**
 * Kelompok reset data sistem.
 *
 * Berkas ini adalah SATU-SATUNYA sumber kebenaran untuk apa yang dihapus dan
 * dengan urutan apa. Controller tidak pernah menerima nama tabel dari klien —
 * klien hanya mengirim `kode` kelompok, sisanya dibaca dari sini.
 *
 * ## Kenapa urutannya ditulis tangan
 *
 * Urutan penghapusan TIDAK BOLEH diserahkan ke Postgres. Dua jebakan nyata di
 * skema ini:
 *
 *   keluarga --CASCADE--> bills --RESTRICT--> bill_payments
 *
 * Menghapus `keluarga` memicu cascade ke `bills`, lalu cascade itu ditolak
 * `bill_payments` yang ber-RESTRICT, dan seluruh transaksi gagal. Satu-satunya
 * jalan adalah menghapus `bill_payments` lebih dulu, secara eksplisit.
 *
 *   users <--RESTRICT-- bills, bill_payments, finances, letters,
 *                       emergency_alerts, bop_finances, alokasi_bop, borrowings
 *
 * Menghapus akun warga selalu gagal selama masih ada satu saja baris di tabel
 * itu yang menunjuk kepadanya.
 *
 * Karena itu setiap kelompok menyebut tabelnya berurutan anak → induk, dan
 * baris yang ikut terhapus karena rantai FK ditandai `ikutan: true` supaya
 * pratinjau bisa menampilkannya terpisah. Tidak ada penghapusan diam-diam.
 */

/** Akun yang tidak pernah boleh terhapus, agar admin tidak mungkin terkunci. */
const ROLE_DILINDUNGI = ['admin', 'ketua_rt', 'sekretaris', 'bendahara'];

/** Dipakai berulang untuk membatasi penghapusan hanya pada milik warga. */
const AKUN_WARGA = "(SELECT id FROM users WHERE role = 'warga')";

/**
 * Tabel yang tidak boleh disentuh reset mana pun, termasuk Reset Total.
 *
 * `reset_logs` ikut dilindungi karena ia justru catatan bahwa reset pernah
 * terjadi — kalau ikut terhapus, jejaknya hilang bersama datanya.
 */
const TABEL_DILINDUNGI = [
  'roles',
  'users', // hanya baris role 'warga' yang boleh, lewat kelompok pengaturan.akun
  'menu_items',
  'role_permissions',
  'jenis_iuran',
  'kategori_kas',
  'kategori_bop',
  'struktur_rt',
  'master_pendidikan',
  'master_pekerjaan',
  'reset_logs',
  // Jejak audit. Dilindungi dari SETIAP kelompok, termasuk Reset Total —
  // sama seperti reset_logs, dan karena alasan yang sama: catatan pengawasan
  // tidak boleh bisa dihapus oleh pihak yang diawasi.
  'activity_logs',
];

/**
 * Daftar kelompok.
 *
 * `ikon` adalah kunci yang dipetakan Flutter ke IconData — backend sengaja
 * tidak tahu-menahu soal widget.
 */
const RESET_GROUPS = [
  {
    kode: 'keuangan.iuran',
    nama: 'Iuran & Pembayaran',
    deskripsi: 'Seluruh tagihan iuran warga, riwayat pembayaran, '
      + 'dan transaksi pembayaran online.',
    ikon: 'receipt',
    // Urutan anak → induk. bill_payments ber-RESTRICT terhadap bills, dan
    // kedua tabel pembayaran online ber-FK ke bills, jadi semuanya harus
    // habis lebih dulu.
    tabel: [
      { tabel: 'payment_transaction_bills' },
      { tabel: 'payment_transactions' },
      { tabel: 'bill_payments' },
      { tabel: 'bills' },
    ],
  },
  {
    kode: 'keuangan.kas',
    nama: 'Kas RT',
    deskripsi: 'Seluruh transaksi pemasukan dan pengeluaran kas RT.',
    ikon: 'wallet',
    tabel: [{ tabel: 'finances' }],
  },
  {
    kode: 'keuangan.bop',
    nama: 'Dana BOP',
    deskripsi: 'Transaksi dana BOP beserta pagu alokasinya.',
    ikon: 'akun_saldo',
    tabel: [
      { tabel: 'bop_finances' },
      { tabel: 'alokasi_bop' },
    ],
  },
  {
    kode: 'inventaris',
    nama: 'Inventaris & Peminjaman',
    deskripsi: 'Data barang milik RT beserta seluruh riwayat peminjaman.',
    ikon: 'kotak',
    // borrowings CASCADE dari inventory, tapi tetap ditulis eksplisit supaya
    // jumlahnya terhitung di pratinjau, bukan hilang diam-diam.
    tabel: [
      { tabel: 'borrowings' },
      { tabel: 'inventory' },
    ],
  },
  {
    kode: 'layanan',
    nama: 'Layanan Warga',
    deskripsi: 'Pengajuan surat menyurat dan buku tamu E-Visitor.',
    ikon: 'surat',
    tabel: [
      { tabel: 'letters' },
      { tabel: 'visitors' },
    ],
  },
  {
    kode: 'kegiatan',
    nama: 'Kegiatan & Informasi',
    deskripsi: 'Agenda kegiatan dan pengumuman warga.',
    ikon: 'kalender',
    tabel: [
      { tabel: 'agenda' },
      { tabel: 'announcements' },
    ],
  },
  {
    kode: 'aspirasi',
    nama: 'Aspirasi & Partisipasi',
    deskripsi: 'Polling warga, pengaduan, dan riwayat status darurat.',
    ikon: 'suara',
    tabel: [
      { tabel: 'polling_votes' },
      { tabel: 'polling_options' },
      { tabel: 'polling' },
      { tabel: 'complaints' },
      { tabel: 'emergency_alerts' },
    ],
  },
  {
    kode: 'bansos',
    nama: 'Bantuan Sosial',
    deskripsi: 'Data penerima bantuan sosial beserta log perubahannya.',
    ikon: 'bantuan',
    tabel: [
      { tabel: 'bantuan_sosial_log' },
      { tabel: 'bantuan_sosial' },
    ],
  },
  {
    kode: 'kependudukan',
    nama: 'Data Warga & Keluarga',
    deskripsi: 'Seluruh kartu keluarga dan anggotanya. Tagihan iuran melekat '
      + 'pada kartu keluarga, jadi ikut terhapus.',
    ikon: 'keluarga',
    // keluarga --CASCADE--> bills --RESTRICT--> bill_payments.
    // Tabel-tabel di depan wajib didahulukan atau seluruh transaksi gagal.
    // payment_transactions juga ber-FK ke keluarga, jadi ikut lebih dulu.
    tabel: [
      { tabel: 'payment_transaction_bills', ikutan: true },
      { tabel: 'payment_transactions', ikutan: true },
      { tabel: 'bill_payments', ikutan: true },
      { tabel: 'bills', ikutan: true },
      { tabel: 'anggota_keluarga' },
      { tabel: 'keluarga' },
    ],
  },
  {
    kode: 'akun',
    nama: 'Akun Warga',
    deskripsi: 'Akun login milik warga. Akun admin dan pengurus tidak tersentuh.',
    ikon: 'akun',
    // Delapan tabel pertama ber-RESTRICT terhadap users: selama masih ada satu
    // baris yang menunjuk akun warga, penghapusan akun pasti gagal. Sisanya
    // ber-CASCADE, tetap ditulis agar jumlahnya muncul di pratinjau.
    //
    // Semua WHERE dibatasi ke akun warga, sehingga transaksi yang dicatat
    // pengurus TIDAK ikut terhitung maupun terhapus.
    tabel: [
      // payment_transactions.user_id ber-RESTRICT terhadap users, jadi
      // transaksi pembayaran milik warga harus habis sebelum akunnya dihapus.
      { tabel: 'payment_transaction_bills', where: `transaction_id IN (SELECT id FROM payment_transactions WHERE user_id IN ${AKUN_WARGA})`, ikutan: true },
      { tabel: 'payment_transactions', where: `user_id IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'bill_payments', where: `user_id IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'bills', where: `user_id IN ${AKUN_WARGA} OR created_by IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'letters', where: `user_id IN ${AKUN_WARGA} OR approved_by IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'emergency_alerts', where: `user_id IN ${AKUN_WARGA} OR dismissed_by IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'borrowings', where: `user_id IN ${AKUN_WARGA} OR dicatat_oleh IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'finances', where: `created_by IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'bop_finances', where: `created_by IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'alokasi_bop', where: `created_by IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'polling_votes', where: `user_id IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'complaints', where: `user_id IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'bantuan_sosial_log', where: `bantuan_sosial_id IN (SELECT id FROM bantuan_sosial WHERE user_id IN ${AKUN_WARGA})`, ikutan: true },
      { tabel: 'bantuan_sosial', where: `user_id IN ${AKUN_WARGA}`, ikutan: true },
      { tabel: 'users', where: "role = 'warga'" },
    ],
  },
  // Kelompok 'log' DIHAPUS dengan sengaja.
  //
  // Dulu ada kelompok reset "Log Aktivitas" yang mengosongkan `activity_logs`.
  // Bersama endpoint `DELETE /api/activity-logs`, itu berarti seorang
  // administrator bisa melenyapkan seluruh bukti perbuatannya sendiri —
  // tepat pada satu keadaan yang paling membutuhkan jejak audit.
  //
  // `activity_logs` kini ada di TABEL_DILINDUNGI, dan database menolak DELETE
  // atasnya lewat trigger `trg_activity_logs_append_only`. Bila kelompok ini
  // dihidupkan lagi, pemeriksaan mandiri di bawah berkas ini akan melempar
  // galat saat server dinyalakan — bukan menghancurkan data saat dijalankan.
  {
    kode: 'sensor',
    nama: 'Data Sensor Perangkat',
    deskripsi: 'Rekaman pembacaan sensor dari perangkat ESP32.',
    ikon: 'sensor',
    tabel: [{ tabel: 'sensor_logs' }],
  },
];

/**
 * Urutan penghapusan untuk Reset Total.
 *
 * Ditulis terpisah, bukan digabung dari daftar kelompok, karena urutan aman
 * secara global berbeda dengan urutan aman per kelompok. Contohnya `bills`
 * harus habis sebelum `keluarga` DAN sebelum `users`.
 *
 * `users` sengaja paling akhir: barulah semua RESTRICT yang menunjuk kepadanya
 * sudah kosong.
 */
const URUTAN_TOTAL = [
  { tabel: 'payment_transaction_bills' },
  { tabel: 'payment_transactions' },
  { tabel: 'bill_payments' },
  { tabel: 'bills' },
  { tabel: 'bantuan_sosial_log' },
  { tabel: 'bantuan_sosial' },
  { tabel: 'borrowings' },
  { tabel: 'inventory' },
  { tabel: 'polling_votes' },
  { tabel: 'polling_options' },
  { tabel: 'polling' },
  { tabel: 'complaints' },
  { tabel: 'emergency_alerts' },
  { tabel: 'letters' },
  { tabel: 'visitors' },
  { tabel: 'agenda' },
  { tabel: 'announcements' },
  { tabel: 'finances' },
  { tabel: 'bop_finances' },
  { tabel: 'alokasi_bop' },
  { tabel: 'anggota_keluarga' },
  { tabel: 'keluarga' },
  { tabel: 'sensor_logs' },
  // `activity_logs` sengaja TIDAK ada di sini. Reset Total pun tidak boleh
  // menghapus jejak audit — kalau boleh, seluruh perlindungannya sia-sia
  // karena tinggal menjalankan Reset Total untuk membersihkan diri.
  { tabel: 'users', where: "role = 'warga'" },
];

const GRUP_TOTAL = {
  kode: 'total',
  nama: 'Reset Total Sistem',
  deskripsi: 'Menghapus seluruh data operasional. Akun admin dan pengurus, '
    + 'master iuran/kas/BOP, serta menu dan hak akses tetap utuh.',
  ikon: 'peringatan',
  konfirmasi: 'RESET TOTAL DATA',
  tabel: URUTAN_TOTAL,
};

/** Frasa yang harus diketik pengguna. Nama kelompok, kecuali Reset Total. */
function frasaKonfirmasi(grup) {
  return grup.konfirmasi || grup.nama;
}

function cariGrup(kode) {
  if (kode === GRUP_TOTAL.kode) return GRUP_TOTAL;
  return RESET_GROUPS.find((g) => g.kode === kode) || null;
}

/**
 * Penjaga terakhir: pastikan tidak ada kelompok yang menyentuh tabel
 * dilindungi. Dijalankan sekali saat modul dimuat, sehingga salah ketik nama
 * tabel menghentikan server saat start — bukan menghapus data saat dipakai.
 */
(function periksaRegistry() {
  const semua = [...RESET_GROUPS, GRUP_TOTAL];
  for (const g of semua) {
    for (const t of g.tabel) {
      if (!TABEL_DILINDUNGI.includes(t.tabel)) continue;
      // `users` satu-satunya pengecualian, dan hanya bila dibatasi role warga.
      const bolehkan = t.tabel === 'users' && t.where === "role = 'warga'";
      if (!bolehkan) {
        throw new Error(
          `reset-groups.js: kelompok "${g.kode}" menyentuh tabel dilindungi `
          + `"${t.tabel}". Perbaiki registry sebelum server dijalankan.`
        );
      }
    }
  }
})();

module.exports = {
  RESET_GROUPS,
  GRUP_TOTAL,
  TABEL_DILINDUNGI,
  ROLE_DILINDUNGI,
  cariGrup,
  frasaKonfirmasi,
};
