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

// Hanya POST. Versi GET dulu ada supaya layar bisa memanggilnya lewat
// launchUrl dengan token di query — dan justru inilah URL yang paling tidak
// boleh tercatat di log: ia menstreamkan dump mentah seluruh tabel dalam satu
// grup reset, data warga termasuk.
//
// Unduhannya sekarang lewat tiket sekali pakai (`jenis: 'reset.cadangan'` di
// src/config/jenis-unduh.js), yang menjalankan roleGuard('admin') yang sama —
// dua kali, saat tiket dibuat dan saat ditukar.
router.post('/cadangan', cadanganReset);

router.post('/eksekusi', eksekusiReset);

module.exports = router;
