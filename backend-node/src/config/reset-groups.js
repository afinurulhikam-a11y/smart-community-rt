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

/**
 * Akun yang tidak pernah boleh terhapus, agar admin tidak mungkin terkunci.
 *
 * `ketua_rw` masuk daftar ini karena alasan yang sama persis dengan tiga peran
 * pengurus di sebelahnya, dan alasan itu menjadi LEBIH kuat sejak satu
 * pemasangan melayani beberapa RT: ia satu-satunya peran selain administrator
 * yang melihat seluruh RW, jadi kehilangannya berarti kehilangan satu-satunya
 * sudut pandang lintas RT yang bukan administrator. Ia sempat tertinggal di
 * sini setelah perannya ditambahkan, dan Reset Total akan menghapusnya.
 */
const ROLE_DILINDUNGI = ['admin', 'ketua_rw', 'ketua_rt', 'sekretaris', 'bendahara'];

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
  'master_pendidikan',
  'master_pekerjaan',
  'reset_logs',
  // Daftar RT. Menghapusnya berarti setiap baris di 18 tabel lain kehilangan
  // acuan RT-nya sekaligus — dan kunci asingnya ON DELETE RESTRICT, jadi
  // percobaannya akan menggagalkan seluruh transaksi reset di tengah jalan.
  // Menghapus sebuah RT dilakukan lewat layarnya sendiri, satu per satu,
  // dan hanya setelah RT itu benar-benar kosong.
  'rt',
  // Jejak audit. Dilindungi dari SETIAP kelompok, termasuk Reset Total —
  // sama seperti reset_logs, dan karena alasan yang sama: catatan pengawasan
  // tidak boleh bisa dihapus oleh pihak yang diawasi.
  'activity_logs',
];


/**
 * ===================================================================
 * Reset per RT
 * ===================================================================
 *
 * Sejak satu pemasangan melayani beberapa RT, "Reset Data Warga" yang
 * menghapus seluruh RW adalah pilihan yang tidak pernah diminta siapa pun.
 * Administrator yang sedang melihat RT 002 dan menekan Reset mengharapkan
 * RT 002 — bukan seluruh kampung.
 *
 * Yang menentukan lingkupnya adalah pemilih RT yang sama dengan seluruh
 * aplikasi (`rtAktif`): ada RT terpilih berarti hanya RT itu, tidak ada
 * berarti seluruh RW seperti sebelumnya.
 *
 * `$rt` adalah tempat nomor parameter disisipkan saat kueri disusun — bukan
 * nilainya. Nilai RT tidak pernah disambung sebagai teks ke dalam SQL.
 *
 * Tabel yang tidak punya `rt_id` dilingkupi LEWAT INDUKNYA, mengikuti
 * keputusan v43: yang bertempat tinggal di sebuah RT adalah kartu keluarga,
 * dan tagihan, bacaan meteran, serta pembayarannya mengikuti.
 */
const LINGKUP_RT = Object.freeze({
  // Punya rt_id sendiri.
  keluarga: 'rt_id = $rt',
  users: 'rt_id = $rt',
  finances: 'rt_id = $rt',
  bop_finances: 'rt_id = $rt',
  alokasi_bop: 'rt_id = $rt',
  inventory: 'rt_id = $rt',
  borrowings: 'rt_id = $rt',
  agenda: 'rt_id = $rt',
  announcements: 'rt_id = $rt',
  polling: 'rt_id = $rt',
  visitors: 'rt_id = $rt',
  complaints: 'rt_id = $rt',
  letters: 'rt_id = $rt',
  emergency_alerts: 'rt_id = $rt',
  bantuan_sosial: 'rt_id = $rt',

  // Lewat kartu keluarga.
  anggota_keluarga: 'keluarga_id IN (SELECT id FROM keluarga WHERE rt_id = $rt)',
  bills: 'keluarga_id IN (SELECT id FROM keluarga WHERE rt_id = $rt)',
  pembacaan_meteran: 'keluarga_id IN (SELECT id FROM keluarga WHERE rt_id = $rt)',
  payment_transactions: 'keluarga_id IN (SELECT id FROM keluarga WHERE rt_id = $rt)',
  bill_payments:
    'bill_id IN (SELECT b.id FROM bills b JOIN keluarga k ON k.id = b.keluarga_id WHERE k.rt_id = $rt)',
  payment_transaction_bills:
    'bill_id IN (SELECT b.id FROM bills b JOIN keluarga k ON k.id = b.keluarga_id WHERE k.rt_id = $rt)',

  // Lewat induk masing-masing.
  polling_options: 'polling_id IN (SELECT id FROM polling WHERE rt_id = $rt)',
  polling_votes: 'polling_id IN (SELECT id FROM polling WHERE rt_id = $rt)',
  bantuan_sosial_log: 'bantuan_sosial_id IN (SELECT id FROM bantuan_sosial WHERE rt_id = $rt)',
});

