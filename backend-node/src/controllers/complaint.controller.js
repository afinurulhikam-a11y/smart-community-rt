const { pool } = require('../config/database');

async function getComplaints(req, res) {
  try {
    const { status, search } = req.query;
    let query = `SELECT c.*, u.nama AS nama_pengirim, r.nama AS responded_by_nama FROM complaints c JOIN users u ON c.user_id = u.id LEFT JOIN users r ON c.responded_by = r.id WHERE 1=1`;
    const params = [];

    // Warga hanya melihat pengaduannya sendiri — pola yang sama dengan
    // getLetters. Aduan kerap memuat keluhan tentang tetangga, jadi membukanya
    // ke seluruh warga menimbulkan masalah nyata. Pengurus tetap melihat semua.
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      query += ` AND c.user_id = $${params.length}`;
    }

    if (status && status !== 'Semua') { params.push(status); query += ` AND c.status = $${params.length}`; }
    if (search) { params.push(`%${search}%`); query += ` AND (c.judul ILIKE $${params.length} OR c.kode_tiket ILIKE $${params.length} OR u.nama ILIKE $${params.length})`; }
    query += ' ORDER BY c.created_at DESC';
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetComplaints Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createComplaint(req, res) {
  try {
    const { judul, deskripsi, kategori } = req.body;
    if (!judul) return res.status(400).json({ success: false, message: 'Judul wajib diisi.' });
    const kode_tiket = `TKT${new Date().toISOString().slice(0,10).replace(/-/g,'')}${String(Date.now()).slice(-3)}`;
    const result = await pool.query(
      `INSERT INTO complaints (kode_tiket, user_id, judul, deskripsi, kategori) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [kode_tiket, req.user.id, judul, deskripsi || null, kategori || null]
    );
    return res.status(201).json({ success: true, message: 'Pengaduan berhasil dikirim.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateComplaint Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateComplaintStatus(req, res) {
  try {
    const { id } = req.params;
    const { status, response } = req.body;
    const validStatus = ['Menunggu', 'Diproses', 'Selesai', 'Ditolak'];
    if (!status || !validStatus.includes(status)) return res.status(400).json({ success: false, message: `Status harus salah satu dari: ${validStatus.join(', ')}` });
    const result = await pool.query(
      `UPDATE complaints SET status = $1, response = $2, responded_by = $3, updated_at = NOW() WHERE id = $4 RETURNING *`,
      [status, response || null, req.user.id, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengaduan tidak ditemukan.' });
    return res.status(200).json({ success: true, message: `Status pengaduan berhasil diubah ke "${status}".`, data: result.rows[0] });
  } catch (err) {
    console.error('UpdateComplaintStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteComplaint(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM complaints WHERE id = $1 RETURNING id, kode_tiket', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengaduan tidak ditemukan.' });
    return res.status(200).json({ success: true, message: 'Pengaduan berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteComplaint Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getComplaints, createComplaint, updateComplaintStatus, deleteComplaint };
