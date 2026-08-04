const express = require('express');
const router = express.Router();
const {
  getBills,
  getBillStats,
  createBill,
  generateBills,
  payBill,
  payBillsBulk,
  deleteBill,
  exportBills,
  downloadReceipt,
} = require('../controllers/bill.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Rute statis didaftarkan lebih dulu agar tidak tertelan pola '/:id'.
router.get('/stats', requirePermission('keuangan.iuran', 'view'), getBillStats);
router.get('/export', requirePermission('keuangan.iuran', 'view'), exportBills);
router.get('/', requirePermission('keuangan.iuran', 'view'), getBills);

router.post('/', requirePermission('keuangan.iuran', 'create'), createBill);
router.post('/generate', requirePermission('keuangan.iuran', 'create'), generateBills);
router.post('/pay-bulk', requirePermission('keuangan.iuran', 'create'), payBillsBulk);

// Rute ini MELUNASI tagihan seketika dan memposting pemasukan ke Kas RT, jadi
// ia untuk mencatat uang tunai/transfer yang BENAR-BENAR SUDAH DITERIMA
// pengurus — bukan untuk warga menyatakan dirinya lunas.
//
// Sebelumnya tanpa penjagaan izin sama sekali, sehingga warga bisa memanggilnya
// dan Kas RT melaporkan uang yang tidak pernah masuk. Warga kini membayar lewat
// POST /api/payments/iuran (Midtrans), dan tagihan baru lunas setelah Midtrans
// mengonfirmasi.
router.post('/:id/pay', requirePermission('keuangan.iuran', 'update'), payBill);
router.get('/:id/receipt', requirePermission('keuangan.iuran', 'view'), downloadReceipt);
router.delete('/:id', requirePermission('keuangan.iuran', 'delete'), deleteBill);

module.exports = router;
