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

/**
 * ===================================================================
 * Keterangan kejadian darurat: wajib, tetapi belum hari ini
 * ===================================================================
 *
 * Tombol NYALAKAN kini menuntut keterangan kejadian. Masalahnya sama persis
 * dengan `?token=` di atas, hanya taruhannya lebih tinggi: **APK 1.1.0+3 yang
 * beredar sekarang mengirim ON tanpa `keterangan`**. Kalau backend naik dengan
 * aturan itu langsung ditegakkan, setiap ponsel yang belum diperbarui akan
 * dijawab 400 — dan yang mati bukan tombol Export, melainkan TOMBOL DARURAT.
 *
 * Kegagalan itu juga muncul pada saat paling buruk: bukan ketika orang membuka
 * aplikasi santai, melainkan ketika ada yang benar-benar menekannya.
 *
 * Karena itu penegakannya bertahap:
 *
 *   Tahap 1 (sekarang) — backend menerima ON tanpa keterangan dari klien lama,
 *     menandainya jelas-jelas sebagai legacy, dan mencatatnya. Klien BARU tetap
 *     mewajibkan 5–500 karakter di UI-nya, jadi keterangan sungguhan mulai
 *     terkumpul sejak hari pertama.
 *
 *   Tahap 2 (setelah APK baru terdistribusi) — `WAJIBKAN_KETERANGAN_DARURAT=true`,
 *     dan ON tanpa keterangan ditolak 400.
 *
 * Bawaannya SENGAJA `false` — permisif — dengan alasan yang sama seperti di
 * atas: deploy yang lupa mengisi variabel ini tidak boleh mematikan tombol
 * darurat siapa pun. Arah amannya baru berbalik setelah klien baru terbukti
 * jalan di produksi.
 *
 * ===================================================================
 * Apa yang TIDAK dilonggarkan
 * ===================================================================
 *
 * Kelonggaran ini hanya berlaku untuk keterangan yang **tidak dikirim sama
 * sekali**. Keterangan yang dikirim tetapi melanggar batas panjang tetap
 * ditolak 400 di kedua tahap — itu bukan klien lama, itu klien baru yang
 * mengirim data buruk, dan menerimanya diam-diam akan menyimpan potongan
 * kalimat ke riwayat darurat.
 *
 * PIN, otorisasi pemilik/pengurus, idempotensi, penguncian konkurensi, MQTT,
 * dan riwayat tidak tersentuh sama sekali oleh saklar ini.
 */

/** `true` hanya bila diisi eksplisit; bawaannya permisif (Tahap 1). */
const WAJIBKAN_KETERANGAN_DARURAT = process.env.WAJIBKAN_KETERANGAN_DARURAT === 'true';

/**
 * Penanda yang disimpan pada `emergency_alerts.message` untuk kejadian yang
 * dinyalakan klien lama tanpa keterangan.
 *
 * Bentuknya sengaja TIDAK menyerupai kalimat manusia. Menuliskan sesuatu
 * seperti "Alarm darurat dinyalakan dari dasbor" akan tampil di Riwayat
 * Darurat seolah-olah pelapor benar-benar mengetiknya — itu memalsukan
 * catatan, dan justru catatan darurat yang paling tidak boleh dipalsukan.
 *
 * Karena ia harfiah dan tetap, ia juga bisa dihitung:
 *
 *   SELECT COUNT(*) FROM emergency_alerts WHERE message = '[legacy_without_keterangan]';
 *
 * Angka itulah dasar keputusan Tahap 2 — bukan tebakan tentang siapa yang sudah
 * memperbarui aplikasinya.
 */
const PENANDA_LEGACY = '[legacy_without_keterangan]';

let _terakhirDicatatKeterangan = 0;

/**
 * Mencatat ON tanpa keterangan, dibatasi laju seperti pencatat di atas.
 *
 * Selama baris ini masih muncul, masih ada APK lama di luar sana dan Tahap 2
 * belum boleh dinyalakan.
 */
function catatDaruratTanpaKeterangan(req) {
  const sekarang = Date.now();
  if (sekarang - _terakhirDicatatKeterangan < _JEDA_CATAT_MS) return;
  _terakhirDicatatKeterangan = sekarang;
  console.warn(
    '[LEGACY] ON darurat tanpa keterangan diterima'
    + ` → pengguna ${req.user?.id ?? '?'} (${req.user?.role ?? '?'})`
    + ' — klien lama belum diperbarui; jangan setel WAJIBKAN_KETERANGAN_DARURAT=true dulu.'
  );
}

module.exports = {
  IZINKAN_TOKEN_QUERY,
  catatPemakaianTokenQuery,
  WAJIBKAN_KETERANGAN_DARURAT,
  PENANDA_LEGACY,
  catatDaruratTanpaKeterangan,
};
