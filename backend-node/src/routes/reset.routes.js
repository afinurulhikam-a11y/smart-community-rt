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
const { IZINKAN_TOKEN_QUERY } = require('../config/kompatibilitas');

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

router.post('/cadangan', cadanganReset);

// Versi GET dipertahankan SEMENTARA untuk klien lama, dan hanya itu.
//
// Ia hanya berguna lewat `?token=` — sebuah navigasi browser tidak bisa membawa
// header — jadi umurnya terikat pada saklar yang sama. Begitu
// IZINKAN_TOKEN_QUERY=false, rutenya tidak didaftarkan sama sekali: lebih jujur
// daripada meninggalkan rute yang selalu menjawab 401 dan menyisakan kesan
// bahwa jalurnya masih ada.
//
// Ini URL yang paling tidak boleh tercatat di log — ia menstreamkan dump mentah
// seluruh tabel dalam satu grup reset, data warga termasuk. Karena itu ia yang
// pertama harus ditinggalkan begitu klien baru terverifikasi.
//
// Penggantinya sudah jalan: tiket sekali pakai `jenis: 'reset.cadangan'` di
// src/config/jenis-unduh.js, dengan roleGuard('admin') yang sama — diperiksa
// dua kali, saat tiket dibuat dan saat ditukar.
if (IZINKAN_TOKEN_QUERY) {
  router.get('/cadangan', cadanganReset);
}

router.post('/eksekusi', eksekusiReset);

module.exports = router;
