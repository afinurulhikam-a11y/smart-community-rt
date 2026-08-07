const express = require('express');
const router = express.Router();
const {
  getTransactions,
  getSummary,
  getBulanan,
  createTransaction,
  updateTransaction,
  deleteTransaction,
  exportFinances,
} = require('../controllers/finance.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validate.middleware');
const Joi = require('joi');

const financeSchema = Joi.object({
  tipe: Joi.string().valid('pemasukan', 'pengeluaran').required(),
  jumlah: Joi.number().positive().required(),
  deskripsi: Joi.string().required(),
  kategori_id: Joi.number().integer().allow(null, ''),
  kategori: Joi.string().allow(null, ''),
  tanggal: Joi.date().iso().allow(null, '')
}).unknown(true);

router.use(authMiddleware);

// Rute statis didaftarkan lebih dulu agar tidak tertelan pola '/:id'.
router.get('/summary', requirePermission('keuangan.kas', 'view'), getSummary);
router.get('/bulanan', requirePermission('keuangan.kas', 'view'), getBulanan);
router.get('/export', requirePermission('keuangan.kas', 'view'), exportFinances);
router.get('/', requirePermission('keuangan.kas', 'view'), getTransactions);

router.post('/', requirePermission('keuangan.kas', 'create'), validate(financeSchema), createTransaction);
router.put('/:id', requirePermission('keuangan.kas', 'update'), validate(financeSchema), updateTransaction);
router.delete('/:id', requirePermission('keuangan.kas', 'delete'), deleteTransaction);

module.exports = router;
