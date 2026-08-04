const { pool } = require('../config/database');

// ======================== JADWAL SISKAMLING ========================

async function getSchedules(req, res) {
  try {
    const result = await pool.query(
      `SELECT s.*, u.nama AS created_by_nama 
       FROM patrol_schedules s 
       LEFT JOIN users u ON s.created_by = u.id 
       ORDER BY s.id ASC`
    );
    return res.status(200).json({ success: true, data: result.rows });
  } catch (err) {
    console.error('GetSchedules Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createSchedule(req, res) {
  try {
    const { hari, shift, petugas_warga, keterangan } = req.body;
    if (!hari || !petugas_warga) {
      return res.status(400).json({ success: false, message: 'Hari dan nama petugas ronda wajib diisi.' });
    }

    const result = await pool.query(
      `INSERT INTO patrol_schedules (hari, shift, petugas_warga, keterangan, created_by)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [hari, shift || 'Shift Malam (22:00 - 04:00)', petugas_warga, keterangan || null, req.user.id]
    );

    return res.status(201).json({ success: true, message: 'Jadwal ronda berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateSchedule Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateSchedule(req, res) {
  try {
    const { id } = req.params;
    const { hari, shift, petugas_warga, keterangan } = req.body;

    const result = await pool.query(
      `UPDATE patrol_schedules 
       SET hari = COALESCE($1, hari), 
           shift = COALESCE($2, shift), 
           petugas_warga = COALESCE($3, petugas_warga), 
           keterangan = COALESCE($4, keterangan),
           updated_at = NOW()
       WHERE id = $5 RETURNING *`,
      [hari, shift, petugas_warga, keterangan, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jadwal ronda tidak ditemukan.' });
    }

    return res.status(200).json({ success: true, message: 'Jadwal ronda berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateSchedule Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteSchedule(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM patrol_schedules WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jadwal ronda tidak ditemukan.' });
    }
    return res.status(200).json({ success: true, message: 'Jadwal ronda berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteSchedule Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== ABSENSI POS RONDA ========================

async function getAttendances(req, res) {
  try {
    const { tanggal } = req.query;
    let query = `
      SELECT a.*, u.username, u.role
      FROM patrol_attendances a
      LEFT JOIN users u ON a.user_id = u.id
      WHERE 1=1
    `;
    const params = [];

    if (tanggal) {
      params.push(tanggal);
      query += ` AND a.tanggal = $${params.length}`;
    }

    query += ' ORDER BY a.waktu_scan DESC LIMIT 100';

    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, data: result.rows });
  } catch (err) {
    console.error('GetAttendances Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function submitAttendance(req, res) {
  try {
    const { schedule_id, kode_qr, lokasi_pos, catatan } = req.body;
    const userId = req.user.id;
    const namaPetugas = req.user.nama || req.user.username || 'Warga';

    // Verifikasi kode QR jika ada
    if (kode_qr && kode_qr !== 'POS_RONDA_OFFICIAL_QR' && kode_qr !== 'POS_RONDA_RT05_OFFICIAL_QR') {
      return res.status(400).json({ success: false, message: 'Kode QR Pos Ronda tidak valid!' });
    }

    // Cek apakah sudah absen hari ini
    const today = new Date().toISOString().split('T')[0];
    const checkExisting = await pool.query(
      'SELECT id FROM patrol_attendances WHERE user_id = $1 AND tanggal = $2',
      [userId, today]
    );

    if (checkExisting.rows.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Anda sudah melakukan absensi ronda hari ini!',
      });
    }

    const now = new Date();
    const hours = now.getHours();
    // Tepat waktu jika diisi antara jam 20:00 - 05:00
    const status = (hours >= 20 || hours < 5) ? 'Tepat Waktu' : 'Hadir Terlambat';

    const result = await pool.query(
      `INSERT INTO patrol_attendances (schedule_id, user_id, nama_petugas, tanggal, waktu_scan, lokasi_pos, status, catatan)
       VALUES ($1, $2, $3, $4, NOW(), $5, $6, $7) RETURNING *`,
      [schedule_id || null, userId, namaPetugas, today, lokasi_pos || 'Pos Ronda Utama', status, catatan || 'Absensi via QR Code Pos Ronda']
    );

    return res.status(201).json({
      success: true,
      message: 'Absensi ronda berhasil dicatat. Terima kasih atas partisipasinya!',
      data: result.rows[0],
    });
  } catch (err) {
    console.error('SubmitAttendance Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getPosRondaQr(req, res) {
  try {
    return res.status(200).json({
      success: true,
      data: {
        pos_name: 'Pos Ronda Utama Siskamling',
        qr_code_data: 'POS_RONDA_OFFICIAL_QR',
        secret_pin: 'RONDA',
        generated_at: new Date().toISOString(),
      },
    });
  } catch (err) {
    console.error('GetPosRondaQr Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getSchedules,
  createSchedule,
  updateSchedule,
  deleteSchedule,
  getAttendances,
  submitAttendance,
  getPosRondaQr,
};
