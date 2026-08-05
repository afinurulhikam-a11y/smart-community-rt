const { pool } = require('../config/database');
const crypto = require('crypto');

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

function formatNamaPetugas(input) {
  if (!input) return '';
  // Pisahkan berdasarkan KOMA untuk membedakan orang yang berbeda
  const orangList = input.split(',').map(o => o.trim()).filter(Boolean);
  
  return orangList
    .map(orang => {
      // Untuk nama 1 orang, kapitalsasi setiap kata tanpa memisahkannya
      return orang
        .split(/\s+/)
        .map(kata => kata.charAt(0).toUpperCase() + kata.slice(1).toLowerCase())
        .join(' ');
    })
    .join(', ');
}

function getDayNameFromDate(dateStr) {
  if (!dateStr) return null;
  const str = dateStr.toString().split('T')[0];
  const parts = str.split('-');
  if (parts.length !== 3) return null;
  const year = parseInt(parts[0], 10);
  const month = parseInt(parts[1], 10) - 1;
  const day = parseInt(parts[2], 10);
  const date = new Date(year, month, day);
  const days = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
  return days[date.getDay()];
}

async function createSchedule(req, res) {
  try {
    const { hari, tanggal, shift, petugas_warga, keterangan } = req.body;
    if (!hari || !petugas_warga) {
      return res.status(400).json({ success: false, message: 'Hari dan nama petugas ronda wajib diisi.' });
    }

    if (tanggal) {
      const expectedHari = getDayNameFromDate(tanggal);
      if (expectedHari && hari.trim().toLowerCase() !== expectedHari.toLowerCase()) {
        return res.status(400).json({
          success: false,
          message: `Hari '${hari}' tidak sesuai dengan tanggal '${tanggal}' (tanggal tersebut adalah hari ${expectedHari}). Mohon sesuaikan.`,
        });
      }

      const checkExist = await pool.query('SELECT id FROM patrol_schedules WHERE tanggal = $1', [tanggal]);
      if (checkExist.rows.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Jadwal siskamling untuk tanggal tersebut sudah ada! Silakan gunakan tombol Edit untuk memperbarui.',
        });
      }
    }

    const formattedPetugas = formatNamaPetugas(petugas_warga);

    const result = await pool.query(
      `INSERT INTO patrol_schedules (hari, tanggal, shift, petugas_warga, keterangan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [hari, tanggal || null, shift || 'Shift Malam (22:00 - 04:00)', formattedPetugas, keterangan || null, req.user.id]
    );

    // Kirim notifikasi WhatsApp ke petugas yang terdaftar (Async)
    const { sendPatrolScheduleWA } = require('../services/whatsapp.service');
    (async () => {
      try {
        const listNama = formattedPetugas.split(',').map(n => n.trim()).filter(Boolean);
        for (const namaPetugas of listNama) {
          const uRes = await pool.query(
            `SELECT nama, no_hp FROM users WHERE nama ILIKE $1 AND no_hp IS NOT NULL AND no_hp != '' LIMIT 1`,
            [`%${namaPetugas}%`]
          );
          if (uRes.rows.length > 0 && uRes.rows[0].no_hp) {
            await sendPatrolScheduleWA({
              noHp: uRes.rows[0].no_hp,
              userNama: uRes.rows[0].nama,
              hari,
              tanggal,
              shift: shift || 'Shift Malam (22:00 - 04:00)',
              petugasLengkap: formattedPetugas,
              keterangan,
            });
          }
        }
      } catch (waErr) {
        console.error('WA Schedule Notification Error:', waErr.message);
      }
    })();

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

    const existing = await pool.query('SELECT hari, tanggal FROM patrol_schedules WHERE id = $1', [id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jadwal ronda tidak ditemukan.' });
    }

    const targetHari = hari || existing.rows[0].hari;
    const targetTanggal = tanggal !== undefined ? tanggal : existing.rows[0].tanggal;

    if (targetTanggal && targetHari) {
      const tglStr = typeof targetTanggal === 'string' ? targetTanggal : new Date(targetTanggal).toISOString().split('T')[0];
      const expectedHari = getDayNameFromDate(tglStr);
      if (expectedHari && targetHari.trim().toLowerCase() !== expectedHari.toLowerCase()) {
        return res.status(400).json({
          success: false,
          message: `Hari '${targetHari}' tidak sesuai dengan tanggal '${tglStr}' (tanggal tersebut adalah hari ${expectedHari}). Mohon sesuaikan.`,
        });
      }

      const checkExist = await pool.query('SELECT id FROM patrol_schedules WHERE tanggal = $1 AND id != $2', [targetTanggal, id]);
      if (checkExist.rows.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Jadwal siskamling untuk tanggal tersebut sudah ada pada jadwal lain!',
        });
      }
    }

    const formattedPetugas = petugas_warga ? formatNamaPetugas(petugas_warga) : null;

    const result = await pool.query(
      `UPDATE patrol_schedules 
       SET hari = COALESCE($1, hari), 
           tanggal = COALESCE($2, tanggal),
           shift = COALESCE($3, shift), 
           petugas_warga = COALESCE($4, petugas_warga), 
           keterangan = COALESCE($5, keterangan),
           updated_at = NOW()
       WHERE id = $6 RETURNING *`,
      [hari, tanggal, shift, formattedPetugas, keterangan, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jadwal ronda tidak ditemukan.' });
    }

    // Kirim notifikasi WhatsApp ke petugas yang terdaftar (Async)
    if (formattedPetugas) {
      const { sendPatrolScheduleWA } = require('../services/whatsapp.service');
      (async () => {
        try {
          const listNama = formattedPetugas.split(',').map(n => n.trim()).filter(Boolean);
          for (const namaPetugas of listNama) {
            const uRes = await pool.query(
              `SELECT nama, no_hp FROM users WHERE nama ILIKE $1 AND no_hp IS NOT NULL AND no_hp != '' LIMIT 1`,
              [`%${namaPetugas}%`]
            );
            if (uRes.rows.length > 0 && uRes.rows[0].no_hp) {
              await sendPatrolScheduleWA({
                noHp: uRes.rows[0].no_hp,
                userNama: uRes.rows[0].nama,
                hari: hari || result.rows[0].hari,
                tanggal: tanggal || result.rows[0].tanggal,
                shift: shift || result.rows[0].shift,
                petugasLengkap: formattedPetugas,
                keterangan: keterangan || result.rows[0].keterangan,
              });
            }
          }
        } catch (waErr) {
          console.error('WA Schedule Update Notification Error:', waErr.message);
        }
      })();
    }

    return res.status(200).json({ success: true, message: 'Jadwal ronda berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateSchedule Error:', err.message);
    return res.status(500).json({ success: false, message: err.message || 'Terjadi kesalahan server.' });
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

    // Admin boleh bypass tanpa scan QR
    if (req.user.role !== 'admin') {
      if (!kode_qr) {
        return res.status(400).json({ success: false, message: 'Anda harus scan QR Pos Ronda untuk absensi!' });
      }
      // Validasi token QR terhadap token aktif di database
      const activeToken = await pool.query(
        'SELECT token FROM patrol_qr_tokens WHERE is_active = true ORDER BY created_at DESC LIMIT 1'
      );
      if (activeToken.rows.length === 0 || activeToken.rows[0].token !== kode_qr) {
        return res.status(400).json({ success: false, message: 'Kode QR Pos Ronda tidak valid atau sudah kadaluarsa!' });
      }
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

    // Hitung menit mulai (toleransi awal 15 menit sebelum jam shift)
    const startMins = startHour * 60 + startMin;
    const earliestStartMins = startMins - 15; // Boleh absen 15 menit sebelum jam dimulainya shift

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
    // Cari token aktif
    let result = await pool.query(
      'SELECT token, created_at FROM patrol_qr_tokens WHERE is_active = true ORDER BY created_at DESC LIMIT 1'
    );

    // Jika belum ada token, buat yang pertama
    if (result.rows.length === 0) {
      const newToken = 'RONDA-' + crypto.randomUUID().substring(0, 8).toUpperCase();
      result = await pool.query(
        'INSERT INTO patrol_qr_tokens (token, is_active) VALUES ($1, true) RETURNING token, created_at',
        [newToken]
      );
    }

    const { token, created_at } = result.rows[0];

    return res.status(200).json({
      success: true,
      data: {
        pos_name: 'Pos Ronda Utama Siskamling',
        qr_code_data: token,
        generated_at: created_at,
      },
    });
  } catch (err) {
    console.error('GetPosRondaQr Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function regenerateQr(req, res) {
  try {
    // Nonaktifkan semua token lama
    await pool.query('UPDATE patrol_qr_tokens SET is_active = false');

    // Buat token baru
    const newToken = 'RONDA-' + crypto.randomUUID().substring(0, 8).toUpperCase();
    const result = await pool.query(
      'INSERT INTO patrol_qr_tokens (token, is_active) VALUES ($1, true) RETURNING token, created_at',
      [newToken]
    );

    return res.status(200).json({
      success: true,
      message: 'QR Pos Ronda berhasil di-regenerate. QR lama sudah tidak berlaku.',
      data: {
        pos_name: 'Pos Ronda Utama Siskamling',
        qr_code_data: result.rows[0].token,
        generated_at: result.rows[0].created_at,
      },
    });
  } catch (err) {
    console.error('RegenerateQr Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteAttendance(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM patrol_attendances WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Data absensi tidak ditemukan.' });
    }
    return res.status(200).json({ success: true, message: 'Log absensi berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteAttendance Error:', err.message);
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
  deleteAttendance,
  getPosRondaQr,
  regenerateQr,
};

