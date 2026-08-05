const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/database');
const { logActivity, logSistem, ringkas, bandingkan, TIPE } = require('../services/log.service');

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

    // Ketiga cabang penolakan di bawah ini SEMUANYA dicatat.
    //
    // Sebelumnya hanya login yang berhasil yang tercatat, sehingga percobaan
    // pembobolan tidak meninggalkan jejak sama sekali: seratus tebakan kata
    // sandi terhadap akun bendahara tampak sama saja dengan tidak ada apa-apa.
    // Alamat IP-nya ikut tersimpan, dan itu yang membuat pola percobaan
    // beruntun bisa terlihat.
    //
    // Yang dicatat adalah identitas yang DICOBA, tidak pernah kata sandinya.

    const result = await pool.query('SELECT * FROM users WHERE email = $1 OR username = $1 OR nik = $1', [email]);
    if (result.rows.length === 0) {
      await logSistem(TIPE.LOGIN_GAGAL, `Percobaan masuk dengan akun tidak terdaftar: '${ringkas(email, 80)}'`, {
        req,
        pelaku: ringkas(email, 80),
      });
      return res.status(401).json({
        success: false,
        message: `Akun atau NIK '${email}' tidak terdaftar dalam sistem.`,
      });
    }

    const user = result.rows[0];

    if (user.is_active === false) {
      await logSistem(TIPE.LOGIN_GAGAL, `Percobaan masuk ke akun yang belum aktif: ${user.nama || user.email}`, {
        req,
        pelaku: user.nama || user.email,
      });
      return res.status(403).json({
        success: false,
        message: 'Akun Anda sedang menunggu verifikasi/persetujuan dari Pengurus RT.',
      });
    }

    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      await logSistem(
        TIPE.LOGIN_GAGAL,
        `Kata sandi salah untuk akun ${user.nama || user.email} (peran: ${user.role})`,
        { req, pelaku: user.nama || user.email }
      );
      return res.status(401).json({
        success: false,
        message: 'Password yang Anda masukkan salah. Silakan periksa kembali.',
      });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    const { password_hash, ...userData } = user;
    req.user = userData;
    // Peran ikut dicatat: "bendahara masuk pukul 02.13" adalah baris yang
    // berbeda artinya dari "warga masuk pukul 02.13".
    await logActivity(
      req,
      TIPE.LOGIN,
      `Berhasil masuk sebagai ${userData.nama || userData.email} (peran: ${userData.role})`
    );

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

    // Dibaca sebelum diubah, supaya lognya bisa menyebut nilai lamanya.
    const cekLama = await pool.query(
      'SELECT nama, email, username, no_hp FROM users WHERE id = $1',
      [userId]
    );
    const sebelum = cekLama.rows[0] || {};

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

    // Perubahan email dan username dicatat dengan nilai lamanya.
    //
    // Mengganti email lalu mengganti kata sandi adalah urutan klasik
    // pengambilalihan akun: pemilik aslinya kehilangan jalur pemulihan tanpa
    // pernah tahu. Dua baris log berurutan membuat pola itu terlihat.
    const rincian = bandingkan(
      sebelum,
      result.rows[0],
      { nama: 'nama', email: 'email', username: 'username', no_hp: 'no. HP' }
    );
    if (rincian) {
      await logActivity(req, TIPE.UPDATE, `Mengubah profil sendiri — ${rincian}`);
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
      // Gagal menebak kata sandi LAMA pada sesi yang sudah masuk. Ini pola
      // seseorang memakai perangkat yang ditinggalkan tanpa dikunci.
      await logActivity(
        req,
        TIPE.LOGIN_GAGAL,
        'Gagal mengubah kata sandi — kata sandi lama yang dimasukkan salah'
      );
      return res.status(400).json({ success: false, message: 'Password lama salah.' });
    }

    const salt = await bcrypt.genSalt(10);
    const newHash = await bcrypt.hash(newPassword, salt);

    await pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);

    // Hanya faktanya yang dicatat. Kata sandi lama maupun baru tidak pernah
    // masuk ke tabel ini — dan tabel ini permanen.
    await logActivity(req, TIPE.AKSES, 'Mengubah kata sandi akun sendiri');

    return res.status(200).json({ success: true, message: 'Password berhasil diubah.' });
  } catch (err) {
    console.error('ChangePassword Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { register, login, getMe, updateProfile, changePassword };