/**
 * Tabel yang memang TIDAK punya dimensi RT.
 *
 * `sensor_logs` adalah telemetri perangkat: barisnya hanya memuat jenis
 * sensor, nilai, dan waktu. Tidak ada kolom yang bisa menghubungkannya ke
 * sebuah RT, dan menebaknya dari perangkat mana pun berarti menghapus bacaan
 * RT lain.
 *
 * Kelompok yang memuat tabel semacam ini DITOLAK ketika sebuah RT sedang
 * dipilih — bukan dijalankan dengan tabel itu dilewati diam-diam, dan bukan
 * pula dijalankan menyeluruh. Keduanya menghasilkan hal yang sama buruknya:
 * seorang administrator yang mengira sedang menghapus data satu RT.
 */
const TABEL_TANPA_RT = Object.freeze(['sensor_logs']);

/**
 * Ekspresi pembatas RT untuk sebuah tabel, dengan `$rt` sudah diganti nomor
 * parameter. `null` berarti tabelnya tidak bisa dilingkupi.
 */
function polaLingkupRt(tabel, nomorParam) {
  const pola = LINGKUP_RT[tabel];
  if (!pola) return null;
  // split/join, bukan replaceAll: dalam string pengganti `replace`, `$` punya
  // arti khusus ($&, $1, $$), dan nomor parameter kita SELALU diawali `$`.
  return pola.split('$rt').join(`$${nomorParam}`);
}

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
    //
    // Baris Kas RT paling dulu, dan HANYA yang lahir dari pembayaran iuran.
    //
    // `catatKeKasRt` menautkannya lewat `finances.ref_id -> bill_payments.id`.
    // Tanpa entri ini, mereset grup Iuran saja akan membuang pembayarannya
    // tetapi meninggalkan uangnya di buku kas — saldo Kas RT tetap memuat
    // pemasukan dari tagihan yang sudah tidak ada, dan tidak ada gejala apa pun
    // karena barisnya tampak seperti pemasukan biasa.
    //
    // Penyaring `sumber = 'iuran'` itu yang menjaga grup ini tidak menyentuh
    // pemasukan dan pengeluaran manual — itu wilayah grup Kas RT, bukan ini.
    //
    // `ikutan: true` karena baris ini mati akibat rantai FK-nya, bukan karena
    // ia sasaran grup ini; pratinjau menampilkannya terpisah supaya tidak ada
    // yang terhapus diam-diam.
    //
    // `pembacaan_meteran` ikut, dan itu bukan kelengkapan belaka. FK-nya ke
    // `bills` adalah ON DELETE SET NULL, jadi menghapus tagihan saja
    // meninggalkan bacaannya hidup dengan `bill_id` kosong. Akibatnya dua:
    // rantai `meteran_lalu` periode berikutnya berlanjut dari angka yang
    // tagihannya sudah tidak ada, dan warga bisa mengubah lagi bacaan periode
    // lampau — karena yang mengunci bacaan justru `bill_id IS NOT NULL`.
    tabel: [
      { tabel: 'finances', where: "sumber = 'iuran'", ikutan: true },
      { tabel: 'payment_transaction_bills' },
      { tabel: 'payment_transactions' },
      { tabel: 'bill_payments' },
      { tabel: 'pembacaan_meteran' },
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
  { tabel: 'pembacaan_meteran' },
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

/**
 * Frasa yang harus diketik pengguna. Nama kelompok, kecuali Reset Total.
 *
 * Ketika sebuah RT sedang dipilih, nomornya IKUT masuk ke dalam frasa —
 * "RESET TOTAL DATA RT 002". Itu bukan hiasan: lingkup sebuah penghapusan
 * adalah hal yang paling berbahaya untuk salah dikira, dan frasa yang harus
 * diketik ulang adalah satu-satunya tempat di seluruh alur ini yang dijamin
 * dibaca. Peringatan di layar bisa dilewati; kotak konfirmasi tidak.
 */
function frasaKonfirmasi(grup, kodeRt) {
  const dasar = grup.konfirmasi || grup.nama;
  return kodeRt ? `${dasar} RT ${kodeRt}` : dasar;
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

/**
 * Penjaga kedua: setiap tabel di setiap kelompok harus punya cara dilingkupi
 * per RT, ATAU dinyatakan terang-terangan tidak punya dimensi RT.
 *
 * Tanpa pemeriksaan ini, sebuah tabel baru yang ditambahkan ke registry tanpa
 * entri di `LINGKUP_RT` akan diam-diam terlewat dari penghapusan per RT —
 * penghapusan yang tampak berhasil sambil meninggalkan datanya utuh. Salah
 * ketik nama tabel karena itu menghentikan server saat start, bukan
 * menghasilkan reset yang setengah jalan saat dipakai.
 */
(function periksaLingkupRt() {
  const semua = [...RESET_GROUPS, GRUP_TOTAL];
  for (const g of semua) {
    for (const t of g.tabel) {
      if (LINGKUP_RT[t.tabel] || TABEL_TANPA_RT.includes(t.tabel)) continue;
      throw new Error(
        `reset-groups.js: tabel "${t.tabel}" pada kelompok "${g.kode}" belum `
        + 'punya entri di LINGKUP_RT dan belum dinyatakan di TABEL_TANPA_RT.'
      );
    }
  }
})();

module.exports = {
  RESET_GROUPS,
  GRUP_TOTAL,
  TABEL_DILINDUNGI,
  TABEL_TANPA_RT,
  ROLE_DILINDUNGI,
  cariGrup,
  frasaKonfirmasi,
  polaLingkupRt,
};
