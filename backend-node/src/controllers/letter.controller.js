const { pool } = require('../config/database');

async function getLetters(req, res) {
  try {
    const { status, user_id } = req.query;
    let query = `SELECT l.*, u.nama AS nama_pemohon, u.alamat, u.no_kk, a.nama AS approved_by_nama
      FROM letters l JOIN users u ON l.user_id = u.id LEFT JOIN users a ON l.approved_by = a.id WHERE 1=1`;
    const params = [];
    if (req.user.role === 'warga') { params.push(req.user.id); query += ` AND l.user_id = $${params.length}`; }
    else if (user_id) { params.push(user_id); query += ` AND l.user_id = $${params.length}`; }
    if (status) { params.push(status); query += ` AND l.status = $${params.length}`; }
    query += ' ORDER BY l.created_at DESC';
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetLetters Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createLetter(req, res) {
  try {
    const { jenis_surat, keperluan } = req.body;
    if (!jenis_surat || !keperluan) return res.status(400).json({ success: false, message: 'jenis_surat dan keperluan wajib diisi.' });
    const result = await pool.query(
      `INSERT INTO letters (user_id, jenis_surat, keperluan) VALUES ($1, $2, $3) RETURNING *`,
      [req.user.id, jenis_surat, keperluan]
    );
    return res.status(201).json({ success: true, message: 'Pengajuan surat berhasil dikirim.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateLetter Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateLetterStatus(req, res) {
  try {
    const { id } = req.params;
    const { status, response_note } = req.body;
    const validStatus = ['diproses', 'disetujui', 'ditolak'];
    if (!status || !validStatus.includes(status)) return res.status(400).json({ success: false, message: `status harus salah satu dari: ${validStatus.join(', ')}` });
    const result = await pool.query(
      `UPDATE letters SET status = $1, approved_by = $2, response_note = $3, tanggal_respon = NOW(), updated_at = NOW() WHERE id = $4 RETURNING *`,
      [status, req.user.id, response_note || null, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Surat tidak ditemukan.' });

    const updatedLetter = result.rows[0];

    // Panggil WhatsApp Service saat status disetujui / ditolak (Async)
    const { sendLetterApprovedWA, sendWA } = require('../services/whatsapp.service');
    (async () => {
      const userRes = await pool.query('SELECT nama, no_hp FROM users WHERE id = $1', [updatedLetter.user_id]);
      if (userRes.rows.length > 0) {
        const u = userRes.rows[0];
        if (status === 'disetujui') {
          await sendLetterApprovedWA({
            userNama: u.nama,
            noHp: u.no_hp,
            jenisSurat: updatedLetter.jenis_surat,
          });
        } else if (status === 'ditolak') {
          await sendWA({
            target: u.no_hp,
            message: `📄 *PERMOHONAN SURAT DITOLAK*\n\nHalo Bpk/Ibu *${u.nama}*,\n\nPermohonan *${updatedLetter.jenis_surat}* Anda belum dapat disetujui.\nCatatan: ${response_note || 'Harap lengkapi persyaratan'}\n\n— *Pengurus RT 05*`,
          });
        }
      }
    })().catch((e) => console.log('ℹ️ Catatan WA Surat:', e.message));

    return res.status(200).json({ success: true, message: `Surat berhasil di-${status}.`, data: updatedLetter });
  } catch (err) {
    console.error('UpdateLetterStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getLetters, createLetter, updateLetterStatus };
