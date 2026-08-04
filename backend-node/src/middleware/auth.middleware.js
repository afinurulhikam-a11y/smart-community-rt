const jwt = require('jsonwebtoken');
const { pool } = require('../config/database');

/** Role sistem yang selalu berakses penuh dan tidak pernah dibaca dari tabel. */
const ROLE_ADMIN = 'admin';

const KOLOM_AKSI = {
  view: 'can_view',
  create: 'can_create',
  update: 'can_update',
  delete: 'can_delete',
};

const LABEL_AKSI = {
  view: 'melihat',
  create: 'menambah data pada',
  update: 'mengubah data pada',
  delete: 'menghapus data pada',
};

function authMiddleware(req, res, next) {
  let token;
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.split(' ')[1];
  } else if (req.query.token) {
    token = req.query.token;
  }

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Akses ditolak. Token tidak ditemukan.',
    });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({
      success: false,
      message: 'Token tidak valid atau sudah kedaluwarsa.',
    });
  }
}

/**
 * Penjagaan berbasis ROLE, dipakai untuk hal yang memang melekat pada peran
 * dan bukan pada modul — misalnya hanya warga yang boleh memicu panic button.
 *
 * Untuk akses per modul, pakai requirePermission: itu yang bisa diatur admin
 * lewat layar Menu & Akses.
 */
function roleGuard(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: 'Anda tidak memiliki izin untuk mengakses resource ini.',
      });
    }
    next();
  };
}

/**
 * Penjagaan berbasis IZIN MODUL, dibaca dari tabel role_permissions.
 *
 * Tiga hal yang menjaga sistem tetap aman:
 *  1. Admin lolos lebih dulu tanpa menyentuh tabel — apa pun isi database,
 *     admin tidak mungkin terkunci dari aplikasinya sendiri.
 *  2. Menu ber-is_sistem (Menu & Akses, Reset Sistem) hanya untuk admin,
 *     bahkan bila ada baris izin yang menyatakan sebaliknya.
 *  3. Bila baris izin tidak ada, jawabannya TOLAK — bukan izinkan.
 *
 * Query dijalankan per request tanpa cache. Pada skala RT biayanya tidak
 * berarti, sedangkan cache akan menghadirkan risiko izin basi — hal terakhir
 * yang boleh terjadi pada kontrol akses.
 */
function requirePermission(menuKode, aksi = 'view') {
  const kolom = KOLOM_AKSI[aksi];
  if (!kolom) {
    throw new Error(`Aksi izin tidak dikenal: "${aksi}". Pakai view/create/update/delete.`);
  }

  return async (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ success: false, message: 'Anda belum masuk.' });
    }

    if (req.user.role === ROLE_ADMIN) return next();

    try {
      const r = await pool.query(
        `SELECT m.nama, m.is_sistem, m.is_aktif,
                COALESCE(p.${kolom}, false) AS diizinkan
         FROM menu_items m
         LEFT JOIN role_permissions p
           ON p.menu_kode = m.kode AND p.role = $2
         WHERE m.kode = $1`,
        [menuKode, req.user.role]
      );

      // Menu tidak terdaftar berarti ada salah tulis kode di rute. Tolak,
      // jangan diam-diam mengizinkan.
      if (r.rows.length === 0) {
        console.error(`requirePermission: menu "${menuKode}" tidak ada di menu_items.`);
        return res.status(403).json({
          success: false,
          message: 'Modul tidak dikenali sehingga aksesnya ditolak.',
        });
      }

      const menu = r.rows[0];

      if (menu.is_sistem) {
        return res.status(403).json({
          success: false,
          message: `${menu.nama} hanya bisa diakses Administrator.`,
        });
      }

      if (!menu.is_aktif) {
        return res.status(403).json({
          success: false,
          message: `Modul ${menu.nama} sedang dinonaktifkan.`,
        });
      }

      if (!menu.diizinkan) {
        return res.status(403).json({
          success: false,
          message: `Anda tidak punya izin ${LABEL_AKSI[aksi]} ${menu.nama}.`,
        });
      }

      return next();
    } catch (err) {
      console.error('requirePermission Error:', err.message);
      return res.status(500).json({ success: false, message: 'Gagal memeriksa izin akses.' });
    }
  };
}

module.exports = { authMiddleware, roleGuard, requirePermission, ROLE_ADMIN };
