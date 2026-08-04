const { pool } = require('../config/database');
const { logActivity } = require('../services/log.service');

async function getActivityLogs(req, res) {
  try {
    const { limit = 25, search, tipe } = req.query;
    let query = `SELECT id, user_id, user_nama, user_role, tipe, aktivitas, ip_address, created_at FROM activity_logs WHERE 1=1`;
    const params = [];

    if (tipe && tipe !== 'Semua') {
      params.push(tipe);
      query += ` AND tipe = $${params.length}`;
    }

    if (search) {
      params.push(`%${search}%`);
      query += ` AND (aktivitas ILIKE $${params.length} OR user_nama ILIKE $${params.length} OR ip_address ILIKE $${params.length})`;
    }

    query += ' ORDER BY created_at DESC';

    const parsedLimit = parseInt(limit, 10);
    if (!isNaN(parsedLimit) && parsedLimit > 0) {
      params.push(parsedLimit);
      query += ` LIMIT $${params.length}`;
    }

    const result = await pool.query(query, params);

    return res.status(200).json({
      success: true,
      count: result.rows.length,
      data: result.rows,
    });
  } catch (err) {
    console.error('GetActivityLogs Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function clearActivityLogs(req, res) {
  try {
    await pool.query('DELETE FROM activity_logs');
    await logActivity(req, 'DELETE', 'Membersihkan seluruh log aktivitas sistem');
    return res.status(200).json({ success: true, message: 'Seluruh log aktivitas sistem berhasil dibersihkan.' });
  } catch (err) {
    console.error('ClearActivityLogs Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getActivityLogs, clearActivityLogs };
