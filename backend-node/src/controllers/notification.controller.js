const notificationService = require('../services/notification.service');

async function registerToken(req, res) {
  try {
    const userId = req.user.id;
    const { fcm_token, device_type, device_name } = req.body;

    if (!fcm_token || typeof fcm_token !== 'string' || fcm_token.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'fcm_token wajib diisi dan harus berupa string yang valid.',
      });
    }

    const tokenRecord = await notificationService.registerFcmToken({
      userId,
      fcmToken: fcm_token.trim(),
      deviceType: device_type || 'android',
      deviceName: device_name || null,
    });

    return res.status(200).json({
      success: true,
      message: 'Token FCM berhasil didaftarkan.',
      data: {
        id: tokenRecord.id,
        device_type: tokenRecord.device_type,
        device_name: tokenRecord.device_name,
        is_active: tokenRecord.is_active,
        last_used_at: tokenRecord.last_used_at,
      },
    });
  } catch (err) {
    console.error('Register FCM Token Error:', err.message);
    return res.status(500).json({
      success: false,
      message: 'Terjadi kesalahan server saat mendaftarkan token notifikasi.',
    });
  }
}

async function unregisterToken(req, res) {
  try {
    const userId = req.user.id;
    const fcmToken = req.body?.fcm_token || req.query?.fcm_token;

    const result = await notificationService.unregisterFcmToken({
      userId,
      fcmToken: fcmToken ? String(fcmToken).trim() : null,
    });

    return res.status(200).json({
      success: true,
      message: 'Token FCM berhasil dicabut.',
      data: {
        deleted_count: result.deletedCount,
      },
    });
  } catch (err) {
    console.error('Unregister FCM Token Error:', err.message);
    return res.status(500).json({
      success: false,
      message: 'Terjadi kesalahan server saat mencabut token notifikasi.',
    });
  }
}

const { getFirebaseDiagnostic } = require('../config/firebase');
const { sendToToken, maskToken } = require('../services/fcm.service');

async function getDiagnostic(req, res) {
  try {
    const diagnostic = getFirebaseDiagnostic();
    return res.status(200).json({
      success: true,
      message: 'Status diagnostik Firebase FCM.',
      data: diagnostic,
    });
  } catch (err) {
    console.error('Get Notification Diagnostic Error:', err.message);
    return res.status(500).json({
      success: false,
      message: 'Terjadi kesalahan server saat mengambil status diagnostik notifikasi.',
    });
  }
}

/**
 * Endpoint uji coba pengiriman 1 push notification ke 1 token tertentu
 * atau ke perangkat aktif milik pengguna yang sedang terotentikasi.
 *
 * Jaminan Keamanan:
 * 1. Hanya mengizinkan single-target per request.
 * 2. User non-admin diisolasi ketat: hanya bisa mengirim ke token aktif miliknya sendiri.
 *    Token milik user lain atau token arbitrary ditolak dengan HTTP 403 Forbidden.
 * 3. Validasi ketat pada title (maks 100 karakter) dan body (maks 500 karakter).
 * 4. Token selalu dimasking pada seluruh log dan output respons.
 */
async function sendTestNotification(req, res) {
  try {
    const userId = req.user?.id;
    const userRole = req.user?.role || 'warga';
    const isAdmin = userRole === 'admin';

    const { fcm_token, title, body, data } = req.body || {};

    // 1. Validasi format & batas karakter title (jika dikirim)
    let cleanTitle = '🧪 Uji Coba Notifikasi FCM';
    if (title !== undefined && title !== null) {
      if (typeof title !== 'string' || title.trim() === '') {
        return res.status(400).json({
          success: false,
          message: 'Judul notifikasi (title) harus berupa string yang valid dan tidak boleh kosong.',
        });
      }
      if (title.trim().length > 100) {
        return res.status(400).json({
          success: false,
          message: 'Judul notifikasi (title) melebihi batas maksimum 100 karakter.',
        });
      }
      cleanTitle = title.trim();
    }

    // 2. Validasi format & batas karakter body (jika dikirim)
    let cleanBody = 'Ini adalah pesan uji coba push notification tunggal dari Smart Community RT.';
    if (body !== undefined && body !== null) {
      if (typeof body !== 'string' || body.trim() === '') {
        return res.status(400).json({
          success: false,
          message: 'Isi pesan (body) harus berupa string yang valid dan tidak boleh kosong.',
        });
      }
      if (body.trim().length > 500) {
        return res.status(400).json({
          success: false,
          message: 'Isi pesan (body) melebihi batas maksimum 500 karakter.',
        });
      }
      cleanBody = body.trim();
    }

    // 3. Resolusi & Validasi Token Target (Strict Ownership Check)
    let targetToken = null;

    if (fcm_token !== undefined && fcm_token !== null) {
      if (typeof fcm_token !== 'string' || fcm_token.trim() === '') {
        return res.status(400).json({
          success: false,
          message: 'fcm_token harus berupa string yang valid dan tidak boleh kosong.',
        });
      }
      if (fcm_token.trim().length > 500) {
        return res.status(400).json({
          success: false,
          message: 'fcm_token melebihi batas panjang maksimum (500 karakter).',
        });
      }

      const candidateToken = fcm_token.trim();

      // Untuk non-admin: wajib verifikasi kepemilikan token di user_fcm_tokens
      if (!isAdmin) {
        const isOwned = await notificationService.isTokenOwnedByUser(userId, candidateToken);
        if (!isOwned) {
          return res.status(403).json({
            success: false,
            message: 'Akses ditolak: Token FCM tidak terdaftar untuk akun Anda atau berstatus tidak aktif.',
          });
        }
      }

      targetToken = candidateToken;
    } else {
      // Jika fcm_token tidak dikirim: ambil 1 token aktif milik user yang sedang login
      const userTokens = await notificationService.getTokensByUserId(userId);
      if (userTokens.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Tidak ada token FCM aktif yang ditemukan untuk akun Anda. Silakan daftarkan token terlebih dahulu.',
        });
      }
      targetToken = userTokens[0];
    }

    // 4. Kirim notifikasi uji coba tunggal (Single Target)
    const customData = (typeof data === 'object' && data !== null && !Array.isArray(data)) ? data : {};
    const result = await sendToToken(targetToken, {
      title: cleanTitle,
      body: cleanBody,
      data: {
        type: 'test_notification',
        timestamp: new Date().toISOString(),
        ...customData,
      },
      priority: 'high',
    });

    return res.status(200).json({
      success: result.success,
      message: result.success
        ? (result.simulated ? 'Uji coba FCM diproses dalam mode simulasi (kredensial belum dipasang).' : 'Uji coba FCM berhasil dikirim ke perangkat.')
        : `Gagal mengirim FCM: ${result.error || 'Unknown error'}`,
      data: {
        simulated: result.simulated,
        messageId: result.messageId || null,
        target_masked: maskToken(targetToken),
        error: result.error || null,
      },
    });
  } catch (err) {
    console.error('Send Test Notification Error:', err.message);
    return res.status(500).json({
      success: false,
      message: 'Terjadi kesalahan server saat mengirim uji coba notifikasi.',
    });
  }
}

module.exports = {
  registerToken,
  unregisterToken,
  getDiagnostic,
  sendTestNotification,
};
