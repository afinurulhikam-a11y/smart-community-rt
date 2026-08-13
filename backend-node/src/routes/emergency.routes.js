const express = require('express');
const router = express.Router();
const { triggerAlarm, dismissAlarm, getAlerts, getActiveAlerts,
  kendaliAlarm, statusAlarm } = require('../controllers/emergency.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Semua pengguna terautentikasi (warga pelapor, admin, pengurus) dapat memicu sinyal/simulasi darurat
router.post('/trigger', triggerAlarm);
router.post('/dismiss/:id', dismissAlarm);

// Kendali alat, terpisah dari pelaporan kejadian.
//
// TANPA requirePermission dengan sengaja: seluruh peran boleh menyalakan
// alarm, dan itu memang maksudnya — keadaan darurat tidak menunggu matriks
// izin. Yang menjaga tetap ada dan tidak dilonggarkan: authMiddleware di atas
// (sesi sah, belum dicabut), PIN darurat diverifikasi di controller, dan
// setiap penekanan tercatat di activity_logs termasuk yang PIN-nya salah.
router.post('/alarm', kendaliAlarm);
router.get('/alarm/status', statusAlarm);
router.get('/alerts', requirePermission('aspirasi.darurat', 'view'), getAlerts);
router.get('/active', requirePermission('aspirasi.darurat', 'view'), getActiveAlerts);

module.exports = router;
