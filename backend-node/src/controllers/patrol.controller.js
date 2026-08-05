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
    const { hari, tanggal, shift, petugas_warga, keterangan } = req.body;
    if (!hari || !petugas_warga) {
      return res.status(400).json({ success: false, message: 'Hari dan nama petugas ronda wajib diisi.' });
    }

    const result = await pool.query(
      `INSERT INTO patrol_schedules (hari, tanggal, shift, petugas_warga, keterangan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [hari, tanggal || null, shift || 'Shift Malam (22:00 - 04:00)', petugas_warga, keterangan || null, req.user.id]
    );

    return res.status(201).json({ success: true, message: 'Jadwal ronda berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateSchedule Error:', err.message);
    return res.status(500).json({ success: false, message: err.message || 'Terjadi kesalahan server.' });
  }
}

async function updateSchedule(req, res) {
  try {
    const { id } = req.params;
    const { hari, tanggal, shift, petugas_warga, keterangan } = req.body;

    const result = await pool.query(
      `UPDATE patrol_schedules 
       SET hari = COALESCE($1, hari), 
           tanggal = COALESCE($2, tanggal),
           shift = COALESCE($3, shift), 
           petugas_warga = COALESCE($4, petugas_warga), 
           keterangan = COALESCE($5, keterangan),
           updated_at = NOW()
       WHERE id = $6 RETURNING *`,
      [hari, tanggal, shift, petugas_warga, keterangan, id]
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

function parseShiftTimes(shiftStr) {
  if (!shiftStr) return { startHour: 20, startMin: 0, endHour: 4, endMin: 0, startStr: '20:00', endStr: '04:00' };
  const match = shiftStr.match(/(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})/);
  if (match) {
    const sH = parseInt(match[1], 10);
    const sM = parseInt(match[2], 10);
    const eH = parseInt(match[3], 10);
    const eM = parseInt(match[4], 10);
    return {
      startHour: sH,
      startMin: sM,
      endHour: eH,
      endMin: eM,
      startStr: `${sH.toString().padStart(2, '0')}:${sM.toString().padStart(2, '0')}`,
      endStr: `${eH.toString().padStart(2, '0')}:${eM.toString().padStart(2, '0')}`,
    };
  }
  return { startHour: 20, startMin: 0, endHour: 4, endMin: 0, startStr: '20:00', endStr: '04:00' };
}

async function submitAttendance(req, res) {
  try {
    const { schedule_id, kode_qr, tipe_absen, lokasi_pos, catatan, foto_url } = req.body;
    const userId = req.user.id;
    const namaPetugas = req.user.nama || req.user.username || 'Warga';

    // Verifikasi kode QR jika ada
    if (kode_qr && kode_qr !== 'POS_RONDA_OFFICIAL_QR') {
      return res.status(400).json({ success: false, message: 'Kode QR Pos Ronda tidak valid!' });
    }

    // Cari jadwal yang berlaku untuk mendapatkan jam shift
    let shiftStr = 'Shift Malam (20:00 - 04:00)';
    if (schedule_id) {
      const schedRes = await pool.query('SELECT shift FROM patrol_schedules WHERE id = $1', [schedule_id]);
      if (schedRes.rows.length > 0) shiftStr = schedRes.rows[0].shift;
    } else {
      const todaySched = await pool.query(
        'SELECT shift FROM patrol_schedules WHERE tanggal = CURRENT_DATE OR created_at::date = CURRENT_DATE LIMIT 1'
      );
      if (todaySched.rows.length > 0) shiftStr = todaySched.rows[0].shift;
    }

    const { startHour, startMin, endHour, endMin, startStr, endStr } = parseShiftTimes(shiftStr);
    const now = new Date();
    const currentMins = now.getHours() * 60 + now.getMinutes();

    // Hitung menit mulai (toleransi awal 30 menit sebelum jam shift)
    const startMins = startHour * 60 + startMin;
    const earliestStartMins = startMins - 30; // Boleh absen 30 menit sebelum jam dimulainya shift

    // Hitung menit selesai
    const endMins = endHour * 60 + endMin;

    const isOvernight = endMins <= startMins; // Misal 22:00 s.d. 04:00

    const today = new Date().toISOString().split('T')[0];
    const existing = await pool.query(
      `SELECT * FROM patrol_attendances WHERE user_id = $1 AND tanggal = $2 ORDER BY created_at DESC LIMIT 1`,
      [userId, today]
    );

    const hasActiveCheckin = existing.rows.length > 0 && !existing.rows[0].waktu_pulang;

    // Jika tipe_absen dispesifikasikan 'Pulang' atau sudah ada aktif check-in hari ini:
    if (tipe_absen === 'Pulang' || (hasActiveCheckin && tipe_absen !== 'Masuk')) {
      if (!hasActiveCheckin) {
        return res.status(400).json({
          success: false,
          message: 'Anda belum melakukan Absen Masuk Tugas ronda hari ini!',
        });
      }

      // Validasi Jam Pulang: Wajib mencapai/melewati jam selesai shift
      let canCheckout = false;
      if (isOvernight) {
        // Jika shift malam melintasi tengah malam (misal 22:00 - 04:00):
        // Boleh pulang jika jam sekarang sudah masuk ke dini hari (setelah midnight & >= endMins)
        // atau jika sudah melewati jam 04:00 pagi (misal jam 04:15, 05:00, 06:00, dll)
        if (now.getHours() >= endHour && now.getHours() < startHour) {
          canCheckout = true;
        }
      } else {
        if (currentMins >= endMins) {
          canCheckout = true;
        }
      }

      // Jika belum waktunya pulang (dan bukan admin bypass):
      if (!canCheckout && req.user.role !== 'admin') {
        return res.status(400).json({
          success: false,
          message: `Absen Pulang belum dapat dilakukan. Tugas ronda Anda berakhir pada pukul ${endStr} WIB!`,
        });
      }

      const activeRow = existing.rows[0];
      const updated = await pool.query(
        `UPDATE patrol_attendances
         SET waktu_pulang = NOW(),
             status = 'Selesai Tugas',
             catatan = COALESCE($1, catatan),
             foto_url = COALESCE($2, foto_url)
         WHERE id = $3 RETURNING *`,
        [catatan || 'Telah menyelesaikan tugas ronda malam.', foto_url || null, activeRow.id]
      );

      return res.status(200).json({
        success: true,
        message: 'Absensi Selesai Tugas berhasil dicatat. Terima kasih atas pengabdian Anda!',
        data: updated.rows[0],
      });
    } else {
      // Absen Masuk Tugas
      if (hasActiveCheckin) {
        return res.status(400).json({
          success: false,
          message: 'Anda sedang dalam masa tugas ronda! Gunakan Absen Selesai Tugas untuk mengakhiri.',
        });
      }

      // Validasi Jam Masuk: Boleh mulai dari 30 menit sebelum startStr sampai jam bertugas
      let canCheckin = false;
      if (isOvernight) {
        if (currentMins >= earliestStartMins || now.getHours() < endHour) {
          canCheckin = true;
        }
      } else {
        if (currentMins >= earliestStartMins) {
          canCheckin = true;
        }
      }

      if (!canCheckin && req.user.role !== 'admin') {
        return res.status(400).json({
          success: false,
          message: `Absen Masuk belum dibuka. Jadwal ronda Anda dimulai pukul ${startStr} WIB!`,
        });
      }

      const result = await pool.query(
        `INSERT INTO patrol_attendances (schedule_id, user_id, nama_petugas, tanggal, tipe_absen, waktu_scan, waktu_masuk, lokasi_pos, status, catatan, foto_url)
         VALUES ($1, $2, $3, $4, 'Masuk', NOW(), NOW(), $5, 'Aktif Ronda', $6, $7) RETURNING *`,
        [schedule_id || null, userId, namaPetugas, today, lokasi_pos || 'Pos Ronda Utama', catatan || 'Absen Masuk Pos Ronda', foto_url || null]
      );

      return res.status(201).json({
        success: true,
        message: 'Absen Masuk Tugas ronda berhasil dicatat. Selamat bertugas!',
        data: result.rows[0],
      });
    }
  } catch (err) {
    console.error('SubmitAttendance Error:', err.message);
    return res.status(500).json({ success: false, message: err.message || 'Terjadi kesalahan server.' });
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
