const express = require('express');
const router = express.Router();
const {
  getInventory,
  getInventoryStats,
  getInventoryDetail,
  createInventory,
  updateInventory,
  deleteInventory,
  exportInventory,
  getBorrowings,
  getBorrowingStats,
  getBarangTersedia,
  createBorrowing,
  updateBorrowing,
  returnBorrowing,
  deleteBorrowing,
  exportBorrowings,
} = require('../controllers/inventory.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// ---------------------------------------------------------------------------
// URUTAN PENTING: seluruh rute '/borrowings' dan rute statis lain harus
// didaftarkan SEBELUM pola '/:id'. Kalau tidak, GET /borrowings akan ditangkap
// oleh GET /:id dan dibaca sebagai barang dengan id "borrowings".
// ---------------------------------------------------------------------------
router.get('/borrowings/stats', requirePermission('inventaris.peminjaman', 'view'), getBorrowingStats);
router.get('/borrowings/export', requirePermission('inventaris.peminjaman', 'view'), exportBorrowings);
router.get('/borrowings', requirePermission('inventaris.peminjaman', 'view'), getBorrowings);
// Pilihan barang untuk form ajukan pinjam. Dijaga izin PEMINJAMAN, bukan
// barang, supaya warga bisa memilih barang tanpa diberi akses ke inventaris.
router.get('/borrowings/barang-tersedia', requirePermission('inventaris.peminjaman', 'view'), getBarangTersedia);
router.post('/borrowings', requirePermission('inventaris.peminjaman', 'create'), createBorrowing);
router.put('/borrowings/:id/return', requirePermission('inventaris.peminjaman', 'update'), returnBorrowing);
router.put('/borrowings/:id', requirePermission('inventaris.peminjaman', 'update'), updateBorrowing);
router.delete('/borrowings/:id', requirePermission('inventaris.peminjaman', 'delete'), deleteBorrowing);

// Rute statis inventaris, juga sebelum '/:id'.
router.get('/stats', requirePermission('inventaris.barang', 'view'), getInventoryStats);
router.get('/export', requirePermission('inventaris.barang', 'view'), exportInventory);
router.get('/', requirePermission('inventaris.barang', 'view'), getInventory);

router.post('/', requirePermission('inventaris.barang', 'create'), createInventory);
router.get('/:id', requirePermission('inventaris.barang', 'view'), getInventoryDetail);
router.put('/:id', requirePermission('inventaris.barang', 'update'), updateInventory);
// Sebelumnya hanya 'admin'; disamakan dengan aksi tulis lain, dan sekarang
// dijaga di controller agar barang yang sedang dipinjam tidak bisa dihapus.
router.delete('/:id', requirePermission('inventaris.barang', 'delete'), deleteInventory);

module.exports = router;
