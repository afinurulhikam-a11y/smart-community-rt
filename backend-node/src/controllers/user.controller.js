const bcrypt = require('bcryptjs');
const { pool } = require('../config/database');
const { logActivity, TIPE } = require('../services/log.service');

async function getUsers(req, res) {
  try {
    // Batas bawaan. Sebelumnya endpoint ini mengembalikan SELURUH tabel setiap
    // kali dipanggil. Pada skala RT hari ini tidak terasa; tabel ini termasuk
    // yang tumbuh terus tanpa pernah dipangkas, jadi yang berubah hanya kapan
    // masalahnya muncul. Klien boleh meminta lebih lewat ?limit=, dengan batas
    // atas supaya satu permintaan tidak bisa menarik seluruh basis data.
    const batas = Math.min(parseInt(req.query.limit, 10) || 200, 1000);

    const { role, no_rt, search } = req.query;
    let query = `SELECT id, nama, email, no_hp, no_kk, alamat, no_rt, role, is_active, created_at FROM users WHERE deleted_at IS NULL`;
    const params = [];

    const pengurusRoles = ['ketua_rt', 'sekretaris', 'bendahara'];
    if (pengurusRoles.includes(req.user.role)) {
      params.push(req.user.no_rt || '001');
      query += ` AND no_rt = $${params.length}`;
    }
    if (role) { params.push(role); query += ` AND role = $${params.length}`; }
    if (no_rt && req.user.role === 'admin') { params.push(no_rt); query += ` AND no_rt = $${params.length}`; }
    if (search) { params.push(`%${search}%`); query += ` AND (nama ILIKE $${params.length} OR email ILIKE $${params.length})`; }

    // Saring ke pengguna yang benar-benar punya data kependudukan. Dipakai
    // pemilih peminjam barang: dari 48 akun, 21 di antaranya yatim (tidak
    // punya baris anggota_keluarga) dan tidak layak muncul sebagai pilihan.
    const hanyaTerdaftar = req.query.terdaftar === 'true';
    if (hanyaTerdaftar) {
      query += ' AND EXISTS (SELECT 1 FROM anggota_keluarga ak WHERE ak.nik = users.nik)';
    }

    // Urutan bawaan dipertahankan agar layar lain tidak berubah perilakunya;
    // hanya daftar pemilih yang diurutkan alfabetis supaya mudah dicari.
    params.push(batas);
    query += hanyaTerdaftar ? ' ORDER BY nama ASC' : ' ORDER BY created_at DESC';
    query += ` LIMIT $${params.length}`;
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetUsers Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Mengaktifkan atau menonaktifkan akun.
 *
 * Menonaktifkan akun adalah cara paling halus membungkam seseorang — misalnya
 * warga yang baru saja mengirim pengaduan. Karena itu dicatat sebagai AKSES,
 * setara dengan perubahan peran.
 */
async function updateUserStatus(req, res) {
  try {
    const { id } = req.params;
    const { is_active } = req.body;
    if (typeof is_active !== 'boolean') {
      return res.status(400).json({ success: false, message: 'is_active harus boolean (true/false).' });
    }

    const sebelum = await pool.query('SELECT nama, email, is_active FROM users WHERE id = $1', [id]);
    if (sebelum.rows.length === 0) return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });

    const result = await pool.query(`UPDATE users SET is_active = $1, updated_at = NOW() WHERE id = $2 RETURNING id, nama, email, is_active`, [is_active, id]);
    // Tidak ada cache yang perlu dibersihkan: `authMiddleware` membaca
    // `is_active` segar dari database pada setiap permintaan, jadi penonaktifan
    // ini berlaku pada permintaan berikutnya — di berapa pun instance.

    const lama = sebelum.rows[0];
    await logActivity(
      req,
      TIPE.AKSES,
      `${is_active ? 'Mengaktifkan' : 'Menonaktifkan'} akun ${lama.nama} (${lama.email}) — ` +
        `status: ${lama.is_active ? 'aktif' : 'nonaktif'} → ${is_active ? 'aktif' : 'nonaktif'}`
    );

    return res.status(200).json({ success: true, message: is_active ? 'User berhasil diaktifkan.' : 'User berhasil dinonaktifkan.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateUserStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createUser(req, res) {
  try {
    const { nama, email, password, role, no_hp, no_kk, alamat, no_rt } = req.body;
    if (!nama || !email || !password) {
      return res.status(400).json({ success: false, message: 'Nama, email, dan password wajib diisi.' });
    }
    const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    if (existing.rows.length > 0) return res.status(409).json({ success: false, message: 'Email sudah terdaftar.' });

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);
    const validRoles = ['warga', 'admin', 'ketua_rt', 'sekretaris', 'bendahara'];
    const userRole = validRoles.includes(role) ? role : 'warga';

    const result = await pool.query(
      `INSERT INTO users (nama, email, password_hash, role, no_hp, no_kk, alamat, no_rt) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id, nama, email, no_hp, no_kk, alamat, no_rt, role, created_at`,
      [nama, email, passwordHash, userRole, no_hp || null, no_kk || null, alamat || null, no_rt || '001']
    );

    // AKSES, bukan CREATE: membuat akun berarti menciptakan wewenang baru —
    // apalagi bila perannya bukan 'warga'. Kata sandinya tidak pernah ikut
    // dicatat, dan tabel ini permanen.
    await logActivity(
      req,
      TIPE.AKSES,
      `Membuat akun baru ${nama} (${email}) dengan peran "${userRole}"`
    );

    return res.status(201).json({ success: true, message: 'User berhasil dibuat.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateUser Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getPendingUsers(req, res) {
  try {
    const result = await pool.query(
      `SELECT id, nama, email, no_hp, no_kk, alamat, no_rt, role, created_at 
       FROM users 
       WHERE is_active = false AND deleted_at IS NULL
       ORDER BY created_at ASC`
    );
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetPendingUsers Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteUser(req, res) {
  try {
    const { id } = req.params;
    
    // Pastikan user ada dan proteksi akun Administrator Developer
    const checkUser = await pool.query('SELECT username, role, is_active FROM users WHERE id = $1', [id]);
    if (checkUser.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });
    }

    if (checkUser.rows[0].username === 'Administrator' || checkUser.rows[0].role === 'admin') {
      return res.status(403).json({ success: false, message: 'Akun Administrator Utama Developer bersifat permanen dan tidak dapat dihapus.' });
    }
    
    if (checkUser.rows[0].is_active === true) {
      return res.status(403).json({ success: false, message: 'Tidak dapat menghapus user yang sudah aktif/disetujui.' });
    }

    // Identitas dibaca SEBELUM dihapus — setelahnya barisnya tidak ada lagi
    // dan lognya hanya akan memuat UUID yang tidak bisa ditelusuri siapa pun.
    const korban = await pool.query('SELECT nama, email, role FROM users WHERE id = $1', [id]);
    const u = korban.rows[0] || {};

    await pool.query('UPDATE users SET deleted_at = NOW(), is_active = false WHERE id = $1', [id]);

    await logActivity(
      req,
      TIPE.AKSES,
      `Menolak & menghapus pendaftaran akun ${u.nama || '-'} (${u.email || '-'}), peran "${u.role || '-'}"`
    );

    return res.status(200).json({ success: true, message: 'Pendaftaran warga berhasil ditolak (dihapus).' });
  } catch (err) {
    console.error('DeleteUser Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server saat menghapus user.' });
  }
}

async function getUserByNik(req, res) {
  try {
    const { nik } = req.params;
    const result = await pool.query(
      `SELECT u.id, u.username, u.email, u.nama, u.no_hp, u.no_kk, u.role, u.is_active, u.nik
       FROM users u
       WHERE (u.nik = $1 OR u.username = $1) AND u.deleted_at IS NULL`,
      [nik]
    );

    if (result.rows.length === 0) {
      const akRes = await pool.query('SELECT ak.nik, ak.nama, ak.no_hp, k.no_kk FROM anggota_keluarga ak JOIN keluarga k ON ak.keluarga_id = k.id WHERE ak.nik = $1', [nik]);
      if (akRes.rows.length === 0) {
        return res.status(404).json({ success: false, message: 'Data warga tidak ditemukan.' });
      }
      const ak = akRes.rows[0];
      return res.status(200).json({
        success: true,
        data: {
          id: null,
          username: ak.nik,
          email: ak.nik,
          nama: ak.nama,
          no_hp: ak.no_hp || '',
          no_kk: ak.no_kk,
          role: 'warga',
          is_active: true,
          nik: ak.nik,
          is_new: true,
        },
      });
    }

    return res.status(200).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('GetUserByNik Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateUserCredentials(req, res) {
  const client = await pool.connect();
  try {
    const { nik, no_hp, role, password } = req.body;
    if (!nik) {
      return res.status(400).json({ success: false, message: 'NIK wajib diisi.' });
    }

    // Otorisasi SEBELUM transaksi — tolak lebih awal sebelum menyentuh data.
    const callerRole = req.user.role;
    const allowedModRoles = ['admin', 'ketua_rt', 'sekretaris'];
    if (!allowedModRoles.includes(callerRole)) {
      return res.status(403).json({
        success: false,
        message: 'Anda hanya memiliki hak akses lihat (view-only) dan tidak diizinkan mengubah data/kredensial warga.',
      });
    }

    // Panjang sandi diperiksa SEBELUM transaksi dimulai.
    //
    // Sebelumnya pemeriksaan ini berada jauh di bawah, setelah perubahan
    // nomor HP dan peran sudah dijalankan di dalam transaksi yang sama. Sandi
    // yang ditolak karena itu ikut membatalkan perubahan peran lewat ROLLBACK
    // — pengguna melihat "sandi minimal 8 karakter" lalu mendapati perannya
    // juga tidak berubah, tanpa satu pun keterangan yang menghubungkan
    // keduanya. Terlihat seperti backend yang tidak berfungsi.
    //
    // Aturannya: apa pun yang bisa ditolak dari isi permintaan diperiksa
    // sebelum baris pertama disentuh.
    if (password && password.trim() !== '' && password.trim().length < 8) {
      return res.status(400).json({
        success: false,
        message: 'Sandi minimal 8 karakter.',
      });
    }

    await client.query('BEGIN');

    let userRes = await client.query('SELECT id, role, password_hash FROM users WHERE (nik = $1 OR username = $1) AND deleted_at IS NULL', [nik]);
    let userId;

    if (userRes.rows.length === 0) {
      // Password wajib saat membuat akun baru — tidak ada lagi default '123456'.
      if (!password || password.trim() === '') {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message: 'Password wajib diisi saat membuat akun baru untuk warga.',
        });
      }
      const akRes = await client.query('SELECT ak.nama, ak.no_hp, k.no_kk, k.alamat FROM anggota_keluarga ak JOIN keluarga k ON ak.keluarga_id = k.id WHERE ak.nik = $1', [nik]);
      const nama = akRes.rows[0]?.nama || 'Warga';
      const noKk = akRes.rows[0]?.no_kk || '';
      const alamat = akRes.rows[0]?.alamat || '';
      const salt = await bcrypt.genSalt(10);
      const hash = await bcrypt.hash(password.trim(), salt);

      const newU = await client.query(
        'INSERT INTO users (username, email, password_hash, nama, no_hp, no_kk, alamat, role, is_active, nik, must_change_password) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, $9, true) RETURNING id',
        [nik, nik, hash, nama, no_hp || akRes.rows[0]?.no_hp || null, noKk, alamat, 'warga', nik]
      );
      userId = newU.rows[0].id;
    } else {
      userId = userRes.rows[0].id;
    }

    if (no_hp !== undefined) {
      await client.query('UPDATE users SET no_hp = $1, updated_at = NOW() WHERE id = $2', [no_hp, userId]);
      await client.query('UPDATE anggota_keluarga SET no_hp = $1 WHERE nik = $2', [no_hp, nik]);
    }

    const canChangeRole = callerRole === 'admin' || callerRole === 'ketua_rt';
    if (role) {
      if (!canChangeRole) {
        await client.query('ROLLBACK');
        return res.status(403).json({ success: false, message: 'Hanya Admin dan Ketua RT yang berhak mengubah role pengguna.' });
      }
      if (role === 'admin' && callerRole !== 'admin') {
        await client.query('ROLLBACK');
        return res.status(403).json({ success: false, message: 'Hanya Administrator yang berhak menetapkan role Administrator.' });
      }
      const validRoles = ['warga', 'admin', 'ketua_rt', 'sekretaris', 'bendahara'];
      if (!validRoles.includes(role)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ success: false, message: `Role tidak valid. Pilihan: ${validRoles.join(', ')}` });
      }
      // Peran dibaca ulang dari database oleh `authMiddleware` pada setiap
      // permintaan, jadi penurunan peran ini berlaku seketika tanpa perlu
      // membersihkan apa pun.
      await client.query('UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2', [role, userId]);
    }

    if (password && password.trim() !== '') {
      // Endpoint ini mengatur ulang sandi TANPA menanyakan sandi lama — memang
      // begitu tujuannya, karena pengurus perlu menolong warga yang lupa.
      //
      // Karena itu peran TARGET-nya harus diperiksa, bukan hanya peran
      // pemanggilnya. Tanpa ini seorang sekretaris cukup mengirim
      // `{ nik: 'Administrator', password: 'x' }` — pencariannya juga cocok
      // pada `username`, jadi tidak perlu tahu NIK apa pun — lalu masuk sebagai
      // administrator. Seluruh pemisahan peran runtuh dalam satu permintaan.
      //
      // Aturannya: sandi akun non-warga hanya boleh disetel oleh admin.
      const targetRole = userRes.rows[0]?.role || 'warga';
      if (targetRole !== 'warga' && callerRole !== 'admin') {
        await client.query('ROLLBACK');
        return res.status(403).json({
          success: false,
          message: `Hanya Administrator yang berhak mengatur ulang sandi akun berperan "${targetRole}".`,
        });
      }

      // Panjang sandi sudah diperiksa sebelum BEGIN — lihat komentar di sana.
      // Yang tersisa di sini hanya pemeriksaan peran target, yang memang butuh
      // baris user-nya dan karena itu tidak bisa dipindah ke atas.

      const salt = await bcrypt.genSalt(10);
      const hash = await bcrypt.hash(password.trim(), salt);
      await client.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [hash, userId]);
    }

    await client.query('COMMIT');
    await logActivity(req, 'UPDATE', `Mengubah kredensial/role akun NIK ${nik}`);

    return res.status(200).json({
      success: true,
      message: 'Kredensial & role akun berhasil diperbarui.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('UpdateUserCredentials Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal memperbarui kredensial.' });
  } finally {
    client.release();
  }
}

module.exports = {
  getUsers,
  updateUserStatus,
  createUser,
  getPendingUsers,
  deleteUser,
  getUserByNik,
  updateUserCredentials,
};
