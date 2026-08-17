const express = require('express');
const router = express.Router();
const {
  getFamilies,
  getFamilyDetail,
  createFamily,
  updateFamily,
  deleteFamily,
  exportFamiliesExcel,
  exportFamiliesPdf,
} = require('../controllers/family.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Kartu keluarga kini punya izinnya sendiri, `kependudukan.kk`.
//
// Sebelumnya seluruh berkas ini menumpang `kependudukan.warga`, sehingga
// Data KK tidak bisa dibuka atau ditutup terpisah dari Data Warga. Keduanya
// memang dua kewenangan berbeda: menyunting anggota keluarga tidak sama
// dengan menyusun ulang kartu keluarganya.
//
// PERLU DIINGAT saat mengatur izin: Iuran Warga memuat `GET /api/families`
// untuk menagih per kartu keluarga. Peran yang mengelola iuran harus tetap
// memegang minimal `view` di sini, kalau tidak daftar KK-nya gagal dimuat
// walau izin iurannya penuh.
router.get('/', requirePermission('kependudukan.kk', 'view'), getFamilies);
router.get('/export/excel', requirePermission('kependudukan.kk', 'view'), exportFamiliesExcel);
router.get('/export/pdf', requirePermission('kependudukan.kk', 'view'), exportFamiliesPdf);
router.get('/:id', requirePermission('kependudukan.kk', 'view'), getFamilyDetail);
router.post('/', requirePermission('kependudukan.kk', 'create'), createFamily);
router.put('/:id', requirePermission('kependudukan.kk', 'update'), updateFamily);

// DELETE tetap admin-only, TIDAK diturunkan menjadi `kependudukan.kk:delete`.
//
// Menghapus kartu keluarga memicu rantai CASCADE ke `bills` yang lalu ditolak
// RESTRICT oleh `bill_payments` — bila rantainya lolos, ia membawa serta
// seluruh anggota keluarga dan riwayat tagihannya. Itu keputusan setingkat
// Reset Sistem, bukan sekadar aksi hapus pada sebuah daftar.
router.delete('/:id', roleGuard('admin'), deleteFamily);

module.exports = router;
