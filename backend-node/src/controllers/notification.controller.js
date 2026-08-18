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

module.exports = {
  registerToken,
  unregisterToken,
  getDiagnostic,
};
