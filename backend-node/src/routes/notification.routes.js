const express = require('express');
const router = express.Router();
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { registerToken, unregisterToken, getDiagnostic, sendTestNotification } = require('../controllers/notification.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

/**
 * Pembatas laju untuk endpoint uji coba test-send: 5 permintaan per menit.
 *
 * ===================================================================
 * Kenapa alamat IP tidak boleh dipakai apa adanya
 * ===================================================================
 *
 * `req.ip` yang disambung langsung menjadi kunci bekerja benar untuk IPv4,
 * tempat satu pelanggan biasanya berarti satu alamat. Pada IPv6 tidak:
 * penyedia layanan memberikan satu BLOK — lazimnya /56 atau /64 — kepada satu
 * pelanggan, dan pemiliknya bebas berganti alamat di dalam blok itu sesukanya.
 *
 * Artinya `2001:db8::1` dan `2001:db8::dead` menghasilkan dua kunci berbeda
 * padahal orangnya sama, sehingga batas 5 per menit bisa dilewati sebanyak
 * jumlah alamat di dalam bloknya — praktis tak terbatas. Pembatas yang
 * terlihat ada dan tidak membatasi apa pun.
 *
 * `ipKeyGenerator()` menormalkan alamatnya ke blok itu lebih dulu, sehingga
 * seluruh blok berbagi satu kunci. express-rate-limit v7 ke atas memeriksa
 * hal ini dan mengeluh ERR_ERL_KEY_GEN_IPV6 bila dilewati.
 *
 * Pemakai yang sudah login tetap dibatasi per AKUN, bukan per alamat — itu
 * yang benar di sini, karena rutenya sendiri sudah di balik authMiddleware
 * dan satu orang tidak boleh mendapat jatah lebih hanya karena berpindah
 * jaringan. Cabang IP hanyalah cadangan bila `req.user` entah bagaimana
 * kosong.
 */
const testSendLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req, res) => (
    req.user?.id ? `user:${req.user.id}` : ipKeyGenerator(req.ip || '', res)
  ),
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
