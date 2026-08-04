const express = require('express');
const router = express.Router();
const { getWarga, exportWargaExcel, exportWargaPdf, tambahWargaLengkap, importWargaExcel } = require('../controllers/warga.controller');
const { authMiddleware, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);
router.get('/', requirePermission('kependudukan.warga', 'view'), getWarga);
router.post('/', requirePermission('kependudukan.warga', 'create'), tambahWargaLengkap);
router.get('/export/excel', requirePermission('kependudukan.warga', 'view'), exportWargaExcel);
router.post('/import/excel', requirePermission('kependudukan.warga', 'create'), importWargaExcel);
router.get('/export/pdf', requirePermission('kependudukan.warga', 'view'), exportWargaPdf);

module.exports = router;
