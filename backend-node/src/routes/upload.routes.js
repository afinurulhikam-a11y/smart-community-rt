const express = require('express');
const router = express.Router();
const { upload } = require('../middleware/upload.middleware');
const { authMiddleware } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.post('/', upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Tidak ada file yang diunggah.' });
    }

    // req.protocol might not be reliable behind proxies, but we'll try to build a full URL
    // or just return the path relative to public/
    const fileUrl = `/uploads/${req.file.filename}`;

    return res.status(200).json({
      success: true,
      message: 'File berhasil diunggah.',
      data: {
        url: fileUrl,
        mimetype: req.file.mimetype,
        size: req.file.size
      }
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message || 'Terjadi kesalahan saat mengunggah file.' });
  }
});

module.exports = router;
