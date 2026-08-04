/**
 * Konfigurasi Midtrans.
 *
 * Kunci dibaca dari .env dan diperiksa saat modul dimuat, bukan saat warga
 * menekan tombol Bayar. Kalau kuncinya belum diisi, server berhenti dengan
 * pesan yang jelas — jauh lebih baik daripada gagal misterius di tengah alur
 * pembayaran seorang warga.
 *
 * Ambil kuncinya di dashboard Midtrans: Settings → Access Keys. Pakai kunci
 * SANDBOX selama pengujian; keduanya berawalan `SB-Mid-`.
 */

const SERVER_KEY = process.env.MIDTRANS_SERVER_KEY || '';
const CLIENT_KEY = process.env.MIDTRANS_CLIENT_KEY || '';
const IS_PRODUCTION = process.env.MIDTRANS_IS_PRODUCTION === 'true';

/** Halaman yang dibuka Snap setelah pembayaran selesai. */
const FINISH_URL = process.env.MIDTRANS_FINISH_URL
  || `http://localhost:${process.env.PORT || 3001}/api/payments/selesai`;

/** True bila kunci sudah lengkap. Dipakai rute untuk menolak dengan sopan. */
const TERPASANG = SERVER_KEY.length > 0 && CLIENT_KEY.length > 0;

/**
 * Peringatan dini saat startup.
 *
 * Sengaja TIDAK melempar error: server harus tetap bisa dijalankan untuk
 * seluruh modul lain walau pembayaran belum dikonfigurasi. Yang menolak adalah
 * endpoint pembayarannya sendiri, lewat `pastikanTerpasang`.
 */
function periksaSaatStartup() {
  if (TERPASANG) {
    const mode = IS_PRODUCTION ? 'PRODUCTION' : 'Sandbox';
    console.log(`💳 Midtrans siap — mode ${mode}`);
    if (IS_PRODUCTION) {
      console.warn('   PERINGATAN: mode PRODUCTION memakai uang sungguhan.');
    }
    return;
  }
  console.warn(
    '⚠️  Midtrans belum dikonfigurasi. Endpoint /api/payments akan menolak.\n'
    + '   Isi MIDTRANS_SERVER_KEY dan MIDTRANS_CLIENT_KEY di backend-node/.env\n'
    + '   (dashboard Midtrans → Settings → Access Keys, mode Sandbox).'
  );
}

/** Dipakai controller sebelum menyentuh Midtrans. */
function pastikanTerpasang(res) {
  if (TERPASANG) return true;
  res.status(503).json({
    success: false,
    message: 'Pembayaran online belum dikonfigurasi. Hubungi Administrator.',
  });
  return false;
}

module.exports = {
  SERVER_KEY,
  CLIENT_KEY,
  IS_PRODUCTION,
  FINISH_URL,
  TERPASANG,
  periksaSaatStartup,
  pastikanTerpasang,
};
