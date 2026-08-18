/**
 * Notification Dispatcher Terpusat (src/services/notification.dispatcher.js)
 *
 * Mengabstraksikan resolusi target penerima (Users, Roles, Broadcast Seluruh Warga Aktif)
 * dan eksekusi non-blocking yang aman, mendelegasikan pengiriman dan sanitasi token ke fcm.service.js.
 */
const { pool } = require('../config/database');
const fcmService = require('./fcm.service');

// Daftar peran pengguna yang diakui sistem database existing
const PERAN_PENGURUS = ['admin', 'ketua_rt', 'sekretaris', 'bendahara', 'pengurus_rt'];
const PERAN_WARGA = ['warga'];
const PERAN_VALID = [...PERAN_PENGURUS, ...PERAN_WARGA];

/**
 * Mengirim push notifikasi ke satu pengguna spesifik (UUID).
 */
async function sendToUser(userId, payload = {}) {
  if (!userId) {
    return { skipped: true, reason: 'missing_user_id', tokensCount: 0, successCount: 0, failureCount: 0 };
  }
  return fcmService.sendToUser(userId, payload);
}

/**
 * Mengirim push notifikasi ke sekumpulan pengguna spesifik (Array of UUIDs).
 */
async function sendToUsers(userIds, payload = {}) {
  if (!Array.isArray(userIds) || userIds.length === 0) {
    return { skipped: true, reason: 'empty_user_ids', tokensCount: 0, successCount: 0, failureCount: 0 };
  }
  return fcmService.sendToUsers(userIds, payload);
}

/**
 * Mengirim push notifikasi ke seluruh pengguna aktif berdasarkan daftar role (mis. Pengurus RT).
 */
async function sendToRoles(roles = [], payload = {}) {
  const roleArray = Array.isArray(roles) ? roles : [roles];
  if (roleArray.length === 0) {
    return { skipped: true, reason: 'empty_roles', tokensCount: 0, successCount: 0, failureCount: 0 };
  }

  const userRows = await pool.query(
    `SELECT id FROM users WHERE is_active = true AND role = ANY($1::varchar[])`,
    [roleArray]
  );
  const userIds = userRows.rows.map((r) => r.id);

  if (userIds.length === 0) {
    return { skipped: true, reason: 'no_active_users_for_roles', tokensCount: 0, successCount: 0, failureCount: 0 };
  }

  return fcmService.sendToUsers(userIds, payload);
}

/**
 * Mengirim push notifikasi ke seluruh pengguna yang berstatus aktif di RT (Broadcast).
 */
async function sendToAllActive(payload = {}) {
  const userRows = await pool.query(
    `SELECT id FROM users WHERE is_active = true`
  );
  const userIds = userRows.rows.map((r) => r.id);

  if (userIds.length === 0) {
    return { skipped: true, reason: 'no_active_users', tokensCount: 0, successCount: 0, failureCount: 0 };
  }

  return fcmService.sendToUsers(userIds, payload);
}

/**
 * Helper eksekusi non-blocking yang aman menggunakan setImmediate,
 * mengisolasi error sehingga kegagalan FCM tidak pernah mengganggu alur bisnis utama.
 */
function dispatchAsync(asyncFn, contextName = 'Notification') {
  if (typeof asyncFn !== 'function') return;
  setImmediate(() => {
    try {
      const promise = asyncFn();
      if (promise && typeof promise.catch === 'function') {
        promise.catch((err) => {
          console.error(`⚠️ [FCM Dispatcher: ${contextName}] Non-blocking dispatch error:`, err?.message || err);
        });
      }
    } catch (err) {
      console.error(`⚠️ [FCM Dispatcher: ${contextName}] Synchronous dispatch error:`, err?.message || err);
    }
  });
}

module.exports = {
  sendToUser,
  sendToUsers,
  sendToRoles,
  sendToAllActive,
  dispatchAsync,
  PERAN_PENGURUS,
  PERAN_WARGA,
  PERAN_VALID,
};
