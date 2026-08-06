const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Ensure upload directory exists
const uploadDir = path.join(__dirname, '../../public/uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

/**
 * Ekstensi DITENTUKAN dari tipe yang sudah lolos daftar izin, bukan dari nama
 * berkas kiriman klien.
 *
 * Sebelumnya nama simpanannya memakai `path.extname(file.originalname)` —
 * bagian yang sepenuhnya dikendalikan pengirim — sementara satu-satunya
 * pemeriksaan adalah `file.mimetype`, yang juga dikirim klien dan bisa disetel
 * bebas terlepas dari isi maupun nama berkasnya.
 *
 * Jadi permintaan dengan `Content-Type: image/png` tetapi
 * `filename="jahat.html"` lolos penyaring dan tersimpan sebagai `.html` di
 * bawah /public/uploads — yang disajikan Express secara statis, dengan
 * content-type sesuai ekstensinya. Hasilnya HTML/JS tersimpan yang berjalan di
 * origin API itu sendiri, dan Helmet di sini sengaja mematikan CSP.
 *
 * Dengan memetakan tipe → ekstensi, nama berkas kiriman tidak lagi menentukan
 * apa pun. Ia bahkan tidak ikut disimpan.
 */
const TIPE_DIIZINKAN = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'application/pdf': '.pdf',
};

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ekstensi = TIPE_DIIZINKAN[file.mimetype] || '.bin';
    cb(null, file.fieldname + '-' + uniqueSuffix + ekstensi);
  }
});

const fileFilter = (req, file, cb) => {
  if (Object.prototype.hasOwnProperty.call(TIPE_DIIZINKAN, file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Format file tidak didukung. Hanya JPG, PNG, dan PDF yang diizinkan.'), false);
  }
};

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  },
  fileFilter: fileFilter
});

module.exports = { upload };
