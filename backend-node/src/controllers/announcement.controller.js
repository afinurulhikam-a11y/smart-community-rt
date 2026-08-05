const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');

async function getAnnouncements(req, res) {
  try {
    const { kategori, status, search } = req.query;
    let query = `SELECT a.*, u.nama AS created_by_nama FROM announcements a LEFT JOIN users u ON a.created_by = u.id WHERE 1=1`;
    const params = [];
    if (kategori && kategori !== 'Semua Kategori') { params.push(kategori); query += ` AND a.kategori = $${params.length}`; }
    if (status) { params.push(status); query += ` AND a.status = $${params.length}`; }
    if (search) { params.push(`%${search}%`); query += ` AND (a.judul ILIKE $${params.length} OR a.isi ILIKE $${params.length})`; }
    query += ' ORDER BY a.created_at DESC';
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetAnnouncements Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createAnnouncement(req, res) {
  try {
    const { judul, isi, kategori, status } = req.body;
    if (!judul || !isi) return res.status(400).json({ success: false, message: 'Judul dan isi wajib diisi.' });
    const result = await pool.query(
      `INSERT INTO announcements (judul, isi, kategori, status, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [judul, isi, kategori || 'Umum', status || 'publish', req.user.id]
    );
    const p = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Membuat pengumuman "${ringkas(p.judul)}" — kategori ${p.kategori || '-'}, status ${p.status}`);

    return res.status(201).json({ success: true, message: 'Pengumuman berhasil dibuat.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateAnnouncement Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateAnnouncement(req, res) {
  try {
    const { id } = req.params;
    const { judul, isi, kategori, status } = req.body;
    const result = await pool.query(
      `UPDATE announcements SET judul = COALESCE($1, judul), isi = COALESCE($2, isi), kategori = COALESCE($3, kategori), status = COALESCE($4, status), updated_at = NOW() WHERE id = $5 RETURNING *`,
      [judul, isi, kategori, status, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengumuman tidak ditemukan.' });
    const p = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah pengumuman "${ringkas(p.judul)}" — status ${p.status}, isi kini: "${ringkas(p.isi, 100)}"`);

    return res.status(200).json({ success: true, message: 'Pengumuman berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateAnnouncement Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteAnnouncement(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM announcements WHERE id = $1 RETURNING id, judul', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengumuman tidak ditemukan.' });
    await logActivity(req, TIPE.DELETE, `Menghapus pengumuman "${ringkas(result.rows[0].judul)}"`);

    return res.status(200).json({ success: true, message: 'Pengumuman berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteAnnouncement Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getAnnouncements, createAnnouncement, updateAnnouncement, deleteAnnouncement };
