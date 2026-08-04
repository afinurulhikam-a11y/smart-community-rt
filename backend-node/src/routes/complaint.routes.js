const express = require('express');
const router = express.Router();
const { getComplaints, createComplaint, updateComplaintStatus, deleteComplaint } = require('../controllers/complaint.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('aspirasi.pengaduan', 'view'), getComplaints);
router.post('/', requirePermission('aspirasi.pengaduan', 'create'), createComplaint);
router.put('/:id/status', requirePermission('aspirasi.pengaduan', 'update'), updateComplaintStatus);
router.delete('/:id', roleGuard('admin'), deleteComplaint);

module.exports = router;
