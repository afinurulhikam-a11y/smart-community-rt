const express = require('express');
const router = express.Router();
const { logSensor, getSensorLogs, getLatestSensorData } = require('../controllers/sensor.controller');
const { authMiddleware, roleGuard } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Hanya admin (atau akun sistem IoT) yang boleh menulis data sensor
router.post('/log', roleGuard('admin'), logSensor);
// Semua warga boleh melihat data sensor
router.get('/logs', getSensorLogs);
router.get('/latest', getLatestSensorData);

module.exports = router;
