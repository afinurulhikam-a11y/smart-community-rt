const express = require('express');
const router = express.Router();
const {
  getJenisIuran,
  createJenisIuran,
  updateJenisIuran,
  deleteJenisIuran,
} = require('../controllers/jenis_iuran.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Dibaca semua role: warga perlu melihat nama jenis iuran pada tagihannya.
router.get('/', requirePermission('keuangan.iuran', 'view'), getJenisIuran);

router.post('/', requirePermission('keuangan.iuran', 'create'), createJenisIuran);
router.put('/:id', requirePermission('keuangan.iuran', 'update'), updateJenisIuran);
router.delete('/:id', requirePermission('keuangan.iuran', 'delete'), deleteJenisIuran);

module.exports = router;
