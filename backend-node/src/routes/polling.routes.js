const express = require('express');
const router = express.Router();
const { getPolling, createPolling, vote, updatePollingStatus, deletePolling } = require('../controllers/polling.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('aspirasi.polling', 'view'), getPolling);
router.post('/', requirePermission('aspirasi.polling', 'create'), createPolling);
// Memberi suara dijaga 'view', BUKAN 'create'. Pada modul ini 'create' berarti
// membuat polling (lihat rute di atas), jadi memakainya untuk vote akan
// sekalian memberi warga hak membuat polling sendiri.
//
// Ikut memilih adalah partisipasi atas polling yang boleh dilihat; aturan
// sisanya sudah dijaga controller: polling harus aktif, dan UNIQUE
// (polling_id, user_id) memastikan satu orang satu suara.
router.post('/:id/vote', requirePermission('aspirasi.polling', 'view'), vote);
router.put('/:id/status', requirePermission('aspirasi.polling', 'update'), updatePollingStatus);
router.delete('/:id', roleGuard('admin'), deletePolling);

module.exports = router;
