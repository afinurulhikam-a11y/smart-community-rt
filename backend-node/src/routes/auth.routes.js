const express = require('express');
const router = express.Router();
const { register, login, getMe,
  getProfilLengkap, updateProfile, changePassword } = require('../controllers/auth.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

// Login dan registrasi WAJIB terbuka: token justru diterbitkan di sini, jadi
// menuntut token untuk mengaksesnya membuat login mustahil bagi siapa pun.
router.post('/register', register);
router.post('/login', login);

// Selebihnya baru menuntut token.
router.use(authMiddleware);

router.get('/me', getMe);

// Profil lengkap milik pemanggil sendiri — email, no_hp, no_kk, nik, alamat.
// Dipisahkan dari /me karena hasil /me DISIMPAN klien ke localStorage,
// sedangkan ini hanya dibaca saat layar Profil Saya terbuka lalu dilupakan.
router.get('/profil', getProfilLengkap);
router.put('/profile', updateProfile);
router.put('/change-password', changePassword);

module.exports = router;
