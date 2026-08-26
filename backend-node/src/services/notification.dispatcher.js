/**
 * Notification Dispatcher Terpusat (src/services/notification.dispatcher.js)
 *
 * Mengabstraksikan resolusi target penerima (Users, Roles, Broadcast Seluruh Warga Aktif)
 * dan eksekusi non-blocking yang aman, mendelegasikan pengiriman dan sanitasi token ke fcm.service.js.
 */
const { pool } = require('../config/database');
const fcmService = require('./fcm.service');
const { PERAN_LINTAS_RT } = require('../utils/lingkup-rt');

/**
 * ===================================================================
 * Kenapa penerima notifikasi harus dilingkupi per RT
 * ===================================================================
 *
 * Pemilihan penerima di berkas ini hanya melihat `role` dan `is_active`.
 * Sejak satu pemasangan melayani beberapa RT, itu berarti setiap pengaduan
 * baru di RT 002 mengirim notifikasi — lengkap dengan nama pelapor dan judul
 * pengaduannya — ke seluruh pengurus se-RW.
 *
 * Yang paling membingungkan bukan kebocorannya melainkan akibat lanjutannya:
 * pengumuman RT 001 memunculkan notifikasi di ponsel warga RT 002, lalu
 * ketika dibuka TIDAK ADA APA-APA, karena daftarnya sendiri sudah tersaring
 * per RT dengan benar. Notifikasi yang menunjuk ke ruang kosong lebih buruk
 * daripada tidak ada notifikasi.
 *
 * `rtId` bersifat opsional: dibiarkan kosong berarti seluruh RW, yaitu
 * perilaku sebelum ada modul RT. Jadi jalur yang belum disesuaikan tidak
 * mendadak berhenti mengirim — ia hanya belum menyempit.
 *
 * ===================================================================
 * Kenapa peran lintas RT selalu ikut
 * ===================================================================
 *
 * Administrator dan ketua RW melihat SELURUH RW di dalam aplikasi. Menyaring
 * notifikasi mereka menurut `users.rt_id` — yang bagi mereka hanyalah RT
 * tempat akunnya kebetulan terdaftar — akan membuat mereka berhenti diberi
 * tahu tentang sebagian besar hal yang justru menjadi tanggung jawab mereka.
 * Notifikasi harus sejalan dengan apa yang bisa dibuka orangnya.
 */
const SARING_RT = `AND ($RT::uuid IS NULL OR rt_id = $RT::uuid OR role = ANY($LINTAS::varchar[]))`;

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
async function sendToRoles(roles = [], payload = {}, { rtId = null } = {}) {
  const roleArray = Array.isArray(roles) ? roles : [roles];
  if (roleArray.length === 0) {
    return { skipped: true, reason: 'empty_roles', tokensCount: 0, successCount: 0, failureCount: 0 };
  }

  const userRows = await pool.query(
    `SELECT id FROM users
      WHERE is_active = true
        AND role = ANY($1::varchar[])
        ${SARING_RT.split('$RT').join('$2').split('$LINTAS').join('$3')}`,
    [roleArray, rtId, PERAN_LINTAS_RT]
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
async function sendToAllActive(payload = {}, { rtId = null } = {}) {
  const userRows = await pool.query(
    `SELECT id FROM users
      WHERE is_active = true
        ${SARING_RT.split('$RT').join('$1').split('$LINTAS').join('$2')}`,
    [rtId, PERAN_LINTAS_RT]
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
