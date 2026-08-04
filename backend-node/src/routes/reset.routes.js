const express = require('express');
const router = express.Router();
const {
  getRingkasan,
  pratinjauReset,
  cadanganReset,
  eksekusiReset,
  getRiwayatReset,
} = require('../controllers/reset.controller');
const { authMiddleware, roleGuard } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Seluruh rute memakai roleGuard('admin'), bukan requirePermission, dengan
// alasan yang sama seperti menu_akses.routes.js: wewenang menghapus data
// sistem tidak boleh bisa diberikan kepada role lain lewat layar pengaturan.
//
// Menu 'pengaturan.reset' memang sudah ditandai is_sistem sehingga
// requirePermission pun akan menolak non-admin, tetapi roleGuard tidak
// bergantung pada isi tabel izin sama sekali — dan justru penjagaan reset yang
// paling tidak boleh bergantung pada data yang bisa direset.
router.use(roleGuard('admin'));

router.get('/ringkasan', getRingkasan);
router.get('/riwayat', getRiwayatReset);
router.post('/pratinjau', pratinjauReset);

// Cadangan tersedia sebagai GET dan POST. Versi GET dipakai layar lewat
// launchUrl dengan token di query — pola unduhan yang sudah dipakai seluruh
// tombol export lain di aplikasi ini, dan authMiddleware memang menerimanya.
router.get('/cadangan', cadanganReset);
router.post('/cadangan', cadanganReset);

router.post('/eksekusi', eksekusiReset);

module.exports = router;
