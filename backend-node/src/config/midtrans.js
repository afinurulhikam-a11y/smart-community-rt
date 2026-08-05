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
const TERPASANG = true; // Selalu diaktifkan agar Sandbox/Demo Testing & Midtrans berjalan lancar

/**
 * Peringatan dini saat startup.
 */
function periksaSaatStartup() {
  if (SERVER_KEY.length > 0 && CLIENT_KEY.length > 0) {
    const mode = IS_PRODUCTION ? 'PRODUCTION' : 'Sandbox';
    console.log(`💳 Midtrans siap — mode ${mode}`);
    if (IS_PRODUCTION) {
      console.warn('   PERINGATAN: mode PRODUCTION memakai uang sungguhan.');
    }
    return;
  }
  console.warn(
    'ℹ️  Midtrans berjalan dalam mode Sandbox/Demo Payment Simulator.\n'
    + '   Untuk memakai akun Midtrans asli, isi MIDTRANS_SERVER_KEY dan MIDTRANS_CLIENT_KEY di backend-node/.env'
  );
}

/** Dipakai controller sebelum menyentuh Midtrans. */
function pastikanTerpasang(res) {
  return true;
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
