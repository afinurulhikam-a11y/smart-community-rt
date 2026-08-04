const { pool } = require('../config/database');
const { broadcast } = require('../config/websocket');

async function triggerAlarm(req, res) {
  try {
    const { message, latitude, longitude, pin } = req.body;

    // Verifikasi 2-Langkah: PIN Keamanan (Default: 1234)
    if (!pin || pin.toString().trim() !== '1234') {
      return res.status(403).json({
        success: false,
        message: 'PIN Keamanan tidak valid. Pemicuan alarm dibatalkan.',
      });
    }

    const userResult = await pool.query('SELECT id, nama, no_hp, alamat FROM users WHERE id = $1', [req.user.id]);
    const user = (userResult.rows && userResult.rows.length > 0)
      ? userResult.rows[0]
      : { id: req.user.id, nama: req.user?.nama || 'Admin RT', no_hp: req.user?.no_hp || '-', alamat: req.user?.alamat || '-' };

    const result = await pool.query(
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude) VALUES ($1, $2, $3, $4) RETURNING *`,
      [req.user.id, message || 'DARURAT! Warga membutuhkan bantuan!', latitude || null, longitude || null]
    );
    const alert = result.rows[0];
    const sentCount = broadcast({
      type: 'ALARM_ON',
      event: 'emergency_alert',
      alert_id: alert.id,
      user_id: user.id,
      nama: user.nama || 'Warga/Admin',
      no_hp: user.no_hp || '-',
      alamat: user.alamat || '-',
      message: alert.message,
      latitude: alert.latitude,
      longitude: alert.longitude,
      timestamp: alert.created_at,
    });

    // Panggil WhatsApp Notification Service (Async)
    const { sendEmergencyWA } = require('../services/whatsapp.service');
    sendEmergencyWA({
      userNama: user.nama,
      alamat: user.alamat,
      noHp: user.no_hp,
      tipeEmergency: message || 'Sinyal Darurat Panic Button',
    }).catch((e) => console.log('ℹ️ Catatan WA Alarm:', e.message));

    return res.status(201).json({
      success: true,
      message: `Sinyal darurat berhasil dikirim ke ${sentCount} perangkat yang terhubung.`,
      data: { alert, broadcast_count: sentCount },
    });
  } catch (err) {
    console.error('TriggerAlarm Error:', err.message);
    return res.status(500).json({ success: false, message: `Gagal mengirim sinyal darurat: ${err.message}` });
  }
}

async function dismissAlarm(req, res) {
  try {
    const { id } = req.params;
    const { pin } = req.body;

    // Verifikasi 2-Langkah: PIN Keamanan (Default: 1234)
    if (!pin || pin.toString().trim() !== '1234') {
      return res.status(403).json({
        success: false,
        message: 'PIN Keamanan tidak valid. Penutupan status darurat dibatalkan.',
      });
    }

    // Pastikan user ID pelaksana valid di tabel users untuk menghindari FK violation
    const userCheck = await pool.query('SELECT id, nama FROM users WHERE id = $1', [req.user.id]);
    const validUserId = (userCheck.rows && userCheck.rows.length > 0) ? req.user.id : null;
    const adminName = (userCheck.rows && userCheck.rows.length > 0) ? userCheck.rows[0].nama : (req.user?.nama || 'Administrator');

    const result = await pool.query(
      `UPDATE emergency_alerts SET status = 'dismissed', dismissed_by = $1, dismissed_at = NOW() WHERE id = $2 AND status = 'active' RETURNING *`,
      [validUserId, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Alert aktif tidak ditemukan atau sudah diselesaikan.' });
    }

    const sentCount = broadcast({
      type: 'ALARM_OFF',
      event: 'emergency_dismissed',
      alert_id: id,
      dismissed_by: validUserId,
      dismissed_by_nama: adminName,
      timestamp: new Date().toISOString(),
    });
    return res.status(200).json({
      success: true,
      message: `Status darurat berhasil diselesaikan. Broadcast ke ${sentCount} perangkat.`,
      data: { ...result.rows[0], dismissed_by_nama: adminName },
    });
  } catch (err) {
    console.error('DismissAlarm Error:', err.message);
    return res.status(500).json({ success: false, message: `Gagal menyelesaikan status darurat: ${err.message}` });
  }
}

async function getAlerts(req, res) {
  try {
    const { status } = req.query;
    let query = `SELECT ea.*, 
      COALESCE(u.nama, 'Administrator') AS nama_warga, 
      COALESCE(u.alamat, '') AS alamat, 
      u.no_hp, 
      COALESCE(d.nama, CASE WHEN ea.dismissed_by IS NOT NULL THEN 'Pengurus RT' ELSE NULL END) AS dismissed_by_nama
      FROM emergency_alerts ea 
      LEFT JOIN users u ON ea.user_id = u.id 
      LEFT JOIN users d ON ea.dismissed_by = d.id 
      WHERE 1=1`;
    const params = [];
    if (status) { params.push(status); query += ` AND ea.status = $${params.length}`; }
    query += ' ORDER BY ea.created_at DESC LIMIT 50';
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetAlerts Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getActiveAlerts(req, res) {
  try {
    const result = await pool.query(
      `SELECT ea.*, 
        COALESCE(u.nama, 'Administrator') AS nama_warga, 
        COALESCE(u.alamat, '') AS alamat, 
        u.no_hp 
        FROM emergency_alerts ea 
        LEFT JOIN users u ON ea.user_id = u.id 
        WHERE ea.status = 'active' 
        ORDER BY ea.created_at DESC`
    );
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetActiveAlerts Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { triggerAlarm, dismissAlarm, getAlerts, getActiveAlerts };
