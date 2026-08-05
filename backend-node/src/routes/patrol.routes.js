const express = require('express');
const router = express.Router();
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');
const {
  getSchedules,
  createSchedule,
  updateSchedule,
  deleteSchedule,
  getAttendances,
  submitAttendance,
  deleteAttendance,
  getPosRondaQr,
} = require('../controllers/patrol.controller');

router.use(authMiddleware);

router.get('/schedules', requirePermission('kegiatan.ronda', 'view'), getSchedules);
router.post('/schedules', requirePermission('kegiatan.ronda', 'create'), createSchedule);
router.put('/schedules/:id', requirePermission('kegiatan.ronda', 'update'), updateSchedule);
router.delete('/schedules/:id', requirePermission('kegiatan.ronda', 'delete'), deleteSchedule);

router.get('/attendances', requirePermission('kegiatan.ronda', 'view'), getAttendances);
router.post('/attendances', requirePermission('kegiatan.ronda', 'create'), submitAttendance);
router.delete('/attendances/:id', requirePermission('kegiatan.ronda', 'delete'), deleteAttendance);

router.get('/qr', requirePermission('kegiatan.ronda', 'view'), getPosRondaQr);

module.exports = router;
