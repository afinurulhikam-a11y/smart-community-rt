const express = require('express');
const router = express.Router();
const { getWarga, exportWargaExcel, exportWargaPdf, tambahWargaLengkap, updateWargaLengkap, importWargaExcel } = require('../controllers/warga.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

const { validate } = require('../middleware/validate.middleware');
const Joi = require('joi');

const wargaSchema = Joi.object({
  nik: Joi.string().required(),
  nama: Joi.string().required(),
  no_kk: Joi.string().required(),
  no_hp: Joi.string().required(),
  jenis_kelamin: Joi.string().required(),
  alamat: Joi.string().allow('', null),
  status_keluarga: Joi.string().allow('', null),
  has_ktp: Joi.boolean(),
  tanggal_lahir: Joi.string().required(),
  status_pernikahan: Joi.string().required(),
  agama: Joi.string().required(),
  pendidikan: Joi.string().required(),
  pekerjaan: Joi.string().required(),
  status_rumah: Joi.string().allow('', null)
}).unknown(true);

router.use(authMiddleware);
router.get('/', requirePermission('kependudukan.warga', 'view'), getWarga);
router.post('/', requirePermission('kependudukan.warga', 'create'), validate(wargaSchema), tambahWargaLengkap);
router.get('/export/excel', requirePermission('kependudukan.warga', 'view'), exportWargaExcel);
router.post('/import/excel', requirePermission('kependudukan.warga', 'create'), importWargaExcel);
router.get('/export/pdf', requirePermission('kependudukan.warga', 'view'), exportWargaPdf);

// Ubah data warga. NIK tidak boleh berubah (kunci utama anggota sekaligus
// username akun), jadi ia ada di path, bukan di body.
router.put('/:nik', requirePermission('kependudukan.warga', 'update'), updateWargaLengkap);

module.exports = router;
