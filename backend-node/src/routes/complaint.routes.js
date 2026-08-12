const express = require('express');
const router = express.Router();
const { getComplaints, getComplaintStats, createComplaint, updateComplaintStatus, tandaiTanggapanDibaca, deleteComplaint } = require('../controllers/complaint.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validate.middleware');
const Joi = require('joi');

const complaintCreateSchema = Joi.object({
  judul: Joi.string().required(),
  deskripsi: Joi.string().allow('', null),
  kategori: Joi.string().allow('', null)
}).unknown(true);

const complaintUpdateSchema = Joi.object({
  status: Joi.string().valid('Menunggu', 'Diproses', 'Selesai', 'Ditolak').required(),
  response: Joi.string().allow('', null)
}).unknown(true);

router.use(authMiddleware);

router.get('/stats', requirePermission('aspirasi.pengaduan', 'view'), getComplaintStats);
router.get('/', requirePermission('aspirasi.pengaduan', 'view'), getComplaints);
router.post('/', requirePermission('aspirasi.pengaduan', 'create'), validate(complaintCreateSchema), createComplaint);
router.put('/:id/status', requirePermission('aspirasi.pengaduan', 'update'), validate(complaintUpdateSchema), updateComplaintStatus);

// Dijaga `view`, BUKAN `update` — di modul ini `update` berarti MENANGGAPI
// pengaduan, kewenangan pengurus. Memberi warga `update` hanya supaya ia bisa
// menghapus lencananya sendiri akan sekaligus membuka jalan menanggapi seluruh
// pengaduan warga lain. Kepemilikannya ditegakkan di controller lewat
// `user_id`, mengikuti preseden `POST /polling/:id/vote` dan `POST /meteran`.
router.put('/:id/baca', requirePermission('aspirasi.pengaduan', 'view'), tandaiTanggapanDibaca);
router.delete('/:id', roleGuard('admin'), deleteComplaint);

module.exports = router;
