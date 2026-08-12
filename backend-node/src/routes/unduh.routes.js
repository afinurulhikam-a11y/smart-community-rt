const express = require('express');
const router = express.Router();
const { buatTiket, tukarTiket } = require('../controllers/unduh.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

// Penukaran tiket WAJIB berada di atas `router.use(authMiddleware)`.
//
// Seluruh alasan mekanisme ini ada adalah karena sebuah navigasi browser tidak
// bisa membawa header `Authorization` — jadi menuntut token di sini membuat
// jalurnya mustahil. Pola yang sama dipakai `POST /payments/notifikasi`, yang
// juga datang tanpa JWT.
//
// Yang menggantikan middleware bukan kelonggaran: satu UPDATE atomik yang
// memeriksa sekali-pakai, umur, akun terhapus, akun nonaktif, dan pencabutan
// sesi sekaligus — lalu izin modulnya diperiksa ulang sesudah itu.
router.get('/:tiket', tukarTiket);

// Penerbitan tiket, sebaliknya, adalah permintaan biasa dari aplikasi dan
// menuntut sesi yang sah seperti endpoint lain.
router.use(authMiddleware);

router.post('/tiket', buatTiket);

module.exports = router;
