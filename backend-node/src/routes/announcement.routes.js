const express = require('express');
const router = express.Router();
const { getAnnouncements, createAnnouncement, updateAnnouncement, deleteAnnouncement } = require('../controllers/announcement.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

// Pengumuman dijaga `kegiatan.agenda`, bukan izinnya sendiri.
//
// Ia sudah menjadi tab keempat di dalam layar Agenda & Kegiatan, jadi izin
// terpisah hanya membuat keadaan yang tidak bisa dijelaskan kepada siapa pun:
// layar boleh dibuka tetapi salah satu tab di dalamnya menjawab 403.
//
// Penggabungan ini tidak mengubah kewenangan satu peran pun — pada matriks
// bawaan, nilai agenda dan pengumuman memang sudah identik untuk kelimanya.
router.get('/', requirePermission('kegiatan.agenda', 'view'), getAnnouncements);
router.post('/', requirePermission('kegiatan.agenda', 'create'), createAnnouncement);
router.put('/:id', requirePermission('kegiatan.agenda', 'update'), updateAnnouncement);
router.delete('/:id', roleGuard('admin'), deleteAnnouncement);

module.exports = router;
