const express = require('express');
const router = express.Router();
const { getAgenda, createAgenda, updateAgenda, deleteAgenda } = require('../controllers/agenda.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('kegiatan.agenda', 'view'), getAgenda);
router.post('/', requirePermission('kegiatan.agenda', 'create'), createAgenda);
router.put('/:id', requirePermission('kegiatan.agenda', 'update'), updateAgenda);
router.delete('/:id', roleGuard('admin'), deleteAgenda);

module.exports = router;
