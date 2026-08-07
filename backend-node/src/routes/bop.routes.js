const express = require('express');
const router = express.Router();
const {
  getTransactions,
  getSummary,
  getBulanan,
  createTransaction,
  updateTransaction,
  deleteTransaction,
  exportBop,
} = require('../controllers/bop.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Rute statis didaftarkan lebih dulu agar tidak tertelan pola '/:id'.
router.get('/summary', requirePermission('keuangan.bop', 'view'), getSummary);
router.get('/bulanan', requirePermission('keuangan.bop', 'view'), getBulanan);
router.get('/export', requirePermission('keuangan.bop', 'view'), exportBop);
router.get('/', requirePermission('keuangan.bop', 'view'), getTransactions);

router.post('/', requirePermission('keuangan.bop', 'create'), createTransaction);
router.put('/:id', requirePermission('keuangan.bop', 'update'), updateTransaction);
router.delete('/:id', requirePermission('keuangan.bop', 'delete'), deleteTransaction);

module.exports = router;
