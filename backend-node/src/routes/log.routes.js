const express = require('express');
const router = express.Router();
const { getActivityLogs, clearActivityLogs } = require('../controllers/log.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('pengaturan.log', 'view'),  getActivityLogs);
router.delete('/', roleGuard('admin'), clearActivityLogs);

module.exports = router;
