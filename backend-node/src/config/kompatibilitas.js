/**
 * Saklar kompatibilitas mundur — satu tempat, supaya pencabutannya sekali ubah.
 *
 * ===================================================================
 * Kenapa `?token=` masih hidup padahal tiket unduh sudah ada
 * ===================================================================
 *
 * Backend dan klien tidak naik pada detik yang sama. Flutter Web produksi yang
 * sedang berjalan hari ini masih menyusun URL unduhan dengan `?token=<jwt>`;
 * kalau backend Fase B naik dengan jalur itu sudah tertutup, SETIAP tombol
 * Export di produksi mati seketika — dan matinya tidak terlihat sebagai galat
 * yang bisa ditebak, melainkan sebagai "aplikasi tiba-tiba rusak".
 *
 * Jadi urutannya: tiket unduh dipasang dan diuji SEKARANG, `?token=` dibiarkan
 * hidup berdampingan, lalu dicabut setelah klien baru terverifikasi di
 * produksi. Dua jalur berjalan bersamaan untuk sementara, bukan selamanya.
 *
 * ===================================================================
 * Kenapa saklar env, bukan sekadar "nanti dihapus"
 * ===================================================================
 *
 * "Nanti dihapus" tidak punya tanggal dan tidak punya cara diuji. Sebuah saklar
 * punya keduanya: pencabutannya bisa dicoba lebih dulu di lingkungan uji
 * (`IZINKAN_TOKEN_QUERY=false`) tanpa mengubah satu baris kode pun, dan
 * dibalikkan seketika bila ternyata masih ada pemanggil yang tertinggal.
 *
 * Bawaannya SENGAJA `true` — permisif. Deploy yang lupa mengisinya tidak boleh
 * mematikan klien lama; itu justru kejadian yang saklar ini ada untuk mencegah.
 * Arah amannya baru berbalik setelah klien baru terbukti jalan.
 *
 * ===================================================================
 * Apa yang TIDAK dilonggarkan oleh saklar ini
 * ===================================================================
 *
 * Token dari query melewati `jwt.verify` DAN seluruh pemeriksaan database yang
 * sama persis dengan token dari header — termasuk `token_versi`. Sesi yang
 * sudah dicabut tetap ditolak walau tokennya dikirim lewat URL. Yang
 * dikembalikan saklar ini hanyalah CARA token dibawa, bukan kelonggaran atas
 * siapa yang boleh masuk.
 *
 * Risiko yang tetap terbuka selama `true`, dan itu memang harganya: URL lengkap
 * beserta tokennya tercatat di log akses server dan proxy, riwayat browser, dan
 * header `Referer`. Yang meringankan sejak Fase B — token yang bocor begitu
 * sekarang bisa dimatikan dengan menekan Keluar.
 */

/** `false` hanya bila diisi eksplisit; apa pun selain itu berarti masih hidup. */
const IZINKAN_TOKEN_QUERY = process.env.IZINKAN_TOKEN_QUERY !== 'false';

/**
 * Mencatat pemakaian jalur legacy, dibatasi laju supaya tidak membanjiri log.
 *
 * Ini bukan hiasan: ia satu-satunya cara mengetahui KAPAN saklarnya boleh
 * dimatikan. Selama baris ini masih muncul, masih ada klien lama di luar sana.
 * Begitu ia berhenti muncul selama beberapa hari, pencabutannya aman.
 */
let _terakhirDicatat = 0;
const _JEDA_CATAT_MS = 60_000;

function catatPemakaianTokenQuery(req) {
  const sekarang = Date.now();
  if (sekarang - _terakhirDicatat < _JEDA_CATAT_MS) return;
  _terakhirDicatat = sekarang;
  // Tokennya sendiri TIDAK ikut dicatat — menuliskannya ke log adalah persis
  // kebocoran yang sedang dibicarakan.
  console.warn(
    `[LEGACY] ?token= masih dipakai → ${req.method} ${req.path}`
    + ' — klien lama belum diperbarui; jangan setel IZINKAN_TOKEN_QUERY=false dulu.'
  );
}

module.exports = { IZINKAN_TOKEN_QUERY, catatPemakaianTokenQuery };
