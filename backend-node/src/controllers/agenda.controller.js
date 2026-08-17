const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');

async function getAgenda(req, res) {
  try {
    const { status, tipe } = req.query;
    let query = `SELECT a.*, a.tanggal::text AS tanggal, u.nama AS created_by_nama,
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
    const { judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status } = req.body;
    if (!judul || !tanggal) return res.status(400).json({ success: false, message: 'Judul dan tanggal wajib diisi.' });

    const cleanMulai = (waktu_mulai && typeof waktu_mulai === 'string' && waktu_mulai.trim()) || null;
    const cleanSelesai = (waktu_selesai && typeof waktu_selesai === 'string' && waktu_selesai.trim()) || null;
    const cleanDeskripsi = (deskripsi && typeof deskripsi === 'string' && deskripsi.trim()) || null;
    const cleanLokasi = (lokasi && typeof lokasi === 'string' && lokasi.trim()) || null;
    const cleanTipe = (tipe && typeof tipe === 'string' && tipe.trim()) || 'Kegiatan';
    const cleanStatus = (status && typeof status === 'string' && status.trim()) || 'Akan Datang';

    const result = await pool.query(
      `INSERT INTO agenda (judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, created_by) 
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) 
       RETURNING *, tanggal::text AS tanggal`,
      [judul.trim(), cleanDeskripsi, cleanTipe, tanggal, cleanMulai, cleanSelesai, cleanLokasi, cleanStatus, req.user.id]
    );
    const a = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Membuat agenda "${ringkas(a.judul)}" — ${a.tipe || '-'}, tanggal ${a.tanggal ? String(a.tanggal).slice(0, 10) : '-'}`);

    return res.status(201).json({ success: true, message: 'Agenda berhasil dibuat.', data: a });
  } catch (err) {
    console.error('CreateAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateAgenda(req, res) {
  try {
    const { id } = req.params;
    const { judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, notulen_url } = req.body;

    const cleanMulai = waktu_mulai !== undefined ? ((waktu_mulai && typeof waktu_mulai === 'string' && waktu_mulai.trim()) || null) : undefined;
    const cleanSelesai = waktu_selesai !== undefined ? ((waktu_selesai && typeof waktu_selesai === 'string' && waktu_selesai.trim()) || null) : undefined;
    const cleanDeskripsi = deskripsi !== undefined ? ((deskripsi && typeof deskripsi === 'string' && deskripsi.trim()) || null) : undefined;
    const cleanLokasi = lokasi !== undefined ? ((lokasi && typeof lokasi === 'string' && lokasi.trim()) || null) : undefined;

    const result = await pool.query(
      `UPDATE agenda SET 
         judul = COALESCE($1, judul), 
         deskripsi = CASE WHEN $2::boolean THEN $3 ELSE deskripsi END, 
         tipe = COALESCE($4, tipe), 
         tanggal = COALESCE($5, tanggal), 
         waktu_mulai = CASE WHEN $6::boolean THEN $7 ELSE waktu_mulai END, 
         waktu_selesai = CASE WHEN $8::boolean THEN $9 ELSE waktu_selesai END, 
         lokasi = CASE WHEN $10::boolean THEN $11 ELSE lokasi END, 
         status = COALESCE($12, status), 
         notulen_url = CASE WHEN $13::boolean THEN $14 ELSE notulen_url END, 
         updated_at = NOW() 
       WHERE id = $15 AND deleted_at IS NULL 
       RETURNING *, tanggal::text AS tanggal`,
      [
        judul ? judul.trim() : null,
        deskripsi !== undefined,
        cleanDeskripsi,
        tipe ? tipe.trim() : null,
        tanggal || null,
        waktu_mulai !== undefined,
        cleanMulai,
        waktu_selesai !== undefined,
        cleanSelesai,
        lokasi !== undefined,
        cleanLokasi,
        status || null,
        notulen_url !== undefined,
        notulen_url || null,
        id
      ]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Agenda tidak ditemukan.' });
    const a = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah agenda "${ringkas(a.judul)}" — status ${a.status}, tanggal ${a.tanggal ? String(a.tanggal).slice(0, 10) : '-'}`);

    return res.status(200).json({ success: true, message: 'Agenda berhasil diperbarui.', data: a });
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
