const express = require('express');
const router = express.Router();
const {
  getMenuAkses,
  getMenuAksesSaya,
  updateMenuAkses,
  resetMenuAkses,
  toggleMenuAktif,
} = require('../controllers/menu_akses.controller');
const { authMiddleware, roleGuard } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Setiap pengguna boleh membaca izinnya SENDIRI — ini yang menggerakkan
// sidebar. Tidak ada informasi role lain yang terbuka di sini.
router.get('/me', getMenuAksesSaya);

// Selebihnya murni wewenang admin. Sengaja memakai roleGuard, bukan
// requirePermission: pengaturan hak akses tidak boleh bisa diberikan kepada
// role lain lewat pengaturan hak akses itu sendiri.
router.get('/', roleGuard('admin'), getMenuAkses);
router.put('/', roleGuard('admin'), updateMenuAkses);
router.post('/reset', roleGuard('admin'), resetMenuAkses);
router.put('/menu/:kode/aktif', roleGuard('admin'), toggleMenuAktif);

module.exports = router;
