const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');
const { klausaRt, tolakLuarRt } = require('../utils/lingkup-rt');

/**
 * Mengirim notifikasi push FCM ke seluruh Pengurus/Admin RT saat ada Permohonan Surat Baru.
 *
 * Menggunakan Durable Database Idempotency (letters.fcm_dispatch_status).
 * Bersifat fail-safe & non-blocking: kegagalan FCM tidak membatalkan pembuatan surat.
 */
async function sendNewLetterPushNotification(letter, applicantUser = {}) {
  if (!letter || !letter.id) {
    return { skipped: true, reason: 'invalid_letter' };
  }

  try {
    // Klaim atomik status dispatch surat baru (Race Condition Guard)
    const claimResult = await pool.query(
      `UPDATE letters
       SET fcm_dispatch_status = 'pending'
       WHERE id = $1
         AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
       RETURNING id, fcm_dispatch_status`,
      [letter.id]
    );

    if (claimResult.rows.length === 0) {
      const check = await pool.query(`SELECT fcm_dispatch_status FROM letters WHERE id = $1`, [letter.id]);
      const curStatus = check.rows[0]?.fcm_dispatch_status || 'unknown';
      console.log(`ℹ️ [FCM Letter] Surat #${letter.id} tidak dapat diklaim (status: '${curStatus}'), siaran duplikat dicegah.`);
      return { skipped: true, reason: curStatus === 'sent' ? 'already_sent' : 'already_processing' };
    }

    const namaPemohon = applicantUser.nama || 'Warga';
    const cleanJenis = String(letter.jenis_surat || 'Surat Pengantar').trim();
    const cleanKeperluan = String(letter.keperluan || '').trim();

    const title = '📄 Permohonan Surat Baru';
    const body = `${namaPemohon} mengajukan ${cleanJenis} — keperluan: "${cleanKeperluan}"`;

    const pushResult = await dispatcher.sendToRoles(dispatcher.PERAN_PENGURUS, {
      title,
      body,
      data: {
        entity_type: 'letter',
        entity_id: String(letter.id),
        jenis_surat: cleanJenis,
        status: String(letter.status || 'pending'),
        action: 'NEW_LETTER_REQUEST',
        created_at: letter.created_at
          ? new Date(letter.created_at).toISOString()
          : new Date().toISOString(),
      },
      priority: 'normal',
      collapseKey: 'letter_admin_incoming',
    }, {
      // Dilingkupi ke RT baris yang memicunya, bukan ke RT pengirimnya:
      // yang menentukan siapa yang perlu tahu adalah data itu sendiri.
      // `?? null` berarti seluruh RW — jaring pengaman untuk baris lama
      // yang `rt_id`-nya belum terisi, karena berhenti mengirim diam-diam
      // lebih buruk daripada mengirim terlalu luas.
      rtId: letter.rt_id ?? null,
    });

    if (pushResult.skipped && pushResult.reason === 'no_active_users_for_roles') {
      console.log('ℹ️ [FCM Letter] Tidak ada pengurus aktif untuk menerima notifikasi permohonan surat baru.');
      await pool.query(
        `UPDATE letters SET fcm_dispatch_status = 'sent' WHERE id = $1`,
        [letter.id]
      );
      return { skipped: true, reason: 'no_active_pengurus' };
    }

    if (pushResult.success === false && !pushResult.simulated) {
      await pool.query(
        `UPDATE letters SET fcm_dispatch_status = 'failed' WHERE id = $1`,
        [letter.id]
      );
      console.error(`⚠️ [FCM Letter] Gagal mengirim push permohonan surat #${letter.id}:`, pushResult.error);
      return pushResult;
    }

    await pool.query(
      `UPDATE letters SET fcm_dispatch_status = 'sent' WHERE id = $1`,
      [letter.id]
    );

    console.log(
      `🔔 [FCM Letter] Notifikasi Permohonan Surat Baru #${letter.id} [${cleanJenis}]:\n` +
      `   - Total Token     : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil        : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal           : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode            : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(
      `UPDATE letters SET fcm_dispatch_status = 'failed' WHERE id = $1`,
      [letter.id]
    ).catch(() => {});
    console.error('⚠️ [FCM Letter] Error dispatch permohonan surat baru:', err.message);
    return { error: err.message };
  }
}

/**
 * Mengirim notifikasi push FCM ke Pemohon spesifik saat status surat disetujui / ditolak.
 *
 * Menggunakan Durable Database Idempotency (letters.fcm_last_status_dispatch).
 * Mencegah siaran ganda jika update tanpa perubahan status atau dipanggil berulang.
 */
async function sendLetterStatusPushNotification(letter, options = {}) {
  if (!letter || !letter.id || !letter.user_id) {
    return { skipped: true, reason: 'invalid_letter_or_applicant' };
  }

  const rawStatus = (letter.status || options.status || '').toLowerCase();
  const note = letter.response_note || options.response_note || '';
  const dispatchSignature = `${rawStatus}::${note}`;

  try {
    // Klaim atomik: hanya kirim bila signature status::note berbeda dari yang terakhir dikirim
    const claimResult = await pool.query(
      `UPDATE letters
       SET fcm_last_status_dispatch = $2
       WHERE id = $1
         AND (fcm_last_status_dispatch IS DISTINCT FROM $2)
       RETURNING id, user_id, jenis_surat, status`,
      [letter.id, dispatchSignature]
    );

    if (claimResult.rows.length === 0) {
      console.log(`ℹ️ [FCM Letter] Status/catatan Surat #${letter.id} sudah pernah dikirim atau tidak berubah, push dilewati.`);
      return { skipped: true, reason: 'no_change_or_duplicate' };
    }

    // Pastikan user pemohon aktif
    const userCheck = await pool.query(
      `SELECT id, nama, is_active FROM users WHERE id = $1`,
      [letter.user_id]
    );
    if (userCheck.rows.length === 0 || !userCheck.rows[0].is_active) {
      console.log(`ℹ️ [FCM Letter] Pemohon #${letter.user_id} tidak ditemukan atau nonaktif, push dilewati.`);
      return { skipped: true, reason: 'inactive_or_missing_user' };
    }

    let statusLabel = 'Diproses';
    let body = `Permohonan ${letter.jenis_surat} Anda sedang diproses oleh Pengurus RT.`;

    if (rawStatus === 'disetujui' || rawStatus === 'approved') {
      statusLabel = 'Disetujui';
      body = `Permohonan ${letter.jenis_surat} Anda telah disetujui. Surat siap diambil di balai RT atau diunduh.`;
    } else if (rawStatus === 'ditolak' || rawStatus === 'rejected') {
      statusLabel = 'Ditolak';
      const cleanNote = String(note || '').trim();
      body = cleanNote
        ? `Permohonan ${letter.jenis_surat} Anda belum dapat disetujui. Catatan: "${cleanNote}"`
        : `Permohonan ${letter.jenis_surat} Anda belum dapat disetujui. Harap lengkapi persyaratan.`;
    }

    const title = `📄 Surat ${letter.jenis_surat}: ${statusLabel}`;

    const pushResult = await dispatcher.sendToUser(letter.user_id, {
      title,
      body,
      data: {
        entity_type: 'letter',
        entity_id: String(letter.id),
        jenis_surat: String(letter.jenis_surat || ''),
        status: String(rawStatus),
        action: 'LETTER_STATUS_CHANGED',
        updated_at: new Date().toISOString(),
      },
      priority: 'high',
      collapseKey: `letter_status_${letter.id}`,
    });

    if (pushResult.success === false && !pushResult.simulated) {
      // Reset signature agar retry memungkinkan jika FCM error
      await pool.query(
        `UPDATE letters SET fcm_last_status_dispatch = NULL WHERE id = $1`,
        [letter.id]
      ).catch(() => {});
      console.error(`⚠️ [FCM Letter] Gagal mengirim push status surat #${letter.id}:`, pushResult.error);
      return pushResult;
    }

    console.log(
      `🔔 [FCM Letter] Notifikasi Status Surat #${letter.id} [${letter.jenis_surat} -> ${statusLabel}]:\n` +
      `   - Target Pemohon : ${userCheck.rows[0].nama} (${letter.user_id})\n` +
      `   - Total Token    : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil       : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal          : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode           : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(
      `UPDATE letters SET fcm_last_status_dispatch = NULL WHERE id = $1`,
      [letter.id]
    ).catch(() => {});
    console.error('⚠️ [FCM Letter] Error dispatch status surat:', err.message);
    return { error: err.message };
  }
}

async function getLetters(req, res) {
  try {
    const { status, user_id } = req.query;
    let query = `SELECT l.*, u.nama AS nama_pemohon, u.alamat, u.no_kk, a.nama AS approved_by_nama,
                 COUNT(*) OVER() AS total_data
                 FROM letters l JOIN users u ON l.user_id = u.id LEFT JOIN users a ON l.approved_by = a.id 
                 WHERE l.deleted_at IS NULL`;
    const params = [];
    // Pelingkupan RT. Dipasang sebelum penyaringan lain supaya daftar,
    // penghitungan total, dan export memakai batas yang sama persis.
    query += klausaRt(req, 'l', params);
    if (req.user.role === 'warga') { params.push(req.user.id); query += ` AND l.user_id = $${params.length}`; }
    else if (user_id) { params.push(user_id); query += ` AND l.user_id = $${params.length}`; }
    if (status) { params.push(status); query += ` AND l.status = $${params.length}`; }
    query += ' ORDER BY l.created_at DESC';

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
    const s = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Mengajukan surat "${ringkas(s.jenis_surat)}" — keperluan: ${ringkas(s.keperluan, 80)}`);

    // Siaran push notifikasi FCM ke Pengurus RT secara non-blocking
    dispatcher.dispatchAsync(() => sendNewLetterPushNotification(s, req.user), 'LetterNew');

    return res.status(201).json({ success: true, message: 'Pengajuan surat berhasil dikirim.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateLetter Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateLetterStatus(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'letters', id)) return;
    const { status, response_note } = req.body;
    const validStatus = ['diproses', 'disetujui', 'ditolak', 'approved', 'rejected'];
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
        if (status === 'disetujui' || status === 'approved') {
          await sendLetterApprovedWA({
            userNama: u.nama,
            noHp: u.no_hp,
            jenisSurat: updatedLetter.jenis_surat,
          });
        } else if (status === 'ditolak' || status === 'rejected') {
          await sendWA({
            target: u.no_hp,
            message: `📄 *PERMOHONAN SURAT DITOLAK*\n\nHalo Bpk/Ibu *${u.nama}*,\n\nPermohonan *${updatedLetter.jenis_surat}* Anda belum dapat disetujui.\nCatatan: ${response_note || 'Harap lengkapi persyaratan'}\n\n— *Pengurus RT*`,
          });
        }
      }
    })().catch((e) => console.log('ℹ️ Catatan WA Surat:', e.message));

    // Siaran push notifikasi FCM ke Pemohon secara non-blocking
    dispatcher.dispatchAsync(() => sendLetterStatusPushNotification(updatedLetter, { status, response_note }), 'LetterStatus');

    await logActivity(req, TIPE.UPDATE, `Memproses surat "${ringkas(updatedLetter.jenis_surat)}" milik ${updatedLetter.nama_pemohon || "-"} — status menjadi "${status}"`);

    return res.status(200).json({ success: true, message: `Surat berhasil di-${status}.`, data: updatedLetter });
  } catch (err) {
    console.error('UpdateLetterStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteLetter(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'letters', id)) return;
    const letterRes = await pool.query('SELECT * FROM letters WHERE id = $1', [id]);
    if (letterRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Surat tidak ditemukan.' });
    }

    const letter = letterRes.rows[0];
    const status = (letter.status || '').toLowerCase();
    const isOwner = letter.user_id === req.user.id;

    // Warga hanya boleh menghapus surat miliknya sendiri
    if (req.user.role === 'warga' && !isOwner) {
      return res.status(403).json({ success: false, message: 'Anda tidak memiliki izin menghapus surat ini.' });
    }

    // Surat yang sudah disetujui (terbit nomor surat resmi) tidak boleh dihapus demi integritas arsip
    if (status === 'disetujui' || status === 'approved') {
      return res.status(409).json({
        success: false,
        message: 'Surat yang sudah disetujui tidak dapat dihapus karena telah menjadi arsip kependudukan resmi.',
      });
    }

    await pool.query('DELETE FROM letters WHERE id = $1', [id]);
    await logActivity(
      req,
      TIPE.DELETE,
      `Menghapus/membatalkan permohonan surat #${id} ("${ringkas(letter.jenis_surat)}") status: ${letter.status}`
    );

    return res.status(200).json({ success: true, message: 'Permohonan surat berhasil dibatalkan/dihapus.' });
  } catch (err) {
    console.error('DeleteLetter Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getLetters,
  createLetter,
  updateLetterStatus,
  deleteLetter,
  sendNewLetterPushNotification,
  sendLetterStatusPushNotification,
};
