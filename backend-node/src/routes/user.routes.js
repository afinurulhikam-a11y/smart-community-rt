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
router.get('/by-nik/:nik', getUserByNik);
// Dijaga izin, bukan hanya login. Pemeriksaan peran di dalam controller tetap
// ada dan sekarang juga memeriksa peran TARGET-nya — lihat komentar di sana.
// Guard ini lapisan keduanya, sekaligus membuat kewenangannya terlihat dan bisa
// dicabut lewat Menu & Akses seperti modul lain.
router.put('/credentials', requirePermission('kependudukan.warga', 'update'), updateUserCredentials);
router.get('/pending', getPendingUsers);
router.post('/', roleGuard('admin'), createUser);
router.put('/:id/role', roleGuard('admin'), updateUserRole);
router.put('/:id/status', roleGuard('admin'), updateUserStatus);
router.delete('/:id', roleGuard('admin'), deleteUser);

module.exports = router;
