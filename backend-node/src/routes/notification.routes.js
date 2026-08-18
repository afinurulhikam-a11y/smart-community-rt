const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');
const { registerToken, unregisterToken, getDiagnostic, sendTestNotification } = require('../controllers/notification.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

// Rate limiter khusus untuk endpoint uji coba test-send: maks 5 request per menit per user/IP
const testSendLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    return req.user?.id ? `user:${req.user.id}` : (req.ip || 'unknown');
  },
  message: {
    success: false,
    message: 'Terlalu banyak permintaan uji coba notifikasi. Silakan tunggu 1 menit sebelum mencoba kembali.',
  },
});

// Seluruh rute notifikasi wajib terotentikasi via JWT
router.use(authMiddleware);

// Status diagnostik FCM readiness
router.get('/status', getDiagnostic);
router.get('/diagnostic', getDiagnostic);

// Endpoint uji coba kirim 1 notifikasi ke 1 token/perangkat (dilindungi rate limiter & auth)
router.post('/test-send', testSendLimiter, sendTestNotification);

// Registrasi / update token FCM perangkat
router.post('/fcm-token', registerToken);

// Pencabutan / unregister token FCM perangkat (misal saat logout)
router.delete('/fcm-token', unregisterToken);

module.exports = router;
