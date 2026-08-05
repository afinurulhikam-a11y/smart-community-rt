/**
 * Pemeriksaan variabel lingkungan saat startup.
 *
 * ===================================================================
 * Kenapa memilih berhenti, bukan memakai nilai bawaan
 * ===================================================================
 *
 * Sebelumnya PIN darurat ditulis `process.env.EMERGENCY_PIN || '1234'`, dan
 * `.env.example` mengirim angka yang sama. Nilai bawaan seperti itu terasa
 * ramah — sistem tetap jalan walau lupa dikonfigurasi — tetapi akibatnya
 * justru sebaliknya: lupa mengaturnya tidak menimbulkan gejala apa pun, jadi
 * tidak ada yang pernah menyadarinya, dan PIN yang melindungi tombol darurat
 * seluruh RT adalah empat angka yang tertulis di repositori publik.
 *
 * Berhenti saat startup mengubah kegagalan diam menjadi kegagalan yang
 * berisik. Satu-satunya waktu yang tepat untuk mengetahui konfigurasi kurang
 * adalah sebelum server menerima permintaan pertama.
 */

/**
 * Wajib ada. Server menolak menyala tanpa ini.
 *
 * Isinya hanya hal yang tanpanya sistem memang tidak bisa bekerja sama sekali.
 * Daftar ini sengaja dijaga pendek: setiap tambahan di sini adalah satu cara
 * baru sebuah deploy bisa gagal total, dan pengetatan keamanan tidak boleh
 * berubah menjadi penyebab matinya layanan.
 */
const WAJIB = {
  JWT_SECRET: 'menandatangani token sesi — tanpa ini tidak ada yang bisa masuk',
};

/**
 * Fitur yang MATI bila variabelnya kosong, tetapi tidak menghentikan server.
 *
 * `EMERGENCY_PIN` ada di sini, bukan di WAJIB, dan itu keputusan yang
 * disengaja. Menjadikannya wajib berarti sebuah deploy yang lupa mengisinya
 * mematikan SELURUH aplikasi — iuran, kas, surat, semuanya — demi satu fitur.
 * Padahal gagal-tertutup di endpoint-nya sendiri sudah cukup: tombol darurat
 * menolak bekerja dan mengatakan alasannya, sementara sisa sistem tetap hidup.
 *
 * Yang tidak boleh terjadi adalah nilai bawaan diam-diam seperti '1234'
 * sebelumnya — itu membuat lupa mengonfigurasi tidak menimbulkan gejala apa pun.
 */
const FITUR_MATI = {
  EMERGENCY_PIN: 'Tombol darurat NONAKTIF sampai variabel ini diisi',
};

/** Sebaiknya ada. Dicatat sebagai peringatan, tidak menghentikan server. */
const DISARANKAN = {
  CORS_ORIGIN: 'membatasi asal yang boleh memanggil API (bawaan: * — terbuka)',
};

function periksaEnv() {
  const hilang = [];
  for (const [nama, alasan] of Object.entries(WAJIB)) {
    const nilai = process.env[nama];
    if (!nilai || nilai.trim() === '') hilang.push(`  ✗ ${nama} — ${alasan}`);
  }

  // Panjang minimum untuk JWT_SECRET. Rahasia sepanjang "rahasia" bisa ditebak
  // dengan daftar kata, dan siapa pun yang menebaknya bisa menempa token untuk
  // peran apa pun — termasuk admin.
  if (process.env.JWT_SECRET && process.env.JWT_SECRET.length < 32) {
    hilang.push('  ✗ JWT_SECRET terlalu pendek (minimal 32 karakter)');
  }

  if (hilang.length > 0) {
    console.error('\n❌ Konfigurasi belum lengkap. Server dihentikan.\n');
    console.error(hilang.join('\n'));
    console.error('\nIsi nilainya di berkas .env (lokal) atau Variables (Railway), lalu jalankan ulang.\n');
    process.exit(1);
  }

  for (const [nama, akibat] of Object.entries(FITUR_MATI)) {
    if (!process.env[nama] || process.env[nama].trim() === '') {
      console.warn(`\n⚠️  ${nama} belum disetel — ${akibat}.\n`);
    }
  }

  // PIN yang pernah menjadi nilai bawaan tidak boleh dipakai lagi: ia sudah
  // terlanjur tertulis di repositori dan di .env.example, jadi memakainya sama
  // saja dengan tidak memakai PIN.
  if (process.env.EMERGENCY_PIN === '1234') {
    console.warn('\n⚠️  EMERGENCY_PIN masih 1234 — angka itu tertulis di repositori. Ganti sekarang.\n');
  }

  for (const [nama, alasan] of Object.entries(DISARANKAN)) {
    if (!process.env[nama]) console.warn(`⚠️  ${nama} belum disetel — ${alasan}`);
  }

  console.log('✅ Variabel lingkungan wajib terverifikasi.');
}

module.exports = { periksaEnv };
