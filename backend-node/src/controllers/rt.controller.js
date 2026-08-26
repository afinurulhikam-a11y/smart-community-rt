/**
 * Daftar RT dalam satu RW.
 *
 * ===================================================================
 * Kenapa modul ini tidak punya entri di matriks izin
 * ===================================================================
 *
 * Membuat dan menghapus RT adalah wewenang sistem, bukan wewenang modul —
 * alasannya sama persis dengan Menu & Akses dan Reset Sistem: kewenangan yang
 * menentukan BATAS seluruh data tidak boleh bergantung pada tabel yang batas
 * itu sendiri ikut menjaganya. Karena itu penjagaannya `roleGuard('admin')`,
 * dan matriks izin tetap 18 modul.
 *
 * ===================================================================
 * Kenapa daftarnya boleh dibaca semua peran
 * ===================================================================
 *
 * Setiap layar menampilkan RT mana yang sedang dilihat, dan warga pun perlu
 * tahu ia terdaftar di RT berapa. Yang membedakan bukan boleh atau tidaknya
 * membaca, melainkan BERAPA BANYAK yang terbaca: peran lintas RT menerima
 * seluruh RT dalam RW-nya, peran lain hanya menerima RT-nya sendiri.
 *
 * Penyaringannya memakai `bolehLintasRt` yang sama dengan seluruh pengendali
 * lain, bukan daftar peran yang ditulis ulang di sini.
 */
const { pool } = require('../config/database');
const { logActivity, TIPE } = require('../services/log.service');
const { bolehLintasRt } = require('../utils/lingkup-rt');
const { siapkanMasterRt } = require('../services/master-rt.service');

const KOLOM = `
  r.id, r.kode, r.nama, r.rw_kode, r.ketua_id, r.alamat_sekretariat,
  r.created_at, r.updated_at,
  k.nama AS ketua_nama,
  (SELECT COUNT(*)::int FROM keluarga kk
    WHERE kk.rt_id = r.id AND kk.deleted_at IS NULL) AS jumlah_kk,
  (SELECT COUNT(*)::int FROM users u
    WHERE u.rt_id = r.id AND u.deleted_at IS NULL) AS jumlah_akun
`;

