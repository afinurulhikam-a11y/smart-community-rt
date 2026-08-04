const express = require('express');
const router = express.Router();
const {
  getKategoriKas,
  createKategoriKas,
  updateKategoriKas,
  deleteKategoriKas,
} = require('../controllers/kategori_kas.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Dibaca semua role: warga melihat nama kategori pada laporan keuangan.
router.get('/', requirePermission('keuangan.kas', 'view'), getKategoriKas);

router.post('/', requirePermission('keuangan.kas', 'create'), createKategoriKas);
router.put('/:id', requirePermission('keuangan.kas', 'update'), updateKategoriKas);
router.delete('/:id', requirePermission('keuangan.kas', 'delete'), deleteKategoriKas);

module.exports = router;
