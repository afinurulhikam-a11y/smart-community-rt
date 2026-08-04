const express = require('express');
const router = express.Router();
const { getAnnouncements, createAnnouncement, updateAnnouncement, deleteAnnouncement } = require('../controllers/announcement.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('kegiatan.pengumuman', 'view'), getAnnouncements);
router.post('/', requirePermission('kegiatan.pengumuman', 'create'), createAnnouncement);
router.put('/:id', requirePermission('kegiatan.pengumuman', 'update'), updateAnnouncement);
router.delete('/:id', roleGuard('admin'), deleteAnnouncement);

module.exports = router;
