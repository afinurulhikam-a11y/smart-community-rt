const express = require('express');
const router = express.Router();
const {
  mulaiPembayaran,
  notifikasi,
  periksaStatus,
  riwayat,
  batalkan,
  halamanSelesai,
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

// ---------------------------------------------------------------------------
// `POST /:order_id/simulasi-lunas` DIHAPUS. Jangan dikembalikan.
//
// Rute itu menyusun payload `settlement` PALSU di dalam server ini sendiri lalu
// menyuapkannya ke terapkanStatus() — tanpa pernah memanggil ambilStatus() ke
// Midtrans, tanpa verifikasi tanda tangan, dan tanpa memeriksa kepemilikan
// order. Padahal keempat penjaga uang modul ini bertumpu pada satu aturan:
// tagihan TIDAK PERNAH dilunasi berdasarkan apa yang dikirim aplikasi.
//
// Izinnya `keuangan.iuran:view`, yang dimiliki SETIAP warga. Jadi warga mana
// pun bisa membuat order lalu melunasinya sendiri tanpa membayar sepeser pun,
// dan catatKeKasRt() memposting uang yang tidak pernah masuk ke Kas RT. Di
// laporan, hasilnya tidak bisa dibedakan dari pembayaran asli.
//
// Untuk mendemokan pembayaran tanpa uang sungguhan, pakai simulator bawaan
// Midtrans Sandbox — di sana statusnya tetap datang dari server Midtrans, jadi
// seluruh rantai verifikasi tetap berjalan sebagaimana mestinya.
// ---------------------------------------------------------------------------

module.exports = router;
