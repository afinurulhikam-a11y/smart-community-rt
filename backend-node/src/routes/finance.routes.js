const express = require('express');
const router = express.Router();
const {
  getTransactions,
  getSummary,
  createTransaction,
  updateTransaction,
  deleteTransaction,
  exportFinances,
} = require('../controllers/finance.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Rute statis didaftarkan lebih dulu agar tidak tertelan pola '/:id'.
router.get('/summary', requirePermission('keuangan.kas', 'view'), getSummary);
router.get('/export', requirePermission('keuangan.kas', 'view'), exportFinances);
router.get('/', requirePermission('keuangan.kas', 'view'), getTransactions);

router.post('/', requirePermission('keuangan.kas', 'create'), createTransaction);
router.put('/:id', requirePermission('keuangan.kas', 'update'), updateTransaction);
router.delete('/:id', requirePermission('keuangan.kas', 'delete'), deleteTransaction);

module.exports = router;
