const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');

async function getAgenda(req, res) {
  try {
    const { status, tipe } = req.query;
    let query = `SELECT a.*, u.nama AS created_by_nama,
                 COUNT(*) OVER() AS total_data 
                 FROM agenda a 
                 LEFT JOIN users u ON a.created_by = u.id 
                 WHERE a.deleted_at IS NULL`;
    const params = [];
    if (status && status !== 'Semua') { params.push(status); query += ` AND a.status = $${params.length}`; }
    if (tipe) { params.push(tipe); query += ` AND a.tipe = $${params.length}`; }
    query += ' ORDER BY a.tanggal DESC, a.waktu_mulai DESC';

    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 25;
    const offset = (page - 1) * limit;

    params.push(limit, offset);
    query += ` LIMIT $${params.length - 1} OFFSET $${params.length}`;

    const result = await pool.query(query, params);

    const totalData = result.rows.length > 0 ? parseInt(result.rows[0].total_data, 10) : 0;
    const totalPages = Math.ceil(totalData / limit);

    return res.status(200).json({ 
      success: true, 
      count: result.rows.length, 
      data: result.rows,
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        limit: limit
      }
    });
  } catch (err) {
    console.error('GetAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createAgenda(req, res) {
  try {
    const { judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi } = req.body;
    if (!judul || !tanggal) return res.status(400).json({ success: false, message: 'Judul dan tanggal wajib diisi.' });
    const result = await pool.query(
      `INSERT INTO agenda (judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, created_by) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [judul, deskripsi || null, tipe || 'Kegiatan', tanggal, waktu_mulai || null, waktu_selesai || null, lokasi || null, req.user.id]
    );
    const a = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Membuat agenda "${ringkas(a.judul)}" — ${a.tipe || '-'}, tanggal ${a.tanggal ? String(a.tanggal).slice(0, 10) : '-'}`);

    return res.status(201).json({ success: true, message: 'Agenda berhasil dibuat.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateAgenda(req, res) {
  try {
    const { id } = req.params;
    const { judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, notulen_url } = req.body;
    const result = await pool.query(
      `UPDATE agenda SET judul = COALESCE($1, judul), deskripsi = COALESCE($2, deskripsi), tipe = COALESCE($3, tipe), tanggal = COALESCE($4, tanggal), waktu_mulai = COALESCE($5, waktu_mulai), waktu_selesai = COALESCE($6, waktu_selesai), lokasi = COALESCE($7, lokasi), status = COALESCE($8, status), notulen_url = COALESCE($9, notulen_url), updated_at = NOW() WHERE id = $10 RETURNING *`,
      [judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, notulen_url, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Agenda tidak ditemukan.' });
    const a = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah agenda "${ringkas(a.judul)}" — status ${a.status}, tanggal ${a.tanggal ? String(a.tanggal).slice(0, 10) : '-'}`);

    return res.status(200).json({ success: true, message: 'Agenda berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteAgenda(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('UPDATE agenda SET deleted_at = NOW() WHERE id = $1 RETURNING id, judul', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Agenda tidak ditemukan.' });
    await logActivity(req, TIPE.DELETE, `Menghapus agenda "${ringkas(result.rows[0].judul)}"`);

    return res.status(200).json({ success: true, message: 'Agenda berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getAgenda, createAgenda, updateAgenda, deleteAgenda };
