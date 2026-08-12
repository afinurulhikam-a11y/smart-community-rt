const crypto = require('crypto');
const { pool } = require('../config/database');
const { JENIS_UNDUH, ambilHandler } = require('../config/jenis-unduh');
const { roleGuard, requirePermission } = require('../middleware/auth.middleware');
const { logActivity, TIPE } = require('../services/log.service');

/** Umur tiket. Pendek dengan sengaja: ia hanya perlu bertahan satu klik. */
const UMUR_DETIK = parseInt(process.env.TIKET_UNDUH_DETIK, 10) || 60;

function hash(nilai) {
  return crypto.createHash('sha256').update(nilai).digest('hex');
}

/**
 * Menjalankan middleware penjaga yang SUDAH ADA terhadap sebuah request, lalu
 * melaporkan hasilnya sebagai nilai balik.
 *
 * Terlihat berputar, dan itu disengaja. Alternatifnya — menulis ulang aturan
 * izin di berkas ini — berarti ada dua implementasi dari satu aturan, dan pada
 * saat keduanya berbeda, yang lebih longgarlah yang akan dipakai orang. Dengan
 * memanggil `requirePermission`/`roleGuard` apa adanya, tiket tidak mungkin
 * lebih longgar daripada rute aslinya: keduanya kode yang sama.
 *
 * `res` tiruan hanya menampung status dan badan; ia tidak pernah menyentuh
 * jaringan.
 */
function jalankanPenjaga(middleware, req) {
  return new Promise((resolve) => {
    const resTiruan = {
      status(kode) {
        this._kode = kode;
        return this;
      },
      json(badan) {
        resolve({ kode: this._kode || 200, badan });
      },
    };
    middleware(req, resTiruan, () => resolve(null));
  });
}

/** Penjaga yang berlaku untuk sebuah jenis — izin modul ATAU peran. */
function penjagaUntuk(def) {
  return def.peran
    ? roleGuard(...def.peran)
    : requirePermission(def.izin.kode, def.izin.aksi);
}

/**
 * POST /api/unduh/tiket — menukar sesi yang sah menjadi satu tautan unduhan.
 *
 * Tiket mentah dikembalikan SEKALI dan tidak pernah bisa ditampilkan ulang:
 * yang disimpan hanyalah SHA-256-nya. Bocornya isi tabel `tiket_unduh` karena
 * itu tidak memberi siapa pun satu unduhan pun — alasan yang sama kenapa kata
 * sandi tidak pernah disimpan apa adanya.
 */
async function buatTiket(req, res) {
  try {
    const { jenis, parameter } = req.body || {};

    const def = JENIS_UNDUH[jenis];
    if (!def) {
      return res.status(400).json({ success: false, message: 'Jenis unduhan tidak dikenal.' });
    }

    // Pemeriksaan izin PERTAMA. Yang kedua terjadi saat penukaran.
    const ditolak = await jalankanPenjaga(penjagaUntuk(def), req);
    if (ditolak) return res.status(ditolak.kode).json(ditolak.badan);

    const tiket = crypto.randomBytes(32).toString('base64url');

    // `token_versi` pemanggil disalin ke tiket supaya tiket ikut mati ketika
    // pemiliknya menekan Keluar. Tanpa ini sebuah tautan berumur 60 detik bisa
    // hidup lebih lama daripada sesinya sendiri, dan tetap menyerahkan berkas
    // berisi data warga setelah sesinya dicabut.
    const versi = await pool.query('SELECT token_versi FROM users WHERE id = $1', [req.user.id]);
    if (versi.rows.length === 0) {
      return res.status(401).json({ success: false, message: 'Akun tidak ditemukan.' });
    }

    await pool.query(
      `INSERT INTO tiket_unduh (tiket_hash, user_id, token_versi, jenis, parameter, kedaluwarsa)
       VALUES ($1, $2, $3, $4, $5::jsonb, NOW() + ($6 || ' seconds')::interval)`,
      [hash(tiket), req.user.id, versi.rows[0].token_versi, jenis,
        JSON.stringify(parameter || {}), String(UMUR_DETIK)]
    );

    // Penyapuan oportunistik: tidak ada penjadwal untuk ini, dan tidak perlu
    // ada. Tabelnya hanya tumbuh saat orang menekan Export, jadi membersihkan
    // sisa lama pada momen yang sama sudah cukup untuk menjaga ukurannya.
    pool.query('DELETE FROM tiket_unduh WHERE kedaluwarsa < NOW() - INTERVAL \'1 day\'')
      .catch((e) => console.warn('Sapu tiket unduh gagal:', e.message));

    return res.status(201).json({
      success: true,
      data: { tiket, jenis, kedaluwarsa_detik: UMUR_DETIK },
    });
  } catch (err) {
    console.error('BuatTiket Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal menyiapkan unduhan.' });
  }
}

