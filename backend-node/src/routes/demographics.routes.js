const express = require('express');
const router = express.Router();
const { getDemographicsSummary } = require('../controllers/demographics.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

// Protect route for Admin and Pengurus RT only
router.use(authMiddleware);
router.use(requirePermission('kependudukan.statistik', 'view'));

router.get('/summary', requirePermission('kependudukan.statistik', 'view'), getDemographicsSummary);

module.exports = router;
