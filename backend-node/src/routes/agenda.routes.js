const express = require('express');
const router = express.Router();
const { getAgenda, createAgenda, updateAgenda, deleteAgenda } = require('../controllers/agenda.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validate.middleware');
const Joi = require('joi');

const agendaCreateSchema = Joi.object({
  judul: Joi.string().required(),
  deskripsi: Joi.string().allow('', null),
  tipe: Joi.string().allow('', null),
  tanggal: Joi.alternatives().try(Joi.date().iso(), Joi.string().pattern(/^\d{4}-\d{2}-\d{2}/)).required(),
  waktu_mulai: Joi.string().pattern(/^([01]?\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/).allow('', null),
  waktu_selesai: Joi.string().pattern(/^([01]?\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/).allow('', null),
  lokasi: Joi.string().allow('', null),
  status: Joi.string().valid('Akan Datang', 'Terjadwal', 'Berjalan', 'Selesai', 'Batal').allow('', null),
}).unknown(true);

const agendaUpdateSchema = Joi.object({
  judul: Joi.string().allow('', null),
  deskripsi: Joi.string().allow('', null),
  tipe: Joi.string().allow('', null),
  tanggal: Joi.alternatives().try(Joi.date().iso(), Joi.string().pattern(/^\d{4}-\d{2}-\d{2}/)).allow('', null),
  waktu_mulai: Joi.string().pattern(/^([01]?\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/).allow('', null),
  waktu_selesai: Joi.string().pattern(/^([01]?\d|2[0-3]):([0-5]\d)(:[0-5]\d)?$/).allow('', null),
  lokasi: Joi.string().allow('', null),
  status: Joi.string().valid('Akan Datang', 'Terjadwal', 'Berjalan', 'Selesai', 'Batal').allow('', null),
  notulen_url: Joi.string().allow('', null)
}).unknown(true);

router.use(authMiddleware);

router.get('/', requirePermission('kegiatan.agenda', 'view'), getAgenda);
router.post('/', requirePermission('kegiatan.agenda', 'create'), validate(agendaCreateSchema), createAgenda);
router.put('/:id', requirePermission('kegiatan.agenda', 'update'), validate(agendaUpdateSchema), updateAgenda);
router.delete('/:id', roleGuard('admin'), deleteAgenda);

module.exports = router;
