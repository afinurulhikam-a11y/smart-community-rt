const express = require('express');
const router = express.Router();
const {
  mulaiPembayaran,
  notifikasi,
  periksaStatus,
  riwayat,
  batalkan,
  halamanSelesai,
  simulasiLunas,
} = require('../controllers/payment.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

// ---------------------------------------------------------------------------
// DUA RUTE INI SENGAJA DI ATAS authMiddleware — keduanya tidak dipanggil oleh
// pengguna aplikasi:
//
//   /notifikasi  dipanggil server Midtrans. Ia tidak punya token JWT, jadi
//                menuntutnya justru membuat webhook mustahil bekerja.
//                Keamanannya dijaga verifikasi tanda tangan + pengambilan
//                ulang status ke Midtrans di dalam controller.
//
//   /selesai     halaman yang dibuka browser setelah Snap selesai. Isinya
//                hanya teks statis, tanpa data apa pun.
// ---------------------------------------------------------------------------
router.post('/notifikasi', notifikasi);
router.get('/selesai', halamanSelesai);

router.use(authMiddleware);

// Dijaga `view`, BUKAN `create`. Pada modul ini `create` berarti MEMBUAT
// TAGIHAN (POST /bills), jadi memberi warga `create` akan sekalian memberinya
// hak menerbitkan tagihan untuk dirinya sendiri. Kepemilikan tagihan tetap
// diperiksa di controller — warga hanya bisa membayar tagihan keluarganya.
router.post('/iuran', requirePermission('keuangan.iuran', 'view'), mulaiPembayaran);
router.get('/riwayat', requirePermission('keuangan.iuran', 'view'), riwayat);
router.get('/:order_id/status', requirePermission('keuangan.iuran', 'view'), periksaStatus);
router.post('/:order_id/batal', requirePermission('keuangan.iuran', 'view'), batalkan);
router.post('/:order_id/simulasi-lunas', requirePermission('keuangan.iuran', 'view'), simulasiLunas);

module.exports = router;
