const express = require('express');
const router = express.Router();
const {
  getRt, createRt, updateRt, deleteRt,
  getPerbandinganRt, exportPerbandinganRt,
} = require('../controllers/rt.controller');
const { authMiddleware, roleGuard } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Dibaca semua peran, tetapi ISINYA disaring pengendali: peran lintas RT
// menerima seluruh RT dalam RW-nya, peran lain hanya RT-nya sendiri.
router.get('/', getRt);

// Rekap satu baris per RT. Didaftarkan SEBELUM `/:id` — kalau tidak,
// "perbandingan" akan tertelan sebagai sebuah id RT. Pola yang sama sudah
// menjadi aturan di inventory.routes.js untuk /borrowings.
router.get('/perbandingan', getPerbandinganRt);
router.get('/perbandingan/ekspor', exportPerbandinganRt);

// Sengaja `roleGuard`, bukan `requirePermission` — sama seperti menu_akses dan
// reset: kewenangan yang menentukan batas seluruh data tidak boleh bergantung
// pada tabel izin yang batas itu ikut menjaganya.
//
// ===================================================================
// Kenapa MENAMBAH dan MENGHAPUS berbeda dari MENGUBAH
// ===================================================================
//
// Menambah dan menghapus RT MENGGESER BATAS yang menentukan seluruh
// pelingkupan data — dan nomor RT-nya tertanam di topik MQTT setiap perangkat
// alarm yang sudah terpasang di lapangan. Menambah RT tanpa memflash
// perangkatnya menghasilkan RT yang sirenenya tidak pernah berbunyi, dan
// tidak ada satu pun layar yang bisa memberi tahu hal itu. Itu wewenang
// pemasang sistem, bukan wewenang jabatan.
//
// MENGUBAH nama RT, alamat sekretariat, dan siapa ketuanya tidak menggeser
// batas apa pun — dan justru itu pekerjaan Ketua RW yang paling biasa.
// Mengharuskan ia menghubungi administrator untuk mencatat pergantian ketua
// RT adalah cara membuat datanya menjadi usang.
router.post('/', roleGuard('admin'), createRt);
router.put('/:id', roleGuard('admin', 'ketua_rw'), updateRt);
router.delete('/:id', roleGuard('admin'), deleteRt);

module.exports = router;
