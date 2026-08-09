const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const { broadcast } = require('../config/websocket');

async function triggerAlarm(req, res) {
  try {
    const { message, latitude, longitude, pin } = req.body;

    // Verifikasi 2-Langkah: PIN Keamanan (Default: 1234 bila tidak disetel)
    const pinDarurat = (process.env.EMERGENCY_PIN && process.env.EMERGENCY_PIN.trim() !== '')
      ? process.env.EMERGENCY_PIN.trim()
      : '1234';

    if (!pin || pin.toString().trim() !== pinDarurat) {
      return res.status(403).json({
        success: false,
        message: 'PIN Keamanan tidak valid. Pemicuan alarm dibatalkan.',
      });
    }

    const userResult = await pool.query('SELECT id, nama, no_hp, alamat FROM users WHERE id = $1', [req.user.id]);
    const validUserId = (userResult.rows && userResult.rows.length > 0) ? req.user.id : null;
    const user = (userResult.rows && userResult.rows.length > 0)
      ? userResult.rows[0]
      : { id: validUserId, nama: req.user?.nama || 'Admin RT', no_hp: req.user?.no_hp || '-', alamat: req.user?.alamat || '-' };

    const result = await pool.query(
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude) VALUES ($1, $2, $3, $4) RETURNING *`,
      [validUserId, message || 'DARURAT! Warga membutuhkan bantuan!', latitude || null, longitude || null]
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
    }, {
      // Muatan untuk perangkat tanpa akun (ESP32). Sengaja TANPA nama, nomor
      // telepon, alamat, koordinat, maupun pesan bebas dari pelapor.
      //
      // Alat itu hanya perlu tahu bahwa alarm menyala — buzzer dan LED tidak
      // membaca nama siapa pun. Sementara koneksi tanpa token bisa dibuka siapa
      // saja yang menjangkau server ini, jadi apa pun yang dikirim ke sana
      // harus dianggap terbaca publik.
      //
      // Firmware sudah aman terhadap ini: ia membaca `type` untuk memicu alarm,
      // dan field lainnya punya nilai cadangan (`| "Tidak diketahui"`).
      type: 'ALARM_ON',
      alert_id: alert.id,
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

    // Alarm palsu maupun sungguhan sama-sama harus berjejak: yang pertama
    // untuk menindak penyalahgunaan tombol panik, yang kedua sebagai bukti
    // waktu kejadian.
    await logActivity(req, TIPE.DARURAT, `Memicu ALARM DARURAT — "${ringkas(alert.message, 80)}"`);

    return res.status(201).json({
      success: true,
      message: `Sinyal darurat berhasil dikirim ke ${sentCount} perangkat yang terhubung.`,
      data: { alert, broadcast_count: sentCount },
    });
  } catch (err) {
    console.error('TriggerAlarm Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal mengirim sinyal darurat. Coba lagi.' });
  }
}

async function dismissAlarm(req, res) {
  try {
    const { id } = req.params;
    const { pin } = req.body;

    // Verifikasi 2-Langkah: PIN Keamanan (Default: 1234 bila tidak disetel)
    const pinDarurat = (process.env.EMERGENCY_PIN && process.env.EMERGENCY_PIN.trim() !== '')
      ? process.env.EMERGENCY_PIN.trim()
      : '1234';

    if (!pin || pin.toString().trim() !== pinDarurat) {
      return res.status(403).json({
        success: false,
        message: 'PIN Keamanan tidak valid. Penutupan status darurat dibatalkan.',
      });
    }

    // Pastikan alert ada dan periksa otorisasi (Pemilik alarm ATAU Pengurus/Admin)
    const alertCheck = await pool.query('SELECT id, user_id, status FROM emergency_alerts WHERE id = $1', [id]);
    if (alertCheck.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Alert tidak ditemukan.' });
    }

    const alertItem = alertCheck.rows[0];
    const isOwner = alertItem.user_id === req.user.id;
    const isPengurus = ['admin', 'ketua_rt', 'sekretaris', 'bendahara', 'pengurus_rt'].includes(req.user.role);

    if (!isOwner && !isPengurus) {
      return res.status(403).json({
        success: false,
        message: 'Anda tidak memiliki hak untuk mematikan sinyal darurat milik warga lain.',
      });
    }

    // Pastikan user ID pelaksana valid di tabel users untuk menghindari FK violation
    const userCheck = await pool.query('SELECT id, nama FROM users WHERE id = $1', [req.user.id]);
    const validUserId = (userCheck.rows && userCheck.rows.length > 0) ? req.user.id : null;
    const adminName = (userCheck.rows && userCheck.rows.length > 0) ? userCheck.rows[0].nama : (req.user?.nama || 'Pengurus/Pelapor');

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
    }, {
      // Perangkat WAJIB menerima perintah mati. Menahannya berarti buzzer terus
      // berbunyi setelah pengurus menekan "Selesaikan" — kegagalan yang jauh
      // lebih terasa daripada kebocoran mana pun. Nama yang mematikan tidak
      // ikut dikirim; alat tidak membutuhkannya.
      type: 'ALARM_OFF',
      alert_id: id,
      timestamp: new Date().toISOString(),
    });
    // Siapa yang mematikan alarm, dan kapan. Ini pertanyaan pertama bila
    // kelak ada keluhan "alarm dimatikan padahal keadaan belum aman".
    await logActivity(req, TIPE.DARURAT, `Mematikan alarm darurat (id ${id})`);

    return res.status(200).json({
      success: true,
      message: `Status darurat berhasil diselesaikan. Broadcast ke ${sentCount} perangkat.`,
      data: { ...result.rows[0], dismissed_by_nama: adminName },
    });
  } catch (err) {
    console.error('DismissAlarm Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal menyelesaikan status darurat. Coba lagi.' });
  }
}

async function getAlerts(req, res) {
  try {
    const { status, page, limit } = req.query;

    const queryParams = [];
    let whereClause = 'WHERE 1=1';

    if (status) {
      queryParams.push(status);
      whereClause += ` AND ea.status = $${queryParams.length}`;
    }

    let limitNum = parseInt(limit, 10);
    let pageNum = parseInt(page, 10);
    const usePagination = !isNaN(limitNum) && limitNum > 0;

    if (usePagination) {
      if (isNaN(pageNum) || pageNum < 1) pageNum = 1;
    }

    const countResult = await pool.query(
      `SELECT COUNT(*) FROM emergency_alerts ea ${whereClause}`,
      queryParams
    );
    const totalData = parseInt(countResult.rows[0].count, 10);

    let query = `SELECT ea.*, 
      COALESCE(u.nama, 'Administrator') AS nama_warga, 
      COALESCE(u.alamat, '') AS alamat, 
      u.no_hp, 
      COALESCE(d.nama, CASE WHEN ea.dismissed_by IS NOT NULL THEN 'Pengurus RT' ELSE NULL END) AS dismissed_by_nama
      FROM emergency_alerts ea 
      LEFT JOIN users u ON ea.user_id = u.id 
      LEFT JOIN users d ON ea.dismissed_by = d.id 
      ${whereClause}
      ORDER BY ea.created_at DESC`;

    if (usePagination) {
      const offset = (pageNum - 1) * limitNum;
      queryParams.push(limitNum);
      query += ` LIMIT $${queryParams.length}`;
      queryParams.push(offset);
      query += ` OFFSET $${queryParams.length}`;
    } else {
      query += ' LIMIT 50';
    }

    const result = await pool.query(query, queryParams);

    const responseData = {
      success: true,
      count: result.rows.length,
      data: result.rows,
    };

    if (usePagination) {
      responseData.pagination = {
        total_data: totalData,
        total_pages: Math.ceil(totalData / limitNum) || 1,
        current_page: pageNum,
        per_page: limitNum,
      };
    }

    return res.status(200).json(responseData);
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
