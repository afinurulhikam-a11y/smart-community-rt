const express = require('express');
const router = express.Router();
const { getActivityLogs } = require('../controllers/log.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('pengaturan.log', 'view'), getActivityLogs);

// TIDAK ADA rute DELETE di sini, dan itu disengaja.
//
// `DELETE /api/activity-logs` dulu ada dan dijaga roleGuard('admin') — yang
// berarti satu-satunya peran yang paling perlu diawasi justru dibolehkan
// menghapus catatan pengawasannya sendiri. Lihat penjelasan lengkapnya di
// `log.controller.js`. Jangan ditambahkan kembali: `activity_logs` kini juga
// menolak DELETE di tingkat database.

module.exports = router;
