const express = require('express');
const router = express.Router();
const { logSensor, getSensorLogs, getLatestSensorData } = require('../controllers/sensor.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.post('/log', logSensor);
router.get('/logs', getSensorLogs);
router.get('/latest', getLatestSensorData);

module.exports = router;
