const express = require('express');
const router = express.Router();
const { register, login, logout, getMe,
  getProfilLengkap, updateProfile, changePassword } = require('../controllers/auth.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

// Login dan registrasi WAJIB terbuka: token justru diterbitkan di sini, jadi
// menuntut token untuk mengaksesnya membuat login mustahil bagi siapa pun.
router.post('/register', register);
router.post('/login', login);

// Selebihnya baru menuntut token.
router.use(authMiddleware);

// Logout MENUNTUT token, dan itu disengaja: ia mencabut sesi seluruh perangkat
// milik pemanggil, jadi hanya pemilik sesi yang boleh memicunya. Tanpa penjaga
// ini, siapa pun yang tahu sebuah user-id bisa mengeluarkan orang lain.
router.post('/logout', logout);

router.get('/me', getMe);

// Profil lengkap milik pemanggil sendiri — email, no_hp, no_kk, nik, alamat.
// Dipisahkan dari /me karena hasil /me DISIMPAN klien ke localStorage,
// sedangkan ini hanya dibaca saat layar Profil Saya terbuka lalu dilupakan.
router.get('/profil', getProfilLengkap);
router.put('/profile', updateProfile);
router.put('/change-password', changePassword);

module.exports = router;
