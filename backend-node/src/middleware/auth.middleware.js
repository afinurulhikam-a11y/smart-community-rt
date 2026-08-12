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

/**
 * Verifikasi token, LALU periksa akunnya ke database.
 *
 * ===================================================================
 * Kenapa menyentuh database di setiap permintaan
 * ===================================================================
 *
 * Sebelumnya middleware ini hanya memanggil `jwt.verify` dan memakai payload
 * token apa adanya. Peran ikut dibekukan ke dalam token saat login, dan masa
 * berlakunya 7 hari. Akibatnya:
 *
 *   - Menonaktifkan akun tidak memutus sesinya.
 *   - Menurunkan peran tidak mencabut aksesnya.
 *   - Menghapus akun pun tidak — tokennya tetap sah.
 *
 * Selama sepekan penuh. Jadi ketika seorang pengurus ketahuan menyalahgunakan
 * wewenang dan dicopot, ia tetap bisa bekerja dengan hak lamanya sampai
 * tokennya kedaluwarsa sendiri — dan tidak ada satu pun tombol di aplikasi yang
 * bisa menghentikannya. Itu justru kebalikan dari yang dibutuhkan.
 *
 * Biayanya satu SELECT terindeks pada primary key per permintaan. Ditukar
 * dengan kemampuan mencabut akses seketika, itu murah.
 *
 * PERAN DIAMBIL DARI DATABASE, BUKAN DARI TOKEN. Kalau tetap dibaca dari token,
 * penurunan peran baru berlaku setelah pengguna login ulang — dan orang yang
 * baru saja dicopot tidak punya alasan untuk melakukannya.
 *
 * ===================================================================
 * Kenapa TIDAK ADA cache di sini
 * ===================================================================
 *
 * Pernah ada: hasil verifikasi disimpan 30 detik per user-id supaya burst
 * permintaan dari satu tab hanya menyentuh database sekali. Cache itu dibongkar
 * ketika pencabutan sesi masuk, dan alasannya bukan selera:
 *
 *   1. Tiga kolom di bawah — `token_versi`, `is_active`, `deleted_at` — MENENTUKAN
 *      apakah sebuah sesi masih hidup. Menyimpannya 30 detik berarti token yang
 *      baru saja dicabut tetap diterima selama itu, dan pada Railway yang bisa
 *      menjalankan lebih dari satu instance, `invalidateAuthCache` di satu proses
 *      tidak pernah terlihat oleh proses lain. "Keluar" yang baru berlaku setengah
 *      menit kemudian, di sebagian instance saja, bukan keluar.
 *   2. Begitu ketiga kolom itu wajib segar, SELECT-nya tetap berjalan tiap
 *      permintaan — sehingga cache tidak lagi menghemat satu kueri pun.
 *      Menyisakannya hanya untuk `nama` berarti memelihara sumber kedua demi
 *      nol keuntungan.
 *
 * Yang tersisa adalah biaya yang memang sudah diterima sejak awal berkas ini:
 * satu SELECT terindeks pada primary key per permintaan. Bila pool terasa
 * sesak, naikkan `DB_POOL_MAX` — jangan kembalikan cache di jalur ini.
 *
 * ===================================================================
 * Token TIDAK LAGI diterima lewat query string
 * ===================================================================
 *
 * Dulu `?token=` diterima supaya navigasi browser (tombol Export/Unduh) bisa
 * menembak endpoint langsung, karena sebuah navigasi tidak bisa membawa header.
 * Harganya: kredensial sesi berumur 24 jam ikut tercatat di log akses server,
 * riwayat browser, dan header `Referer`.
 *
 * Penggantinya `src/routes/unduh.routes.js` — tiket sekali pakai berumur 60
 * detik yang hanya membuka satu unduhan tertentu. Selama query-param masih
 * diterima di sini, penghapusannya di klien tidak menutup apa pun, jadi
 * keduanya harus naik bersamaan.
 */
async function authMiddleware(req, res, next) {
  let token;
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.split(' ')[1];
  }

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Akses ditolak. Token tidak ditemukan.',
    });
  }

  let decoded;
  try {
    // Algoritma dikunci eksplisit, tidak diserahkan ke bawaan pustaka.
    //
    // `alg=none` dan token ber-RS256 dengan kunci penyerang sudah ditolak
    // jsonwebtoken@9 hari ini — tetapi penolakan itu milik PUSTAKA, bukan milik
    // kode ini, dan bawaan pustaka bisa berubah antar-versi mayor. Allowlist di
    // sini membuat "hanya HS256 yang diterima" menjadi keputusan yang tertulis
    // dan teruji, bukan warisan yang kebetulan masih berlaku.
    decoded = jwt.verify(token, process.env.JWT_SECRET, { algorithms: ['HS256'] });
  } catch (err) {
    return res.status(401).json({
      success: false,
      message: 'Token tidak valid atau sudah kedaluwarsa.',
    });
  }

  try {
    const akun = await pool.query(
      `SELECT id, nama, role, is_active, token_versi
       FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [decoded.id]
    );

    if (akun.rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Akun tidak ditemukan atau sudah dihapus. Silakan masuk kembali.',
      });
    }
    if (akun.rows[0].is_active === false) {
      return res.status(401).json({
        success: false,
        message: 'Akun Anda dinonaktifkan. Hubungi pengurus RT.',
      });
    }

    // Pencabutan sesi. `tv` dibandingkan sebagai BILANGAN BULAT, bukan terhadap
    // waktu — lihat migration_v29_token_versi.js untuk alasannya.
    //
    // `?? 0` adalah jalur kompatibilitas: token yang diterbitkan sebelum Fase B
    // tidak punya klaim ini, dan kolomnya lahir 0, jadi keduanya cocok dan tidak
    // ada seorang pun yang dikeluarkan oleh migrasinya. Token lama baru mati
    // pada logout pertama pemiliknya, atau pada kedaluwarsanya sendiri.
    if ((decoded.tv ?? 0) !== akun.rows[0].token_versi) {
      return res.status(401).json({
        success: false,
        message: 'Sesi Anda sudah berakhir. Silakan masuk kembali.',
      });
    }

    // Payload token dipertahankan (no_kk, email, dan lainnya dipakai controller),
    // tetapi peran dan nama ditimpa dengan yang berlaku sekarang.
    req.user = { ...decoded, role: akun.rows[0].role, nama: akun.rows[0].nama };
    return next();
  } catch (err) {
    // FAIL-CLOSED. Sebelumnya jalur ini memakai payload JWT sebagai cadangan
    // dan memanggil `next()` — sehingga gangguan database, sekecil apa pun,
    // MEMBERIKAN AKSES tanpa satu pun pemeriksaan di atas berjalan: akun
    // nonaktif lolos, akun terhapus lolos, dan sesi yang baru saja dicabut
    // lolos. Sebuah kegagalan infrastruktur tidak boleh berubah menjadi izin.
    //
    // 503, bukan 401: pengguna tidak melakukan kesalahan apa pun, dan
    // membedakannya penting supaya klien tidak menghapus sesi yang sebetulnya
    // masih sah. Yang hilang hanyalah ilusi — aplikasi ini memang tidak
    // berfungsi tanpa database.
    console.error('AuthMiddleware DB Error (menolak, fail-closed):', err.message);
    return res.status(503).json({
      success: false,
      message: 'Tidak dapat memverifikasi sesi karena database sedang bermasalah. Coba lagi sebentar lagi.',
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
