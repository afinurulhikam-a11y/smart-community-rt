const { pool } = require('../config/database');
const { logActivity } = require('../services/log.service');
const { jenisKelamin } = require('../utils/normalisasi');

async function getFamilies(req, res) {
  try {
    const { search } = req.query;
    let query = `SELECT k.*,
        (SELECT COUNT(*) FROM anggota_keluarga ak WHERE ak.keluarga_id = k.id) AS jumlah_anggota,
        -- false berarti nama kepala keluarga masih memakai nama anggota pertama
        -- sebagai penanda sementara, bukan kepala keluarga sungguhan.
        EXISTS (
          SELECT 1 FROM anggota_keluarga ak2
          WHERE ak2.keluarga_id = k.id AND ak2.status_keluarga = 'Kepala Keluarga'
        ) AS kepala_terkonfirmasi
      FROM keluarga k WHERE k.deleted_at IS NULL`;
    const params = [];

    // Penyempitan baris untuk warga — lapisan kedua, bukan yang pertama.
    //
    // Hari ini `kependudukan.warga` memang tertutup bagi warga di tabel izin,
    // jadi klausa ini seolah tidak pernah terpakai. Tapi izin itu bisa diubah
    // dari layar Menu & Akses, dan permintaan "biar warga bisa lihat direktori
    // RT" sangat masuk akal untuk muncul suatu hari. Tanpa klausa ini, satu
    // klik itu membuka NIK, no_kk, alamat, dan telepon SELURUH warga kepada
    // setiap warga sekaligus. Pola yang sama sudah dipakai di bill.controller.
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      query += ` AND k.no_kk = (SELECT no_kk FROM users WHERE id = $${params.length})`;
    }

    if (search) { params.push(`%${search}%`); query += ` AND (k.no_kk ILIKE $${params.length} OR k.kepala_keluarga ILIKE $${params.length} OR k.alamat ILIKE $${params.length})`; }
    const countQuery = `SELECT COUNT(*) FROM (${query}) AS total`;
    const countResult = await pool.query(countQuery, params);
    const totalData = parseInt(countResult.rows[0].count);

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 25;
    const offset = (page - 1) * limit;
    const totalPages = Math.ceil(totalData / limit);

    query += ` ORDER BY k.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const result = await pool.query(query, params);
    return res.status(200).json({ 
      success: true, 
      count: result.rows.length, 
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        per_page: limit
      },
      data: result.rows 
    });
  } catch (err) {
    console.error('GetFamilies Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getFamilyDetail(req, res) {
  try {
    const { id } = req.params;
    // Rute detail ikut disempitkan. Menyaring daftar tetapi membiarkan
    // `/:id` terbuka adalah kelalaian yang paling sering terjadi: id-nya
    // bisa ditebak atau didapat dari tempat lain, dan seluruh penyaringan
    // di daftar menjadi tidak ada artinya.
    const params = [id];
    let syaratWarga = '';
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      syaratWarga = ` AND no_kk = (SELECT no_kk FROM users WHERE id = $${params.length})`;
    }

    const familyResult = await pool.query(
      `SELECT * FROM keluarga WHERE id = $1 AND deleted_at IS NULL${syaratWarga}`,
      params
    );
    if (familyResult.rows.length === 0) return res.status(404).json({ success: false, message: 'Kartu Keluarga tidak ditemukan.' });
    const membersResult = await pool.query('SELECT * FROM anggota_keluarga WHERE keluarga_id = $1 ORDER BY id', [id]);
    return res.status(200).json({ success: true, data: { ...familyResult.rows[0], anggota: membersResult.rows } });
  } catch (err) {
    console.error('GetFamilyDetail Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createFamily(req, res) {
  try {
    const { no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, anggota } = req.body;
    if (!no_kk || !kepala_keluarga || !alamat || !rt || !rw) return res.status(400).json({ success: false, message: 'No KK, kepala keluarga, alamat, RT, dan RW wajib diisi.' });
    const existing = await pool.query('SELECT id FROM keluarga WHERE no_kk = $1', [no_kk]);
    if (existing.rows.length > 0) return res.status(409).json({ success: false, message: 'No KK sudah terdaftar.' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const familyResult = await client.query(
        `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [no_kk, kepala_keluarga, alamat || null, rt || '001', rw || '001', kelurahan || null, kecamatan || null]
      );
      const family = familyResult.rows[0];
      if (anggota && Array.isArray(anggota)) {
        for (const a of anggota) {
          await client.query(
            `INSERT INTO anggota_keluarga (keluarga_id, nik, nama, jenis_kelamin, tempat_lahir, tanggal_lahir, agama, status_keluarga, pekerjaan, pendidikan) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
            // jenis_kelamin bertipe varchar(1): mengirim "Laki-laki" apa
            // adanya membuat seluruh permintaan gagal dengan 500 yang tidak
            // menjelaskan apa-apa. Dinormalisasi lebih dulu.
            [family.id, a.nik || null, a.nama, jenisKelamin(a.jenis_kelamin), a.tempat_lahir || null, a.tanggal_lahir || null, a.agama || null, a.status_keluarga || null, a.pekerjaan || null, a.pendidikan || null]
          );
        }
      }
      await client.query('COMMIT');
      await logActivity(req, 'CREATE', `Menambah kartu keluarga ${family.no_kk} atas nama ${family.kepala_keluarga}`);
      return res.status(201).json({ success: true, message: 'Kartu Keluarga berhasil ditambahkan.', data: family });
    } catch (txErr) { await client.query('ROLLBACK'); throw txErr; }
    finally { client.release(); }
  } catch (err) {
    console.error('CreateFamily Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateFamily(req, res) {
  try {
    const { id } = req.params;
    const { kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan } = req.body;
    const result = await pool.query(
      `UPDATE keluarga SET kepala_keluarga = COALESCE($1, kepala_keluarga), alamat = COALESCE($2, alamat), rt = COALESCE($3, rt), rw = COALESCE($4, rw), kelurahan = COALESCE($5, kelurahan), kecamatan = COALESCE($6, kecamatan), updated_at = NOW() WHERE id = $7 RETURNING *`,
      [kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Kartu Keluarga tidak ditemukan.' });
    const kk = result.rows[0];
    await logActivity(req, 'UPDATE', `Mengubah kartu keluarga ${kk.no_kk} atas nama ${kk.kepala_keluarga}`);
    return res.status(200).json({ success: true, message: 'Kartu Keluarga berhasil diperbarui.', data: kk });
  } catch (err) {
    console.error('UpdateFamily Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteFamily(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('UPDATE keluarga SET deleted_at = NOW() WHERE id = $1 RETURNING id, no_kk', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Kartu Keluarga tidak ditemukan.' });
    await logActivity(req, 'DELETE', `Menghapus kartu keluarga ${result.rows[0].no_kk}`);
    return res.status(200).json({ success: true, message: 'Kartu Keluarga berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteFamily Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getFamilies, getFamilyDetail, createFamily, updateFamily, deleteFamily };
