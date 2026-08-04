const express = require('express');
const router = express.Router();
const {
  getKategoriBop,
  createKategoriBop,
  updateKategoriBop,
  deleteKategoriBop,
} = require('../controllers/kategori_bop.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('keuangan.bop', 'view'), getKategoriBop);
router.post('/', requirePermission('keuangan.bop', 'create'), createKategoriBop);
router.put('/:id', requirePermission('keuangan.bop', 'update'), updateKategoriBop);
router.delete('/:id', requirePermission('keuangan.bop', 'delete'), deleteKategoriBop);

module.exports = router;
