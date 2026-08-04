const { pool } = require('../config/database');

/**
 * Catat aktivitas pengguna ke dalam tabel activity_logs secara otomatis.
 * @param {Object} req - Express request object (untuk ekstraksi user & IP)
 * @param {String} tipe - Tipe aktivitas: 'LOGIN', 'CREATE', 'UPDATE', 'DELETE'
 * @param {String} aktivitas - Deskripsi rinci kegiatan
 */
async function logActivity(req, tipe, aktivitas) {
  try {
    const userId = req.user ? req.user.id : null;
    const userNama = req.user ? (req.user.nama || req.user.email) : 'Sistem / Anonim';
    const userRole = req.user ? (req.user.role || 'User') : 'Sistem';

    // Ekstraksi IP Address secara aman
    const rawIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || req.ip || '127.0.0.1';
    const ipAddress = (typeof rawIp === 'string' ? rawIp.split(',')[0].trim() : '127.0.0.1')
      .replace('::ffff:', '')
      .replace('::1', '127.0.0.1');

    await pool.query(
      `INSERT INTO activity_logs (user_id, user_nama, user_role, tipe, aktivitas, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [userId, userNama, userRole, tipe, aktivitas, ipAddress]
    );
  } catch (err) {
    console.error('LogActivity Service Error:', err.message);
  }
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

module.exports = { logActivity, rupiah };
