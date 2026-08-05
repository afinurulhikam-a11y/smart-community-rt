const express = require('express');
const router = express.Router();
const { getLetters, createLetter, updateLetterStatus } = require('../controllers/letter.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', requirePermission('layanan.surat', 'view'), getLetters);
router.post('/', requirePermission('layanan.surat', 'create'), createLetter);
router.put('/:id/approve', requirePermission('layanan.surat', 'update'), updateLetterStatus);

module.exports = router;
