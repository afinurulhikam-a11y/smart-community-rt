/**
 * Isi bawaan tabel master.
 *
 * Dipisahkan dari `schema.sql` supaya struktur dan isi tidak tercampur, dan
 * dipakai `seed-master.js` saat memasang dari nol. Admin bebas mengubahnya
 * lewat layar masing-masing setelah terpasang; berkas ini hanya titik awal.
 */

const JENIS_IURAN = [
  { nama: 'Iuran Wajib Bulanan (Keamanan & Kas RT)', nominal: 50000, periode: 'bulanan' },
  { nama: 'Iuran Kebersihan & Pengangkutan Sampah', nominal: 25000, periode: 'bulanan' },
  { nama: 'Iuran Sosial & Duka Cita', nominal: 10000, periode: 'bulanan' },
];

/** `tipe` IN = pemasukan, OUT = pengeluaran. */
const KATEGORI_KAS = [
  { nama: 'Pemasukan Iuran Bulanan', tipe: 'IN' },
  { nama: 'Dana Bantuan / Donasi', tipe: 'IN' },
  { nama: 'Biaya Keamanan', tipe: 'OUT' },
  { nama: 'Biaya Kebersihan / Sampah', tipe: 'OUT' },
  { nama: 'Biaya Kegiatan Lomba', tipe: 'OUT' },
];

const KATEGORI_BOP = [
  { nama: 'Pencairan Dana BOP', tipe: 'IN' },
  { nama: 'Bantuan Lain', tipe: 'IN' },
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
  nama: 'Warga Demo',
  email: 'warga@example.com',
  password: 'warga123',
  role: 'warga',
};

module.exports = {
  JENIS_IURAN, KATEGORI_KAS, KATEGORI_BOP, ADMIN_AWAL, WARGA_UJI,
};
