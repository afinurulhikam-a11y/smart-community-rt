const express = require('express');
const router = express.Router();
const { getFamilies, getFamilyDetail, createFamily, updateFamily, deleteFamily } = require('../controllers/family.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('kependudukan.warga', 'view'), getFamilies);
router.get('/:id', requirePermission('kependudukan.warga', 'view'), getFamilyDetail);
router.post('/', requirePermission('kependudukan.warga', 'create'), createFamily);
router.put('/:id', requirePermission('kependudukan.warga', 'update'), updateFamily);
router.delete('/:id', roleGuard('admin'), deleteFamily);

module.exports = router;
