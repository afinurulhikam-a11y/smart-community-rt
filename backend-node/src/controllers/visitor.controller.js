const { pool } = require('../config/database');

async function getVisitors(req, res) {
  try {
    const { status, tipe, search, tanggal } = req.query;
    let query = `SELECT v.*, u.nama AS created_by_nama FROM visitors v LEFT JOIN users u ON v.created_by = u.id WHERE 1=1`;
    const params = [];
    if (status && status !== 'Semua Status') { params.push(status); query += ` AND v.status = $${params.length}`; }
    if (tipe && tipe !== 'Semua Tipe') { params.push(tipe); query += ` AND v.tipe_keperluan = $${params.length}`; }
    if (tanggal) { params.push(tanggal); query += ` AND v.jam_masuk::DATE = $${params.length}::DATE`; }
    if (search) { params.push(`%${search}%`); query += ` AND (v.nama_tamu ILIKE $${params.length} OR v.blok_tujuan ILIKE $${params.length} OR v.plat_nomor ILIKE $${params.length})`; }
    query += ' ORDER BY v.jam_masuk DESC';
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetVisitors Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getVisitorStats(req, res) {
  try {
    const today = new Date().toISOString().split('T')[0];
    const todayResult = await pool.query('SELECT COUNT(*) as count FROM visitors WHERE jam_masuk::DATE = $1::DATE', [today]);
    const insideResult = await pool.query("SELECT COUNT(*) as count FROM visitors WHERE status = 'Di Dalam'");
    const stayingResult = await pool.query("SELECT COUNT(*) as count FROM visitors WHERE tipe_keperluan = 'Menginap' AND status = 'Di Dalam'");
    const totalResult = await pool.query('SELECT COUNT(*) as count FROM visitors');
    return res.status(200).json({
      success: true,
      data: {
        tamu_hari_ini: parseInt(todayResult.rows[0].count),
        sedang_di_dalam: parseInt(insideResult.rows[0].count),
        tamu_menginap: parseInt(stayingResult.rows[0].count),
        total_semua: parseInt(totalResult.rows[0].count),
      }
    });
  } catch (err) {
    console.error('GetVisitorStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createVisitor(req, res) {
  try {
    const { nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan } = req.body;

    // Validasi: semua kolom wajib diisi
    const kosong = [];
    if (!nama_tamu?.trim()) kosong.push('Nama Tamu');
    if (!no_hp_tamu?.trim()) kosong.push('No. HP Tamu');
    if (!blok_tujuan?.trim()) kosong.push('Blok Tujuan');
    if (!no_hp_tujuan?.trim()) kosong.push('No. HP Warga Tujuan');
    if (!detail_keperluan?.trim()) kosong.push('Detail Keperluan');
    if (!plat_nomor?.trim()) kosong.push('Plat Nomor');

    if (kosong.length > 0) {
      return res.status(400).json({
        success: false,
        message: `Kolom berikut wajib diisi: ${kosong.join(', ')}.`,
      });
    }

    const result = await pool.query(
      `INSERT INTO visitors (nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [nama_tamu.trim(), no_hp_tamu.trim(), blok_tujuan.trim(), no_hp_tujuan.trim(), tipe_keperluan || 'Kunjungan', detail_keperluan.trim(), plat_nomor.trim(), jenis_kendaraan || null, req.user.id]
    );
    return res.status(201).json({ success: true, message: 'Tamu berhasil diregistrasi.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function checkoutVisitor(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query(
      "UPDATE visitors SET status = 'Checkout', jam_keluar = NOW() WHERE id = $1 AND status = 'Di Dalam' RETURNING *", [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Tamu tidak ditemukan atau sudah checkout.' });
    return res.status(200).json({ success: true, message: 'Checkout berhasil.', data: result.rows[0] });
  } catch (err) {
    console.error('CheckoutVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteVisitor(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM visitors WHERE id = $1 RETURNING id, nama_tamu', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Data tamu tidak ditemukan.' });
    return res.status(200).json({ success: true, message: 'Data tamu berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getVisitors, getVisitorStats, createVisitor, checkoutVisitor, deleteVisitor };
