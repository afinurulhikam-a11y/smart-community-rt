const express = require('express');
const router = express.Router();
const {
  meteranSaya,
  isiMeteran,
  daftarMeteran,
  koreksiMeteran,
} = require('../controllers/meteran.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

// authMiddleware SEBELUM requirePermission — kalau dibalik, hasilnya 401 dan
// bukan 403, karena `req.user` belum terisi saat izin diperiksa.
router.use(authMiddleware);

// Aksi milik warga dijaga `view`, BUKAN `create`/`update`.
//
// Di modul ini `update` berarti mengoreksi meteran warga lain — kewenangan
// pengurus. Memberi warga `update` supaya bisa mengisi meterannya sendiri akan
// sekaligus membuka koreksi seluruh warga.
//
// Pola yang sama sudah dipakai dan sudah tercatat di CLAUDE.md sebagai jebakan
// yang pernah terjadi: `POST /polling/:id/vote` dijaga `view` karena `create`
// di sana berarti MEMBUAT polling, dan `POST /payments/iuran` dijaga `view`
// karena `create` berarti MENERBITKAN tagihan. Kepemilikan barisnya ditegakkan
// di controller lewat `no_kk`, bukan oleh tabel izin.
router.get('/saya', requirePermission('keuangan.iuran', 'view'), meteranSaya);
router.post('/', requirePermission('keuangan.iuran', 'view'), isiMeteran);

// Daftar dibaca semua peran; controller menyempitkannya untuk warga.
router.get('/', requirePermission('keuangan.iuran', 'view'), daftarMeteran);

// Koreksi milik pengurus, dan tidak mengenal batas tanggal — justru untuk
// keadaan setelah tanggal 5 inilah jalur ini ada.
router.put('/:id/koreksi', requirePermission('keuangan.iuran', 'update'), koreksiMeteran);

module.exports = router;
