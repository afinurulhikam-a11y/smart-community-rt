const { pool } = require('../config/database');

/**
 * Jejak audit sistem.
 *
 * `activity_logs` bersifat HANYA-TAMBAH: database menolak UPDATE dan DELETE
 * lewat trigger `trg_activity_logs_append_only` (migrasi v19). Tidak ada
 * endpoint untuk menghapusnya, dan Reset Sistem tidak menyentuhnya. Jadi apa
 * pun yang ditulis di sini bersifat permanen — tulislah yang berguna, dan
 * jangan pernah menulis kata sandi, token, atau kunci.
 *
 * ATURAN PEMANGGILAN, ketiganya penting:
 *
 *   1. Panggil SETELAH operasinya berhasil. Mencatat lebih dulu berarti log
 *      memuat kejadian yang ternyata gagal.
 *   2. Bila ada transaksi, panggil SETELAH COMMIT. Mencatat di dalam transaksi
 *      berarti catatannya ikut hilang saat ROLLBACK.
 *   3. Fungsi ini sengaja menelan galatnya sendiri, supaya kegagalan mencatat
 *      tidak pernah menggagalkan permintaan pengguna.
 */

/**
 * Jenis aktivitas.
 *
 * Layar Log Aktivitas menyaring berdasarkan nilai ini, jadi keduanya harus
 * sepakat. Menambah jenis baru berarti menambahkannya juga di
 * `log_aktivitas_screen.dart` dan `pages/pengaturan/LogAktivitas.tsx`.
 */
const TIPE = Object.freeze({
  LOGIN: 'LOGIN',
  /** Percobaan masuk yang DITOLAK — jejak pembobolan. */
  LOGIN_GAGAL: 'LOGIN_GAGAL',
  CREATE: 'CREATE',
  UPDATE: 'UPDATE',
  DELETE: 'DELETE',
  PEMBAYARAN: 'PEMBAYARAN',
  IMPORT: 'IMPORT',
  /** Perubahan hak akses atau peran — pengawasan wewenang. */
  AKSES: 'AKSES',
  /** Penghapusan massal lewat Reset Sistem. */
  RESET: 'RESET',
  /** Tombol panik dipicu atau dimatikan. */
  DARURAT: 'DARURAT',
});

/** Ambil alamat IP secara aman dari berbagai bentuk header proxy. */
function ambilIp(req) {
  if (!req) return null;
  const mentah =
    req.headers?.['cf-connecting-ip'] ||
    req.headers?.['x-real-ip'] ||
    req.headers?.['x-forwarded-for'] ||
    req.socket?.remoteAddress ||
    req.ip ||
    '127.0.0.1';
  return (typeof mentah === 'string' ? mentah.split(',')[0].trim() : '127.0.0.1')
    .replace('::ffff:', '')
    .replace('::1', '127.0.0.1');
}

async function tulis({ userId, userNama, userRole, tipe, aktivitas, ipAddress }) {
  try {
    await pool.query(
      `INSERT INTO activity_logs (user_id, user_nama, user_role, tipe, aktivitas, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [userId, userNama, userRole, tipe, aktivitas, ipAddress]
    );
  } catch (err) {
    // Ditelan dengan sengaja; tetap dicetak supaya tidak hilang diam-diam.
    console.error('LogActivity Service Error:', err.message);
  }
}

/**
 * Catat aktivitas atas nama pengguna yang sedang masuk.
 *
 * @param {Object} req       Express request — sumber identitas pelaku dan IP
 * @param {String} tipe      Salah satu nilai [TIPE]
 * @param {String} aktivitas Kalimat yang menjelaskan APA yang berubah
 */
async function logActivity(req, tipe, aktivitas) {
  await tulis({
    userId: req?.user?.id ?? null,
    userNama: req?.user ? req.user.nama || req.user.email : 'Sistem / Anonim',
    userRole: req?.user?.role || 'Sistem',
    tipe,
    aktivitas,
    ipAddress: ambilIp(req),
  });
}

/**
 * Catat kejadian yang TIDAK punya pengguna yang masuk.
 *
 * Dibutuhkan oleh dua hal yang justru paling perlu terlihat, dan keduanya tidak
 * punya `req.user`: webhook Midtrans (`POST /payments/notifikasi`) yang datang
 * dari server Midtrans tanpa JWT, dan percobaan login yang gagal.
 *
 * @param {String} tipe
 * @param {String} aktivitas
 * @param {Object} [opsi]
 * @param {Object} [opsi.req]    Untuk mengambil IP bila ada
 * @param {String} [opsi.pelaku] Nama pelaku, mis. 'Midtrans' atau email yang dicoba
 */
async function logSistem(tipe, aktivitas, opsi = {}) {
  await tulis({
    userId: null,
    userNama: opsi.pelaku || 'Sistem',
    userRole: 'Sistem',
    tipe,
    aktivitas,
    ipAddress: ambilIp(opsi.req),
  });
}

/**
 * Format nominal untuk pesan log.
 *
 * Ada di sini, bukan di tiap controller, supaya satu baris log berbunyi sama di
 * mana pun asalnya — Kas RT, BOP, atau pembayaran iuran.
 */
function rupiah(nilai) {
  const angka = Number(nilai);
  if (!Number.isFinite(angka)) return String(nilai ?? '-');
  return 'Rp ' + Math.round(angka).toLocaleString('id-ID');
}

/** Potong nilai panjang supaya satu baris log tetap terbaca. */
function ringkas(nilai, maks = 60) {
  if (nilai === null || nilai === undefined || nilai === '') return '(kosong)';
  const teks = String(nilai);
  return teks.length > maks ? teks.slice(0, maks - 1) + '…' : teks;
}

/**
 * Susun potongan "sebelum → sesudah" untuk field yang benar-benar berubah.
 *
 * Inilah yang membedakan log yang bisa membuktikan penyalahgunaan dari log yang
 * cuma mencatat bahwa sesuatu terjadi. "Mengubah data warga" tidak menolong
 * siapa pun; "peran: warga → admin" menjelaskan dirinya sendiri.
 *
 * Field yang tidak berubah sengaja dilewati — kalau semua ikut ditulis,
 * perubahan yang penting tenggelam di antara belasan nilai yang sama.
 *
 * @param {Object}   sebelum  Baris sebelum diubah
 * @param {Object}   sesudah  Baris setelah diubah
 * @param {Object}   label    Peta nama kolom → label yang dibaca manusia
 * @param {Function} [format] Pemformat nilai, mis. `rupiah` untuk kolom uang
 * @returns {String} Contoh: 'peran: warga → admin; status: aktif → nonaktif'
 */
function bandingkan(sebelum, sesudah, label, format = ringkas) {
  const bagian = [];
  for (const [kolom, namaBaca] of Object.entries(label)) {
    const a = sebelum?.[kolom];
    const b = sesudah?.[kolom];
    // Perbandingan sebagai string disengaja: Postgres mengembalikan NUMERIC
    // sebagai string, sehingga 50000 dan '50000' adalah nilai yang sama dan
    // tidak boleh dilaporkan sebagai perubahan.
    if (String(a ?? '') === String(b ?? '')) continue;
    bagian.push(`${namaBaca}: ${format(a)} → ${format(b)}`);
  }
  return bagian.join('; ');
}

module.exports = { logActivity, logSistem, rupiah, ringkas, bandingkan, TIPE };
