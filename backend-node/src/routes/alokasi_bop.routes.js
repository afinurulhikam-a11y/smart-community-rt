const express = require('express');
const router = express.Router();
const {
  getAlokasiBop,
  createAlokasiBop,
  updateAlokasiBop,
  deleteAlokasiBop,
} = require('../controllers/alokasi_bop.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Dibaca semua role: pagu dan realisasinya bagian dari transparansi ke warga.
router.get('/', requirePermission('keuangan.bop', 'view'), getAlokasiBop);

router.post('/', requirePermission('keuangan.bop', 'create'), createAlokasiBop);
router.put('/:id', requirePermission('keuangan.bop', 'update'), updateAlokasiBop);
router.delete('/:id', requirePermission('keuangan.bop', 'delete'), deleteAlokasiBop);

module.exports = router;
