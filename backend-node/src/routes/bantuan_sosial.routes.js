const express = require('express');
const router = express.Router();
const { getBantuanSosial, getBantuanSosialStats, createBantuanSosial, updateBantuanSosial, deleteBantuanSosial, exportBantuanSosial, getBantuanSosialHistory } = require('../controllers/bantuan_sosial.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/export', requirePermission('kependudukan.bansos', 'view'), exportBantuanSosial);
router.get('/', requirePermission('kependudukan.bansos', 'view'), getBantuanSosial);
router.get('/stats', requirePermission('kependudukan.bansos', 'view'), getBantuanSosialStats);
router.get('/:id/history', requirePermission('kependudukan.bansos', 'view'), getBantuanSosialHistory);
router.post('/', requirePermission('kependudukan.bansos', 'create'), createBantuanSosial);
router.put('/:id', requirePermission('kependudukan.bansos', 'update'), updateBantuanSosial);
router.delete('/:id', roleGuard('admin'), deleteBantuanSosial);

module.exports = router;
