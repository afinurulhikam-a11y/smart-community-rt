const { pool } = require('../config/database');

/**
 * Service pengelola registry token FCM perangkat pengguna.
 *
 * ===================================================================
 * Desain Relasi Identitas & Multi-Device
 * ===================================================================
 *
 * 1. `userId` selalu berupa UUID v4 dari `req.user.id` yang telah divalidasi
 *    oleh JWT authMiddleware. Klien TIDAK mengirim userId dalam payload.
 * 2. Token FCM bersifat unik per instalasi aplikasi di perangkat.
 *    Menggunakan UPSERT: bila perangkat berpindah kepemilikan akun (login user lain),
 *    token akan diasosiasikan ulang ke `user_id` yang baru.
 * 3. Saat logout, token perangkat tersebut dihapus atau dinonaktifkan agar
 *    tidak menerima push notification milik pengguna sebelumnya.
 */

async function registerFcmToken({ userId, fcmToken, deviceType = 'android', deviceName = null }) {
  if (!userId || !fcmToken) {
    throw new Error('userId dan fcmToken wajib diisi.');
  }

  const cleanToken = String(fcmToken).trim();
  const cleanType = String(deviceType || 'android').trim().toLowerCase();
  const cleanDevice = deviceName ? String(deviceName).trim().slice(0, 100) : null;

  const result = await pool.query(
    `INSERT INTO public.user_fcm_tokens (
       user_id, fcm_token, device_type, device_name, is_active, last_used_at, updated_at
     )
     VALUES ($1, $2, $3, $4, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     ON CONFLICT (fcm_token) DO UPDATE SET
       user_id = EXCLUDED.user_id,
       device_type = COALESCE(EXCLUDED.device_type, user_fcm_tokens.device_type),
       device_name = COALESCE(EXCLUDED.device_name, user_fcm_tokens.device_name),
       is_active = true,
       last_used_at = CURRENT_TIMESTAMP,
       updated_at = CURRENT_TIMESTAMP
     RETURNING id, user_id, fcm_token, device_type, device_name, is_active, last_used_at, created_at, updated_at`,
    [userId, cleanToken, cleanType, cleanDevice]
  );

  return result.rows[0];
}

async function unregisterFcmToken({ userId, fcmToken }) {
  if (!userId) {
    throw new Error('userId wajib diisi.');
  }

  if (fcmToken) {
    const cleanToken = String(fcmToken).trim();
    const result = await pool.query(
      `DELETE FROM public.user_fcm_tokens
       WHERE fcm_token = $1 AND user_id = $2
       RETURNING id, fcm_token, user_id`,
      [cleanToken, userId]
    );
    return {
      deletedCount: result.rowCount,
      tokens: result.rows,
    };
  }

  // Jika token tidak disertakan, nonaktifkan seluruh token milik user tersebut
  const result = await pool.query(
    `UPDATE public.user_fcm_tokens
     SET is_active = false, updated_at = CURRENT_TIMESTAMP
     WHERE user_id = $1
     RETURNING id, fcm_token, is_active`,
    [userId]
  );

  return {
    deletedCount: result.rowCount,
    tokens: result.rows,
  };
}

async function getTokensByUserId(userId) {
  if (!userId) return [];
  const result = await pool.query(
    `SELECT fcm_token, device_type, device_name
     FROM public.user_fcm_tokens
     WHERE user_id = $1 AND is_active = true`,
    [userId]
  );
  return result.rows.map((r) => r.fcm_token);
}

async function isTokenOwnedByUser(userId, fcmToken) {
  if (!userId || !fcmToken) return false;
  const cleanToken = String(fcmToken).trim();
  const result = await pool.query(
    `SELECT 1 FROM public.user_fcm_tokens
     WHERE user_id = $1 AND fcm_token = $2 AND is_active = true
     LIMIT 1`,
    [userId, cleanToken]
  );
  return result.rowCount > 0;
}

const fcmService = require('./fcm.service');

module.exports = {
  registerFcmToken,
  unregisterFcmToken,
  getTokensByUserId,
  isTokenOwnedByUser,
  sendToToken: fcmService.sendToToken,
  sendToTokens: fcmService.sendToTokens,
  sendToUser: fcmService.sendToUser,
  sendToUsers: fcmService.sendToUsers,
};
