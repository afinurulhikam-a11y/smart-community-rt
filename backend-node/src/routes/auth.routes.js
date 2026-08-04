const express = require('express');
const router = express.Router();
const { register, login, getMe, updateProfile, changePassword } = require('../controllers/auth.controller');
const { authMiddleware } = require('../middleware/auth.middleware');

// Login dan registrasi WAJIB terbuka: token justru diterbitkan di sini, jadi
// menuntut token untuk mengaksesnya membuat login mustahil bagi siapa pun.
router.post('/register', register);
router.post('/login', login);

// Selebihnya baru menuntut token.
router.use(authMiddleware);

router.get('/me', getMe);
router.put('/profile', updateProfile);
router.put('/change-password', changePassword);

module.exports = router;
