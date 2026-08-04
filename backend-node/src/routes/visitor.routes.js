const express = require('express');
const router = express.Router();
const { getVisitors, getVisitorStats, createVisitor, checkoutVisitor, deleteVisitor } = require('../controllers/visitor.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('layanan.visitor', 'view'), getVisitors);
router.get('/stats', requirePermission('layanan.visitor', 'view'), getVisitorStats);
router.post('/', requirePermission('layanan.visitor', 'create'), createVisitor);
router.put('/:id/checkout', checkoutVisitor);
router.delete('/:id', requirePermission('layanan.visitor', 'delete'), deleteVisitor);

module.exports = router;
