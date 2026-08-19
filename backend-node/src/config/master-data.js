/**
 * Isi bawaan tabel master.
 *
 * Dipisahkan dari `schema.sql` supaya struktur dan isi tidak tercampur, dan
 * dipakai `seed-master.js` saat memasang dari nol. Admin bebas mengubahnya
 * lewat layar masing-masing setelah terpasang; berkas ini hanya titik awal.
 */

// Hanya SATU jenis iuran, dan ia berbasis meteran.
//
// Sebelumnya ada tiga iuran bernominal tetap — keamanan, kebersihan, dan sosial.
// Ketiganya dihapus karena RT ini menagih lewat tagihan air, dan biaya sampah
// sudah menjadi salah satu komponen di dalamnya. Menagihnya terpisah berarti
// warga membayar kebersihan dua kali.
//
//     total = (terpakai m³ × tarif_per_m3) + abondement + biaya_sampah
//
// Angka bawaan ini mengikuti tagihan yang berjalan di RT: 4 m³ menghasilkan
// Rp 67.000. Rumah yang tidak memakai air sama sekali tetap membayar Rp 55.000,
// karena abondement dan sampah tidak bergantung pada pemakaian.
//
// Pengurus bisa mengubah ketiganya lewat layar master; nilai di sini hanya
// titik awal saat memasang dari nol.
const JENIS_IURAN = [
  {
    nama: 'Iuran Air Sumur Bor',
    nominal: 0,
    periode: 'bulanan',
    tipe_hitung: 'meteran',
    tarif_per_m3: 3000,
    abondement: 25000,
    biaya_sampah: 30000,
  },
];

/** `tipe` IN = pemasukan, OUT = pengeluaran. */
const KATEGORI_KAS = [
  { nama: 'Pemasukan Iuran Bulanan', tipe: 'IN' },
  { nama: 'Dana Bantuan / Donasi', tipe: 'IN' },
  { nama: 'Biaya Keamanan', tipe: 'OUT' },
  { nama: 'Biaya Kebersihan / Sampah', tipe: 'OUT' },
  { nama: 'Biaya Kegiatan Lomba', tipe: 'OUT' },
];

// Pemasukan BOP hanya punya SATU kategori, dan itu disengaja.
//
// Dulu ada "Bantuan Lain" di sini, dan itulah satu-satunya jalan uang non-BOP
// bisa masuk ke buku ini. Akibatnya `sisa_pagu` menjadi angka yang maknanya
// bisa diperdebatkan: `terpakai` menjumlah SELURUH pengeluaran tanpa melihat
// asal uangnya, jadi membelanjakan sumbangan donatur ikut memotong jatah BOP
// yang belum tersentuh. RT tampak sudah memakai anggarannya padahal belum.
//
// Kategori itu dibuang, bukan ditambal, karena tidak ada satu pun keadaan yang
// benar-benar membutuhkannya:
//
//   - Sumbangan donatur bukan uang BOP. Ia tidak berpagu dan tidak
//     dipertanggungjawabkan ke kelurahan. Tempatnya di Kas RT, yang sudah punya
//     kategori "Dana Bantuan / Donasi" di KATEGORI_KAS di atas.
//   - Dana tambahan dari kelurahan memang uang BOP — tetapi mencatatnya sebagai
//     pemasukan biasa membuat kasnya bertambah tanpa pagunya ikut bertambah.
//     Yang benar adalah alokasi termin berikutnya; `alokasi_bop` sudah punya
//     kolom `termin` dan `sumber_dana` persis untuk itu.
//
// Dengan begitu pemasukan BOP dijamin selalu berasal dari pencairan alokasi,
// sehingga setiap pengeluaran BOP memang membelanjakan uang jatah — dan
// `terpakai` = seluruh pengeluaran menjadi benar tanpa syarat.
//
// Pemasangan yang sudah berjalan tetap menyimpan barisnya dengan
// `is_aktif = false`, bukan dihapus, agar riwayatnya utuh dan bisa dihidupkan
// lagi bila ternyata keliru. `auto-setup.js` dan `seed-master.js` sama-sama
// memakai ON CONFLICT DO NOTHING di atas unique index `nama_kategori`, jadi
// deploy berikutnya tidak akan menghidupkannya kembali.
const KATEGORI_BOP = [
  { nama: 'Pencairan Dana BOP', tipe: 'IN' },
  { nama: 'Honor Pengurus RT', tipe: 'OUT' },
  { nama: 'ATK & Administrasi', tipe: 'OUT' },
  { nama: 'Kegiatan Warga', tipe: 'OUT' },
  { nama: 'Pemeliharaan Sarana', tipe: 'OUT' },
  { nama: 'Konsumsi Rapat', tipe: 'OUT' },
];

/**
 * Akun administrator pertama. Password WAJIB diganti setelah login pertama.
 * Role disimpan di kolom `users.role` bertipe VARCHAR — tidak ada tabel roles.
 */
const ADMIN_AWAL = {
  nama: 'Administrator',
  email: 'admin@example.com',
  // Tampil apa adanya di layar Profil Saya, jadi ditulis untuk dibaca manusia.
  // Pemasangan lama menyimpan `admin_developer` warisan migrasi
  // `database/migrations-lama/fix-db.js`; seed-master merapikannya.
  username: 'Developer',
  password: 'admin123',
  role: 'admin',
};

/**
 * Akun pengurus RT bawaan untuk mempermudah login & pengujian peran.
 */
const PENGURUS_AWAL = [
  {
    nama: 'Ketua RT',
    email: 'ketua@example.com',
    username: 'ketua',
    password: 'ketua123',
    role: 'ketua_rt',
  },
  {
    nama: 'Sekretaris RT',
    email: 'sekretaris@example.com',
    username: 'sekretaris',
    password: 'sekretaris123',
    role: 'sekretaris',
  },
  {
    nama: 'Bendahara RT',
    email: 'bendahara@example.com',
    username: 'bendahara',
    password: 'bendahara123',
    role: 'bendahara',
  },
];

/**
 * Akun warga untuk uji coba.
 *
 * Akun warga sebenarnya dibuat otomatis oleh Data Warga dengan NIK sebagai
 * username sekaligus email (password `123456`). Akun ini ada supaya sisi warga
 * bisa dicoba tanpa harus mengisi kartu keluarga lebih dulu — `login`
 * mencocokkan `email = $1 OR username = $1`, jadi emailnya bisa diketik di
 * kolom username.
 *
 * Ia sengaja TIDAK punya `no_kk`. Akibatnya layar Tagihan Saya akan kosong,
 * karena tagihan disaring lewat kartu keluarga — itu perilaku yang benar,
 * bukan error. Untuk mengujinya berisi, buat satu KK lewat Data Warga lalu
 * samakan `no_kk`-nya, atau pakai akun warga bikinan Data Warga.
 */
const WARGA_UJI = {
  nama: 'Demo Warga',
  email: 'warga@example.com',
  username: 'warga',
  password: 'warga123',
  role: 'warga',
};

module.exports = {
  JENIS_IURAN, KATEGORI_KAS, KATEGORI_BOP, ADMIN_AWAL, PENGURUS_AWAL, WARGA_UJI,
};