async function getRt(req, res) {
  try {
    const params = [];
    let saring = '';
    if (!bolehLintasRt(req)) {
      // Peran biasa hanya melihat RT-nya sendiri. Bukan penyembunyian demi
      // kerapian: daftar RT lain memuat nama ketua dan alamat sekretariat.
      params.push(req.user?.rt_id ?? null);
      saring = ' AND r.id = $1';
    }
    const hasil = await pool.query(
      `SELECT ${KOLOM}
         FROM rt r
         LEFT JOIN users k ON k.id = r.ketua_id
        WHERE r.deleted_at IS NULL${saring}
        ORDER BY r.rw_kode, r.kode`,
      params
    );
    return res.status(200).json({
      success: true,
      count: hasil.rows.length,
      data: hasil.rows,
    });
  } catch (err) {
    console.error('GetRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Menormalkan nomor RT: "3" dan " 3 " sama-sama menjadi "003". */
function normalKode(nilai) {
  const bersih = String(nilai ?? '').trim();
  if (!bersih) return '';
  return /^\d+$/.test(bersih) ? bersih.padStart(3, '0') : bersih;
}

async function createRt(req, res) {
  try {
    const kode = normalKode(req.body?.kode);
    const rwKode = normalKode(req.body?.rw_kode) || req.user?.rw_kode || '001';
    const { nama, alamat_sekretariat, ketua_id } = req.body || {};

    if (!kode) {
      return res.status(400).json({ success: false, message: 'Nomor RT wajib diisi.' });
    }

    // RT dan tabel masternya lahir dalam SATU transaksi.
    //
    // Sebuah RT tanpa jenis iuran dan tanpa kategori kas bukan RT yang setengah
    // jadi — ia RT yang tidak bisa dipakai sama sekali: dropdown Generate
    // Tagihan kosong, dan Kas RT tidak punya satu pun pos untuk mencatat uang.
    // Tidak ada layar yang memberi tahu penyebabnya, karena tidak ada yang
    // salah menurut kode mana pun; daftarnya memang kosong.
    //
    // Membuatnya di luar transaksi berarti sebuah RT bisa berdiri tanpa master
    // ketika penyisipannya gagal di tengah, dan tidak ada jalan dari layar
    // untuk memperbaikinya.
    const client = await pool.connect();
    let baris;
    let master;
    try {
      await client.query('BEGIN');
      const hasil = await client.query(
        `INSERT INTO rt (kode, nama, rw_kode, alamat_sekretariat, ketua_id)
         VALUES ($1, $2, $3, $4, $5) RETURNING id, kode, nama, rw_kode`,
        [kode, (nama || '').trim() || `RT ${kode}`, rwKode,
          alamat_sekretariat || null, ketua_id || null]
      );
      baris = hasil.rows[0];
      master = await siapkanMasterRt(client, baris.id);
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }

    await logActivity(
      req, TIPE.CREATE,
      `Menambah RT ${kode} pada RW ${rwKode} — beserta ${master.jenis_iuran} jenis iuran, `
      + `${master.kategori_kas} kategori kas, dan ${master.kategori_bop} kategori BOP bawaan`
    );
    return res.status(201).json({
      success: true, message: 'RT berhasil ditambahkan.', data: { ...baris, master },
    });
  } catch (err) {
    // Ditangkap dari indeks unik, bukan diperiksa lebih dulu dengan SELECT:
    // dua permintaan bersamaan bisa lolos pemeriksaan dan tetap bentrok.
    if (err.code === '23505') {
      return res.status(409).json({
        success: false, message: 'Nomor RT tersebut sudah terdaftar pada RW ini.',
      });
    }
    console.error('CreateRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateRt(req, res) {
  try {
    const { id } = req.params;
    const { nama, alamat_sekretariat, ketua_id } = req.body || {};

    const lama = await pool.query('SELECT * FROM rt WHERE id = $1 AND deleted_at IS NULL', [id]);
    if (!lama.rows.length) {
      return res.status(404).json({ success: false, message: 'RT tidak ditemukan.' });
    }

    // Nomor RT sengaja TIDAK boleh diubah. Ia sudah tertanam pada topik MQTT
    // di setiap perangkat alarm yang terpasang; menggantinya dari layar akan
    // membuat sirene berhenti berbunyi tanpa satu pun pesan galat.
    const hasil = await pool.query(
      `UPDATE rt SET
         nama = COALESCE($2, nama),
         alamat_sekretariat = COALESCE($3, alamat_sekretariat),
         ketua_id = $4,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING id, kode, nama, rw_kode, ketua_id`,
      [id, (nama || '').trim() || null, alamat_sekretariat ?? null,
        ketua_id ?? lama.rows[0].ketua_id]
    );

    await logActivity(req, TIPE.UPDATE, `Mengubah data RT ${lama.rows[0].kode}`);
    return res.status(200).json({
      success: true, message: 'Data RT berhasil diperbarui.', data: hasil.rows[0],
    });
  } catch (err) {
    console.error('UpdateRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteRt(req, res) {
  try {
    const { id } = req.params;
    const rt = await pool.query('SELECT * FROM rt WHERE id = $1 AND deleted_at IS NULL', [id]);
    if (!rt.rows.length) {
      return res.status(404).json({ success: false, message: 'RT tidak ditemukan.' });
    }

    // Kunci asing `rt_id` memakai ON DELETE RESTRICT, jadi basis data akan
    // menolak sendiri. Diperiksa lebih dulu supaya pesannya menyebut berapa
    // banyak yang menghalangi, bukan sekadar galat kendala yang tidak terbaca.
    const isi = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM keluarga WHERE rt_id = $1 AND deleted_at IS NULL) AS kk,
         (SELECT COUNT(*)::int FROM users WHERE rt_id = $1 AND deleted_at IS NULL) AS akun`,
      [id]
    );
    const { kk, akun } = isi.rows[0];
    if (kk > 0 || akun > 0) {
      return res.status(409).json({
        success: false,
        message: `RT ${rt.rows[0].kode} masih memiliki ${kk} kartu keluarga dan ${akun} akun. `
          + 'Pindahkan atau hapus datanya lebih dulu.',
      });
    }

    await pool.query('UPDATE rt SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1', [id]);
    await logActivity(req, TIPE.DELETE, `Menghapus RT ${rt.rows[0].kode}`);
    return res.status(200).json({ success: true, message: 'RT berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getRt, createRt, updateRt, deleteRt };
