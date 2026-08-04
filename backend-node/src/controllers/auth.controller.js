const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/database');
const { logActivity } = require('../services/log.service');

async function register(req, res) {
  return res.status(403).json({
    success: false,
    message: 'Registrasi mandiri tidak diaktifkan. Akun warga dibuatkan langsung oleh Pengurus RT saat mendaftarkan data kependudukan.',
  });
}

async function login(req, res) {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Email dan password wajib diisi.' });
    }

    const result = await pool.query('SELECT * FROM users WHERE email = $1 OR username = $1 OR nik = $1', [email]);
    if (result.rows.length === 0) {
      return res.status(401).json({ success: false, message: 'Kredensial tidak valid.' });
    }

    const user = result.rows[0];

    if (user.is_active === false) {
      return res.status(403).json({ success: false, message: 'Akun Anda sedang menunggu persetujuan dari Admin RT.' });
    }

    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Email atau password salah.' });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    const { password_hash, ...userData } = user;
    req.user = userData;
    await logActivity(req, 'LOGIN', `User ${userData.nama || userData.email} berhasil login ke sistem`);

    return res.status(200).json({ success: true, message: 'Login berhasil.', data: { user: userData, token } });
  } catch (err) {
    console.error('Login Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getMe(req, res) {
  try {
    const result = await pool.query(
      'SELECT id, username, nama, email, no_hp, no_kk, alamat, no_rt, role, is_active, created_at FROM users WHERE id = $1',
      [req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });
    }

    return res.status(200).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('GetMe Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateProfile(req, res) {
  try {
    const userId = req.user.id;
    const { nama, email, no_hp, username } = req.body;

    if (!nama) {
      return res.status(400).json({ success: false, message: 'Nama wajib diisi.' });
    }

    if (email) {
      const checkEmail = await pool.query('SELECT id FROM users WHERE LOWER(email) = LOWER($1) AND id != $2', [email, userId]);
      if (checkEmail.rows.length > 0) {
        return res.status(409).json({ success: false, message: 'Email sudah digunakan oleh akun lain.' });
      }
    }

    if (username) {
      const checkUsername = await pool.query('SELECT id FROM users WHERE LOWER(username) = LOWER($1) AND id != $2', [username, userId]);
      if (checkUsername.rows.length > 0) {
        return res.status(409).json({ success: false, message: 'Username sudah digunakan oleh akun lain.' });
      }
    }

    const result = await pool.query(
      `UPDATE users 
       SET nama = $1, 
           email = COALESCE($2, email), 
           no_hp = $3, 
           username = COALESCE($4, username) 
       WHERE id = $5 
       RETURNING id, nama, email, username, no_hp, no_kk, alamat, no_rt, role, is_active`,
      [nama, email || null, no_hp || null, username || null, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });
    }

    return res.status(200).json({ success: true, message: 'Profil berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateProfile Error:', err.message);
    if (err.code === '23505') {
      if (err.constraint && err.constraint.includes('username')) {
        return res.status(409).json({ success: false, message: 'Username sudah digunakan oleh akun lain.' });
      }
      if (err.constraint && err.constraint.includes('email')) {
        return res.status(409).json({ success: false, message: 'Email sudah digunakan oleh akun lain.' });
      }
      if (err.constraint && err.constraint.includes('no_hp')) {
        return res.status(409).json({ success: false, message: 'Nomor HP/WhatsApp sudah terdaftar pada akun lain.' });
      }
      return res.status(409).json({ success: false, message: 'Data yang diisi sudah terdaftar pada akun lain.' });
    }
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function changePassword(req, res) {
  try {
    const userId = req.user.id;
    const { oldPassword, newPassword } = req.body;

    if (!oldPassword || !newPassword) {
      return res.status(400).json({ success: false, message: 'Password lama dan password baru wajib diisi.' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ success: false, message: 'Password baru minimal 6 karakter.' });
    }

    const userRes = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
    if (userRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });
    }

    const isMatch = await bcrypt.compare(oldPassword, userRes.rows[0].password_hash);
    if (!isMatch) {
      return res.status(400).json({ success: false, message: 'Password lama salah.' });
    }

    const salt = await bcrypt.genSalt(10);
    const newHash = await bcrypt.hash(newPassword, salt);

    await pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);

    return res.status(200).json({ success: true, message: 'Password berhasil diubah.' });
  } catch (err) {
    console.error('ChangePassword Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { register, login, getMe, updateProfile, changePassword };
