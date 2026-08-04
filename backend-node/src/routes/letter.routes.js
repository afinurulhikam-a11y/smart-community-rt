const express = require('express');
const router = express.Router();
const { getLetters, createLetter, updateLetterStatus } = require('../controllers/letter.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('layanan.surat', 'view'), getLetters);
router.post('/', roleGuard('warga'), createLetter);
router.put('/:id/approve', requirePermission('layanan.surat', 'update'), updateLetterStatus);

module.exports = router;
