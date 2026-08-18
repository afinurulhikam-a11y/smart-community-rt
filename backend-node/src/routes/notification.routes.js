const express = require('express');
const router = express.Router();
const { registerToken, unregisterToken } = require('../controllers/notification.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

// Seluruh rute notifikasi wajib terotentikasi via JWT
router.use(authMiddleware);

// Registrasi / update token FCM perangkat
router.post('/fcm-token', registerToken);

// Pencabutan / unregister token FCM perangkat (misal saat logout)
router.delete('/fcm-token', unregisterToken);

module.exports = router;
