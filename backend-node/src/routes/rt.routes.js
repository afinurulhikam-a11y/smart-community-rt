const express = require('express');
const router = express.Router();
const { getRt, createRt, updateRt, deleteRt } = require('../controllers/rt.controller');
const { authMiddleware, roleGuard } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Dibaca semua peran, tetapi ISINYA disaring pengendali: peran lintas RT
// menerima seluruh RT dalam RW-nya, peran lain hanya RT-nya sendiri.
router.get('/', getRt);

// Sengaja `roleGuard`, bukan `requirePermission` — sama seperti menu_akses dan
// reset: kewenangan yang menentukan batas seluruh data tidak boleh bergantung
// pada tabel izin yang batas itu ikut menjaganya.
router.post('/', roleGuard('admin'), createRt);
router.put('/:id', roleGuard('admin'), updateRt);
router.delete('/:id', roleGuard('admin'), deleteRt);

module.exports = router;
