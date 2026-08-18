const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');

/**
 * Mengirim notifikasi push FCM ke seluruh Pengurus/Admin RT saat ada Pengaduan Baru.
 *
 * Menggunakan Durable Database Idempotency (complaints.fcm_dispatch_status).
 * Bersifat fail-safe & non-blocking: kegagalan FCM tidak membatalkan pembuatan pengaduan.
 */
async function sendNewComplaintPushNotification(complaint, reporterUser = {}) {
  if (!complaint || !complaint.id) {
    return { skipped: true, reason: 'invalid_complaint' };
  }

  try {
    // Klaim atomik status dispatch pengaduan baru (Race Condition Guard)
    const claimResult = await pool.query(
      `UPDATE complaints
       SET fcm_dispatch_status = 'pending'
       WHERE id = $1
         AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
       RETURNING id, fcm_dispatch_status`,
      [complaint.id]
    );

    if (claimResult.rows.length === 0) {
      const check = await pool.query(`SELECT fcm_dispatch_status FROM complaints WHERE id = $1`, [complaint.id]);
      const curStatus = check.rows[0]?.fcm_dispatch_status || 'unknown';
      console.log(`ℹ️ [FCM Complaint] Pengaduan #${complaint.id} tidak dapat diklaim (status: '${curStatus}'), siaran duplikat dicegah.`);
      return { skipped: true, reason: curStatus === 'sent' ? 'already_sent' : 'already_processing' };
    }

    const namaPelapor = reporterUser.nama || 'Warga';
    const cleanJudul = String(complaint.judul || '').trim();
    const cleanDeskripsi = String(complaint.deskripsi || '').trim();
    const ringkasan = cleanDeskripsi.length > 100 ? `${cleanDeskripsi.slice(0, 97)}...` : cleanDeskripsi;

    const title = `📩 Pengaduan Baru: [${complaint.kode_tiket}]`;
    const body = `Dari ${namaPelapor}: "${cleanJudul}"${ringkasan ? ` — ${ringkasan}` : ''}`;

    const pushResult = await dispatcher.sendToRoles(dispatcher.PERAN_PENGURUS, {
      title,
      body,
      data: {
        entity_type: 'complaint',
        entity_id: String(complaint.id),
        kode_tiket: String(complaint.kode_tiket || ''),
        kategori: String(complaint.kategori || ''),
        status: String(complaint.status || 'Menunggu'),
        action: 'NEW_COMPLAINT',
        created_at: complaint.created_at
          ? new Date(complaint.created_at).toISOString()
          : new Date().toISOString(),
      },
      priority: 'normal',
      collapseKey: 'complaint_admin_incoming',
    });

    if (pushResult.skipped && pushResult.reason === 'no_active_users_for_roles') {
      console.log('ℹ️ [FCM Complaint] Tidak ada pengurus aktif untuk menerima notifikasi pengaduan baru.');
      await pool.query(
        `UPDATE complaints SET fcm_dispatch_status = 'sent' WHERE id = $1`,
        [complaint.id]
      );
      return { skipped: true, reason: 'no_active_pengurus' };
    }

    if (pushResult.success === false && !pushResult.simulated) {
      await pool.query(
        `UPDATE complaints SET fcm_dispatch_status = 'failed' WHERE id = $1`,
        [complaint.id]
      );
      console.error(`⚠️ [FCM Complaint] Gagal mengirim push pengaduan baru #${complaint.id}:`, pushResult.error);
      return pushResult;
    }

    await pool.query(
      `UPDATE complaints SET fcm_dispatch_status = 'sent' WHERE id = $1`,
      [complaint.id]
    );

    console.log(
      `🔔 [FCM Complaint] Notifikasi Pengaduan Baru #${complaint.id} [${complaint.kode_tiket}]:\n` +
      `   - Total Token     : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil        : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal           : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode            : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(
      `UPDATE complaints SET fcm_dispatch_status = 'failed' WHERE id = $1`,
      [complaint.id]
    ).catch(() => {});
    console.error('⚠️ [FCM Complaint] Error dispatch pengaduan baru:', err.message);
    return { error: err.message };
  }
}

/**
 * Mengirim notifikasi push FCM ke Pelapor spesifik saat status atau tanggapan pengaduan berubah.
 *
 * Menggunakan Durable Database Idempotency (complaints.fcm_last_response_dispatch).
 * Mencegah siaran ganda jika update tanpa perubahan data atau dipanggil berulang.
 */
async function sendComplaintResponsePushNotification(complaint, options = {}) {
  if (!complaint || !complaint.id || !complaint.user_id) {
    return { skipped: true, reason: 'invalid_complaint_or_owner' };
  }

  const finalStatus = complaint.status || 'Diproses';
  const responseText = complaint.response || options.response || '';
  const dispatchSignature = `${finalStatus}::${responseText}`;

  try {
    // Klaim atomik: hanya kirim bila signature status::response berbeda dari yang terakhir dikirim
    const claimResult = await pool.query(
      `UPDATE complaints
       SET fcm_last_response_dispatch = $2
       WHERE id = $1
         AND (fcm_last_response_dispatch IS DISTINCT FROM $2)
       RETURNING id, user_id, kode_tiket, status`,
      [complaint.id, dispatchSignature]
    );

    if (claimResult.rows.length === 0) {
      console.log(`ℹ️ [FCM Complaint] Tanggapan/status Pengaduan #${complaint.id} sudah pernah dikirim atau tidak berubah, push dilewati.`);
      return { skipped: true, reason: 'no_change_or_duplicate' };
    }

    // Pastikan user pelapor aktif
    const userCheck = await pool.query(
      `SELECT id, nama, is_active FROM users WHERE id = $1`,
      [complaint.user_id]
    );
    if (userCheck.rows.length === 0 || !userCheck.rows[0].is_active) {
      console.log(`ℹ️ [FCM Complaint] Pelapor #${complaint.user_id} tidak ditemukan atau nonaktif, push dilewati.`);
      return { skipped: true, reason: 'inactive_or_missing_user' };
    }

    const title = `📋 Pengaduan [${complaint.kode_tiket}]: ${finalStatus}`;
    const cleanTanggapan = String(responseText || '').trim();
    const body = cleanTanggapan
      ? `Tanggapan Pengurus: "${cleanTanggapan.length > 100 ? `${cleanTanggapan.slice(0, 97)}...` : cleanTanggapan}"`
      : `Status pengaduan Anda telah diperbarui menjadi "${finalStatus}".`;

    const pushResult = await dispatcher.sendToUser(complaint.user_id, {
      title,
      body,
      data: {
        entity_type: 'complaint',
        entity_id: String(complaint.id),
        kode_tiket: String(complaint.kode_tiket || ''),
        status: String(finalStatus),
        action: 'COMPLAINT_REPLIED',
        updated_at: new Date().toISOString(),
      },
      priority: 'high',
      collapseKey: `complaint_status_${complaint.id}`,
    });

    if (pushResult.success === false && !pushResult.simulated) {
      // Reset signature agar retry memungkinkan jika FCM error
      await pool.query(
        `UPDATE complaints SET fcm_last_response_dispatch = NULL WHERE id = $1`,
        [complaint.id]
      ).catch(() => {});
      console.error(`⚠️ [FCM Complaint] Gagal mengirim push tanggapan #${complaint.id}:`, pushResult.error);
      return pushResult;
    }

    console.log(
      `🔔 [FCM Complaint] Notifikasi Tanggapan Pengaduan #${complaint.id} [${complaint.kode_tiket}]:\n` +
      `   - Target Pelapor : ${userCheck.rows[0].nama} (${complaint.user_id})\n` +
      `   - Total Token    : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil       : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal          : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode           : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(
      `UPDATE complaints SET fcm_last_response_dispatch = NULL WHERE id = $1`,
      [complaint.id]
    ).catch(() => {});
    console.error('⚠️ [FCM Complaint] Error dispatch tanggapan pengaduan:', err.message);
    return { error: err.message };
  }
}

async function getComplaints(req, res) {
  try {
    const { status, search } = req.query;
    let query = `SELECT c.*, u.nama AS nama_pengirim, u.nama AS nama_pelapor, u.nama AS nama, r.nama AS responded_by_nama,
                 COUNT(*) OVER() AS total_data
                 FROM complaints c 
                 JOIN users u ON c.user_id = u.id 
                 LEFT JOIN users r ON c.responded_by = r.id 
                 WHERE c.deleted_at IS NULL`;
    const params = [];

    // Warga hanya melihat pengaduannya sendiri — pola yang sama dengan
    // getLetters. Aduan kerap memuat keluhan tentang tetangga, jadi membukanya
    // ke seluruh warga menimbulkan masalah nyata. Pengurus tetap melihat semua.
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      query += ` AND c.user_id = $${params.length}`;
    }

    if (status && status !== 'Semua') {
      let st = status;
      if (st.toLowerCase() === 'pending') st = 'Menunggu';
      params.push(st);
      query += ` AND c.status = $${params.length}`;
    }
    if (search) { params.push(`%${search}%`); query += ` AND (c.judul ILIKE $${params.length} OR c.kode_tiket ILIKE $${params.length} OR u.nama ILIKE $${params.length})`; }
    query += ' ORDER BY c.created_at DESC';

    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 25;
    const offset = (page - 1) * limit;

    params.push(limit, offset);
    query += ` LIMIT $${params.length - 1} OFFSET $${params.length}`;

    const result = await pool.query(query, params);
    
    const totalData = result.rows.length > 0 ? parseInt(result.rows[0].total_data, 10) : 0;
    const totalPages = Math.ceil(totalData / limit);

    return res.status(200).json({ 
      success: true, 
      count: result.rows.length, 
      data: result.rows,
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        limit: limit
      }
    });
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
    const aduan = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Mengirim pengaduan [${aduan.kode_tiket}] "${ringkas(aduan.judul)}" — kategori ${aduan.kategori || '-'}`);

    // Siaran push notifikasi FCM ke Pengurus RT secara non-blocking
    dispatcher.dispatchAsync(() => sendNewComplaintPushNotification(aduan, req.user), 'ComplaintNew');

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
    let finalStatus = status;
    if (finalStatus && finalStatus.toLowerCase() === 'pending') finalStatus = 'Menunggu';
    if (!finalStatus || !validStatus.includes(finalStatus)) return res.status(400).json({ success: false, message: `Status harus salah satu dari: ${validStatus.join(', ')}` });
    // `tanggapan_dibaca_pada` dikosongkan setiap kali tanggapan ditulis.
    //
    // Satu pengaduan bisa ditanggapi berkali-kali — "Diproses" hari ini,
    // "Selesai" minggu depan dengan penjelasan yang berbeda. Kalau penandanya
    // dipasang sekali seumur hidup baris, tanggapan kedua tidak akan pernah
    // terlihat baru: warga sudah membaca yang pertama, dan aplikasinya
    // menganggap urusannya sudah lewat.
    //
    // Hanya dikosongkan bila memang ADA teks tanggapan. Mengubah status tanpa
    // menulis apa pun tidak menghadirkan sesuatu yang perlu dibaca, jadi
    // menyalakan lencananya hanya melatih warga mengabaikan lencana itu.
    //
    // `response` HANYA ditulis bila kuncinya memang dikirim.
    //
    // Sebelumnya kolomnya selalu ditimpa `response || null`, sehingga "tidak
    // mengirim field ini" dan "sengaja mengosongkannya" tidak bisa dibedakan:
    // satu permintaan yang hanya memajukan status akan MENGHAPUS tanggapan yang
    // sudah pernah ditulis pengurus. Hilangnya tak bergejala — statusnya
    // berubah seperti diminta, dan teks yang lenyap baru ketahuan kalau ada
    // yang membuka dialog Detail dan bertanya ke mana perginya.
    //
    // Ditemukan oleh uji ini sendiri: bagian yang mengubah status tanpa teks
    // membuat bagian berikutnya gagal, karena barisnya kehilangan tanggapannya.
    const kirimResponse = response !== undefined;
    const adaTanggapan = kirimResponse && typeof response === 'string' && response.trim() !== '';
    const result = await pool.query(
      `UPDATE complaints SET
         status = $1,
         response = CASE WHEN $5 THEN $2 ELSE response END,
         responded_by = $3,
         tanggapan_dibaca_pada = CASE WHEN $6 THEN NULL ELSE tanggapan_dibaca_pada END,
         updated_at = NOW()
       WHERE id = $4 RETURNING *`,
      [finalStatus, response ?? null, req.user.id, id, kirimResponse, adaTanggapan]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengaduan tidak ditemukan.' });
    const a = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Menanggapi pengaduan [${a.kode_tiket}] "${ringkas(a.judul)}" — status menjadi "${status}"${response ? `, tanggapan: "${ringkas(response, 80)}"` : ''}`);

    // Beri tahu pelapornya lewat WhatsApp — sejajar dengan surat yang disetujui
    // dan tagihan yang terbit. Tanpa ini, pengaduan yang ditanggapi lalu
    // ditandai "Diproses" tidak mengubah satu angka pun di dasbor warga, jadi
    // ia benar-benar tidak punya cara tahu jawabannya sudah ada.
    //
    // Dijalankan tanpa di-await dan galatnya ditelan: WhatsApp adalah kabar
    // tambahan, dan gateway yang sedang mati tidak boleh membuat penyimpanan
    // tanggapan ikut gagal — tanggapannya sendiri sudah tersimpan di atas.
    const { sendComplaintRepliedWA } = require('../services/whatsapp.service');
    (async () => {
      if (!adaTanggapan) return;
      const u = await pool.query('SELECT nama, no_hp FROM users WHERE id = $1', [a.user_id]);
      if (u.rows.length === 0) return;
      await sendComplaintRepliedWA({
        userNama: u.rows[0].nama,
        noHp: u.rows[0].no_hp,
        kodeTiket: a.kode_tiket,
        judul: a.judul,
        status: finalStatus,
        tanggapan: a.response,
      });
    })().catch((e) => console.log('ℹ️ Catatan WA Pengaduan:', e.message));

    // Siaran push notifikasi FCM ke Pelapor secara non-blocking
    dispatcher.dispatchAsync(() => sendComplaintResponsePushNotification(a, { response: a.response }), 'ComplaintResponse');

    return res.status(200).json({ success: true, message: `Status pengaduan berhasil diubah ke "${status}".`, data: result.rows[0] });
  } catch (err) {
    console.error('UpdateComplaintStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * PUT /api/complaints/:id/baca — warga menandai tanggapan sudah ia baca.
 *
 * Dijaga izin `view`, BUKAN `update`. Di modul ini `update` berarti menanggapi
 * pengaduan — kewenangan pengurus — jadi memberi warga `update` supaya bisa
 * menghapus lencananya sendiri akan sekaligus membuka jalan menanggapi seluruh
 * pengaduan warga lain. Preseden yang sama sudah tercatat pada
 * `POST /polling/:id/vote` dan `POST /meteran`.
 *
 * Kepemilikan ditegakkan DI SINI lewat `user_id`, bukan dengan mempercayai
 * pemanggil: klausanya ada di dalam WHERE, sehingga id milik orang lain tidak
 * memperbarui apa pun dan menjawab 404 — bukan 403, karena warga memang tidak
 * berhak tahu bahwa baris itu ada.
 *
 * Idempoten: menandai dua kali tidak menggeser waktunya, supaya "kapan dibaca"
 * tetap berarti pertama kali dibaca.
 */
async function tandaiTanggapanDibaca(req, res) {
  try {
    const { id } = req.params;
    const hasil = await pool.query(
      `UPDATE complaints
       SET tanggapan_dibaca_pada = COALESCE(tanggapan_dibaca_pada, NOW())
       WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
         AND response IS NOT NULL
       RETURNING id, tanggapan_dibaca_pada`,
      [id, req.user.id]
    );

    if (hasil.rows.length === 0) {
      // Tidak ditemukan, bukan milik pemanggil, atau memang belum ada
      // tanggapan untuk dibaca. Ketiganya bukan galat yang perlu ditampilkan
      // ke warga — layarnya memanggil ini otomatis saat dialog dibuka, dan
      // sebuah kesalahan merah untuk aduan yang belum ditanggapi hanya
      // membingungkan. Dijawab 200 dengan penanda apa adanya.
      return res.status(200).json({ success: true, ditandai: false });
    }

    return res.status(200).json({
      success: true,
      ditandai: true,
      dibaca_pada: hasil.rows[0].tanggapan_dibaca_pada,
    });
  } catch (err) {
    console.error('TandaiTanggapanDibaca Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteComplaint(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('UPDATE complaints SET deleted_at = NOW() WHERE id = $1 RETURNING *', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengaduan tidak ditemukan.' });
    const d = result.rows[0];
    await logActivity(req, TIPE.DELETE, `Menghapus pengaduan [${d.kode_tiket}] "${ringkas(d.judul)}" (status ${d.status}) — isi: "${ringkas(d.deskripsi, 100)}"`);

    return res.status(200).json({ success: true, message: 'Pengaduan berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteComplaint Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getComplaintStats(req, res) {
  try {
    let whereClause = 'WHERE c.deleted_at IS NULL';
    const params = [];

    if (req.user.role === 'warga') {
      params.push(req.user.id);
      whereClause += ` AND c.user_id = $${params.length}`;
    }

    const query = `
      SELECT 
        COUNT(*) FILTER (WHERE c.status IN ('Menunggu', 'pending', 'diajukan')) AS pending,
        COUNT(*) FILTER (WHERE c.status = 'Diproses') AS diproses,
        COUNT(*) FILTER (WHERE c.status IN ('Selesai', 'disetujui')) AS selesai,
        COUNT(*) FILTER (WHERE c.status = 'Ditolak') AS ditolak,
        COUNT(*) AS total
      FROM complaints c
      ${whereClause}
    `;

    const result = await pool.query(query, params);
    const row = result.rows[0] || {};

    return res.status(200).json({
      success: true,
      data: {
        pending: parseInt(row.pending || 0, 10),
        diproses: parseInt(row.diproses || 0, 10),
        selesai: parseInt(row.selesai || 0, 10),
        ditolak: parseInt(row.ditolak || 0, 10),
        total: parseInt(row.total || 0, 10),
      }
    });
  } catch (err) {
    console.error('GetComplaintStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getComplaints,
  getComplaintStats,
  createComplaint,
  updateComplaintStatus,
  tandaiTanggapanDibaca,
  deleteComplaint,
  sendNewComplaintPushNotification,
  sendComplaintResponsePushNotification,
};

