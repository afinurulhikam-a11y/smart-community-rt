const express = require('express');
const router = express.Router();
const {
  getUsers,
  updateUserRole,
  updateUserStatus,
  createUser,
  getPendingUsers,
  deleteUser,
  getUserByNik,
  updateUserCredentials,
} = require('../controllers/user.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('kependudukan.warga', 'view'), getUsers);
// Mengembalikan no_hp, no_kk, peran, dan status — bahkan untuk orang yang belum
// punya akun, karena ia jatuh ke anggota_keluarga bila tidak ketemu di users.
// Tanpa guard ini, warga mana pun bisa menelusuri data tetangganya satu per
// satu. Digabung dengan sandi bawaan akun warga, itu rantai pengambilalihan
// akun yang lengkap.
router.get('/by-nik/:nik', requirePermission('kependudukan.warga', 'view'), getUserByNik);
// Dijaga izin, bukan hanya login. Pemeriksaan peran di dalam controller tetap
// ada dan sekarang juga memeriksa peran TARGET-nya — lihat komentar di sana.
// Guard ini lapisan keduanya, sekaligus membuat kewenangannya terlihat dan bisa
// dicabut lewat Menu & Akses seperti modul lain.
router.put('/credentials', requirePermission('kependudukan.warga', 'update'), updateUserCredentials);
// Mengembalikan no_hp, no_kk, dan alamat setiap pendaftar yang menunggu
// persetujuan. Itu daftar data pribadi, bukan informasi umum.
router.get('/pending', requirePermission('kependudukan.warga', 'view'), getPendingUsers);
router.post('/', roleGuard('admin'), createUser);
router.put('/:id/role', roleGuard('admin'), updateUserRole);
router.put('/:id/status', roleGuard('admin'), updateUserStatus);
router.delete('/:id', roleGuard('admin'), deleteUser);

module.exports = router;
