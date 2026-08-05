const crypto = require('crypto');
const midtransClient = require('midtrans-client');
const { SERVER_KEY, CLIENT_KEY, IS_PRODUCTION, FINISH_URL } = require('../config/midtrans');

/**
 * Pembungkus SDK Midtrans.
 *
 * Controller tidak pernah menyentuh SDK langsung, sehingga seluruh urusan
 * Midtrans — nama field, aturan tanda tangan, perbedaan sandbox/production —
 * terkumpul di satu berkas.
 */

const snap = new midtransClient.Snap({
  isProduction: IS_PRODUCTION,
  serverKey: SERVER_KEY,
  clientKey: CLIENT_KEY,
});

const core = new midtransClient.CoreApi({
  isProduction: IS_PRODUCTION,
  serverKey: SERVER_KEY,
  clientKey: CLIENT_KEY,
});

/**
 * Buat transaksi Snap dan kembalikan token beserta URL pembayarannya.
 *
 * `grossAmount` WAJIB bilangan bulat rupiah — Midtrans menolak pecahan, dan
 * nominal iuran di database bertipe NUMERIC yang bisa membawa desimal.
 */
function formatEmailValid(email) {
  if (!email || typeof email !== 'string') return null;
  const cleaned = email.trim();
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(cleaned) ? cleaned : null;
}

function formatPhoneValid(phone) {
  if (!phone || typeof phone !== 'string') return undefined;
  const digits = phone.replace(/\D/g, '');
  return digits.length >= 8 && digits.length <= 15 ? digits : undefined;
}

async function buatSnap({ orderId, grossAmount, pelanggan, rincian }) {
  const validEmail = formatEmailValid(pelanggan.email) || 'warga@smart-community.id';
  const validPhone = formatPhoneValid(pelanggan.no_hp);

  const parameter = {
    transaction_details: {
      order_id: orderId,
      gross_amount: Math.round(Number(grossAmount)),
    },
    expiry: {
      unit: 'minute',
      duration: 15,
    },
    item_details: rincian.map((r) => ({
      id: String(r.id),
      name: String(r.nama).slice(0, 50),
      price: Math.round(Number(r.harga)),
      quantity: 1,
    })),
    customer_details: {
      first_name: String(pelanggan.nama || 'Warga').slice(0, 50),
      email: validEmail,
      phone: validPhone,
    },
    callbacks: { finish: FINISH_URL },
  };

  const hasil = await snap.createTransaction(parameter);
  return { token: hasil.token, redirect_url: hasil.redirect_url };
}

/**
 * Tanyakan status resmi sebuah order langsung ke Midtrans.
 *
 * Inilah satu-satunya sumber kebenaran status pembayaran. Isi notifikasi
 * webhook TIDAK PERNAH dipercaya apa adanya — selalu dicocokkan ke sini.
 */
async function ambilStatus(orderId) {
  return core.transaction.status(orderId);
}

/**
 * Verifikasi tanda tangan notifikasi Midtrans.
 *
 *   signature_key = sha512(order_id + status_code + gross_amount + server_key)
 *
 * Tanpa pemeriksaan ini, siapa pun yang tahu alamat webhook bisa mengirim
 * "settlement" palsu dan melunasi tagihan tanpa membayar.
 */
function verifikasiTandaTangan({ order_id, status_code, gross_amount, signature_key }) {
  if (!order_id || !status_code || !gross_amount || !signature_key) return false;

  const dihitung = crypto
    .createHash('sha512')
    .update(`${order_id}${status_code}${gross_amount}${SERVER_KEY}`)
    .digest('hex');

  // timingSafeEqual menuntut panjang yang sama, jadi diperiksa lebih dulu.
  const a = Buffer.from(dihitung, 'utf8');
  const b = Buffer.from(String(signature_key), 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Terjemahkan status Midtrans menjadi status internal.
 *
 *   lunas   — uang diterima, tagihan boleh dilunasi
 *   pending — masih ditunggu, termasuk kartu yang sedang ditinjau (challenge)
 *   gagal   — batal/ditolak/kedaluwarsa, tagihan kembali bisa dibayar
 */
function terjemahkanStatus(data) {
  const status = data.transaction_status;
  const fraud = data.fraud_status;

  if (status === 'settlement') return 'lunas';
  if (status === 'capture') return fraud === 'accept' ? 'lunas' : 'pending';
  if (status === 'pending') return 'pending';
  if (['deny', 'cancel', 'expire', 'failure'].includes(status)) return 'gagal';

  // Status yang tidak dikenal diperlakukan sebagai belum selesai — lebih aman
  // menahan tagihan daripada melunasinya karena tebakan.
  return 'pending';
}

module.exports = {
  buatSnap,
  ambilStatus,
  verifikasiTandaTangan,
  terjemahkanStatus,
};
