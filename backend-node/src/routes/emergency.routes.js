const express = require('express');
const router = express.Router();
const { triggerAlarm, dismissAlarm, getAlerts, getActiveAlerts } = require('../controllers/emergency.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Semua pengguna terautentikasi (warga pelapor, admin, pengurus) dapat memicu sinyal/simulasi darurat
router.post('/trigger', triggerAlarm);
router.post('/dismiss/:id', dismissAlarm);
router.get('/alerts', requirePermission('aspirasi.darurat', 'view'), getAlerts);
router.get('/active', requirePermission('aspirasi.darurat', 'view'), getActiveAlerts);

module.exports = router;
