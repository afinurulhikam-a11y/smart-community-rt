const express = require('express');
const router = express.Router();
const { getLetters, createLetter, updateLetterStatus, deleteLetter } = require('../controllers/letter.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validate.middleware');
const Joi = require('joi');

const letterCreateSchema = Joi.object({
  jenis_surat: Joi.string().required(),
  keperluan: Joi.string().required()
}).unknown(true);

const letterUpdateSchema = Joi.object({
  status: Joi.string().valid('diproses', 'disetujui', 'ditolak').required(),
  response_note: Joi.string().allow(null, '')
}).unknown(true);

router.use(authMiddleware);

router.get('/', requirePermission('layanan.surat', 'view'), getLetters);
router.post('/', requirePermission('layanan.surat', 'create'), validate(letterCreateSchema), createLetter);
router.put('/:id/approve', requirePermission('layanan.surat', 'update'), validate(letterUpdateSchema), updateLetterStatus);
router.delete('/:id', deleteLetter);

module.exports = router;