/**
 * GET /api/unduh/:tiket — menukar tiket menjadi berkasnya.
 *
 * Rute ini SENGAJA berada di luar `authMiddleware`: sebuah navigasi browser
 * tidak bisa membawa header `Authorization`, dan itulah seluruh alasan
 * mekanisme ini ada. Pola yang sama dipakai webhook Midtrans.
 *
 * Yang menggantikan middleware bukan kelonggaran, melainkan satu UPDATE yang
 * memeriksa enam hal sekaligus dan bersifat atomik.
 */
async function tukarTiket(req, res) {
  try {
    const { tiket } = req.params;
    if (!tiket) {
      return res.status(400).json({ success: false, message: 'Tiket tidak diberikan.' });
    }

    // Satu pernyataan, dan itu yang membuatnya sekali pakai. Dua permintaan
    // bersamaan sama-sama mencoba menulis `dipakai_pada`; hanya satu yang
    // menemukan baris dengan `dipakai_pada IS NULL`, yang lain mendapat nol
    // baris. Pola yang sama dipakai `payBill`.
    //
    // Enam syarat, masing-masing menutup hal berbeda:
    //   dipakai_pada IS NULL   → sekali pakai
    //   kedaluwarsa > NOW()    → umur 60 detik
    //   deleted_at IS NULL     → akun sudah dihapus
    //   is_active = true       → akun dinonaktifkan admin
    //   token_versi sama       → pemiliknya sudah menekan Keluar
    const hasil = await pool.query(
      `UPDATE tiket_unduh t SET dipakai_pada = NOW()
       FROM users u
       WHERE t.tiket_hash = $1
         AND t.dipakai_pada IS NULL
         AND t.kedaluwarsa > NOW()
         AND u.id = t.user_id
         AND u.deleted_at IS NULL
         AND u.is_active = true
         AND u.token_versi = t.token_versi
       RETURNING t.jenis, t.parameter,
                 u.id, u.email, u.role, u.nama, u.username, u.no_rt`,
      [hash(tiket)]
    );

    if (hasil.rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Tautan unduhan sudah dipakai, kedaluwarsa, atau sesinya telah berakhir.',
      });
    }

    const baris = hasil.rows[0];
    const def = JENIS_UNDUH[baris.jenis];
    const handler = ambilHandler(baris.jenis);
    if (!def || !handler) {
      // Hanya mungkin bila sebuah jenis dihapus dari registry setelah tiketnya
      // terbit. Tolak — jangan menebak maksudnya.
      return res.status(400).json({ success: false, message: 'Jenis unduhan tidak dikenal.' });
    }

    // `req` disusun ulang supaya handler aslinya menerima persis bentuk yang
    // biasa diterimanya lewat jalur bearer: identitas dari baris `users` yang
    // baru saja dibaca, bukan dari apa pun yang dikirim pemanggil.
    const parameter = baris.parameter || {};
    const params = {};
    const query = {};
    for (const [k, v] of Object.entries(parameter)) {
      if (def.paramJalur.includes(k)) params[k] = v;
      else query[k] = v;
    }

    req.user = {
      id: baris.id,
      email: baris.email,
      role: baris.role,
      nama: baris.nama,
      username: baris.username,
      no_rt: baris.no_rt,
    };
    req.params = params;
    req.query = query;

    // Pemeriksaan izin KEDUA, dengan peran yang berlaku SEKARANG. Menu & Akses
    // bisa mencabut izin di antara pembuatan dan penukaran tiket, dan jendela
    // 60 detik cukup untuk itu terjadi. Tiket bukan izin beku.
    const ditolak = await jalankanPenjaga(penjagaUntuk(def), req);
    if (ditolak) return res.status(ditolak.kode).json(ditolak.badan);

    await logActivity(req, TIPE.AKSES, `Mengunduh ${def.label} lewat tautan sekali pakai`);

    return handler(req, res);
  } catch (err) {
    console.error('TukarTiket Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal memproses unduhan.' });
  }
}

module.exports = { buatTiket, tukarTiket };
