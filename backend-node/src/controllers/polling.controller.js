const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');

/**
 * Mengirim notifikasi push FCM siaran polling baru yang aktif kepada seluruh warga/user yang berhak memberikan suara.
 *
 * Menggunakan Durable Database Idempotency (polling.fcm_dispatch_status).
 * Bersifat fail-safe & non-blocking: kegagalan FCM tidak membatalkan pembuatan/aktivasi polling.
 */
async function sendNewPollingPushNotification(polling) {
  if (!polling || !polling.id) {
    return { skipped: true, reason: 'invalid_polling' };
  }

  const rawStatus = (polling.status || '').toLowerCase();
  if (rawStatus !== 'aktif') {
    console.log(`ℹ️ [FCM Polling] Polling #${polling.id} berstatus '${polling.status}' (bukan aktif), push dilewati.`);
    return { skipped: true, reason: 'polling_not_active' };
  }

  try {
    // 1. Klaim atomik status dispatch (Race Condition & Durable Idempotency Guard)
    const claimResult = await pool.query(
      `UPDATE polling
       SET fcm_dispatch_status = 'pending'
       WHERE id = $1
         AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
       RETURNING id, judul, deskripsi, status, tanggal_mulai::text AS tanggal_mulai, tanggal_selesai::text AS tanggal_selesai`,
      [polling.id]
    );

    if (claimResult.rows.length === 0) {
      console.log(`ℹ️ [FCM Polling] Polling #${polling.id} tidak dapat diklaim (status: sudah dikirim/sedang diproses), siaran duplikat dicegah.`);
      return { skipped: true, reason: 'already_sent_or_pending' };
    }

    const currentPolling = claimResult.rows[0];

    // 2. Tentukan role yang berhak melihat/memilih pada modul polling dari role_permissions
    let eligibleRoles = ['admin', 'ketua_rt', 'sekretaris', 'bendahara', 'warga'];
    try {
      const permRes = await pool.query(
        `SELECT DISTINCT role FROM role_permissions WHERE menu_kode = 'aspirasi.polling' AND can_view = true`
      );
      if (permRes.rows.length > 0) {
        eligibleRoles = ['admin', ...permRes.rows.map((r) => r.role)];
      }
    } catch {
      // fallback default
    }

    const title = `🗳️ Polling Baru: ${currentPolling.judul}`;
    const tglSelesai = currentPolling.tanggal_selesai ? String(currentPolling.tanggal_selesai).split('T')[0] : '';
    const body = tglSelesai
      ? `Suara Anda menentukan lingkungan RT! Berikan hak suara Anda pada polling "${currentPolling.judul}" sebelum ${tglSelesai}.`
      : `Suara Anda menentukan lingkungan RT! Berikan hak suara Anda pada polling "${currentPolling.judul}".`;

    const pushResult = await dispatcher.sendToRoles(eligibleRoles, {
      title,
      body,
      data: {
        entity_type: 'polling',
        entity_id: String(currentPolling.id),
        action: 'NEW_POLLING',
        judul: String(currentPolling.judul || ''),
        tanggal_mulai: String(currentPolling.tanggal_mulai || ''),
        tanggal_selesai: String(currentPolling.tanggal_selesai || ''),
        status: String(currentPolling.status || 'aktif'),
        created_at: new Date().toISOString(),
      },
      priority: 'normal',
      collapseKey: 'polling_broadcast',
    });

    if (pushResult.success === false && !pushResult.simulated) {
      await pool.query('UPDATE polling SET fcm_dispatch_status = $1 WHERE id = $2', ['failed', currentPolling.id]).catch(() => {});
      console.error(`⚠️ [FCM Polling] Gagal mengirim push polling baru #${currentPolling.id}:`, pushResult.error);
      return pushResult;
    }

    await pool.query('UPDATE polling SET fcm_dispatch_status = $1 WHERE id = $2', ['sent', currentPolling.id]).catch(() => {});

    console.log(
      `🔔 [FCM Polling] Notifikasi Polling Baru #${currentPolling.id} [${currentPolling.judul}]:\n` +
      `   - Total Token : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil    : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal       : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode        : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query('UPDATE polling SET fcm_dispatch_status = $1 WHERE id = $2', ['failed', polling.id]).catch(() => {});
    console.error(`⚠️ [FCM Polling] Gagal memproses dispatch polling baru #${polling.id}:`, err.message);
    return { error: err.message };
  }
}

async function getPolling(req, res) {
  try {
    const { status } = req.query;
    let query = `
      SELECT p.id, p.judul, p.deskripsi, p.status,
        p.tanggal_mulai::text AS tanggal_mulai,
        p.tanggal_selesai::text AS tanggal_selesai,
        p.created_by, p.created_at, p.updated_at,
        u.nama AS created_by_nama,
        CASE 
          WHEN p.tanggal_selesai::text ~ 'T|\\s\\d{2}:' AND NOT p.tanggal_selesai::text ~ '00:00:00' 
            THEN (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta') > p.tanggal_selesai::timestamp
          ELSE (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date > p.tanggal_selesai::date
        END AS lewat_deadline,
        CASE 
          WHEN p.tanggal_mulai::text ~ 'T|\\s\\d{2}:' AND NOT p.tanggal_mulai::text ~ '00:00:00' 
            THEN (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta') < p.tanggal_mulai::timestamp
          ELSE (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date < p.tanggal_mulai::date
        END AS belum_mulai
      FROM polling p 
      LEFT JOIN users u ON p.created_by = u.id 
      WHERE 1=1
    `;
    const params = [];
    if (status && status !== 'Semua') {
      params.push(status.toLowerCase());
      query += ` AND LOWER(p.status) = $${params.length}`;
    }
    query += ' ORDER BY p.created_at DESC';
    const result = await pool.query(query, params);

    // Suara milik pemanggil, sekali ambil untuk seluruh polling.
    const suaraSaya = await pool.query(
      'SELECT polling_id, option_id FROM polling_votes WHERE user_id = $1',
      [req.user.id]
    );
    const pilihanSaya = new Map(suaraSaya.rows.map((v) => [v.polling_id, v.option_id]));

    const semuaId = result.rows.map((p) => p.id);
    const opsiPerPolling = new Map();

    if (semuaId.length > 0) {
      const opsi = await pool.query(
        'SELECT * FROM polling_options WHERE polling_id = ANY($1::int[]) ORDER BY polling_id, id',
        [semuaId]
      );
      for (const o of opsi.rows) {
        if (!opsiPerPolling.has(o.polling_id)) opsiPerPolling.set(o.polling_id, []);
        opsiPerPolling.get(o.polling_id).push(o);
      }
    }

    const pollingList = result.rows.map((p) => {
      const daftarOpsi = opsiPerPolling.get(p.id) || [];
      const totalVotes = daftarOpsi.reduce((sum, o) => sum + (o.vote_count || 0), 0);
      return {
        ...p,
        lewat_deadline: Boolean(p.lewat_deadline),
        belum_mulai: Boolean(p.belum_mulai),
        options: daftarOpsi.map((o) => ({
          ...o,
          percentage: totalVotes > 0 ? Math.round((o.vote_count / totalVotes) * 100) : 0,
        })),
        total_votes: totalVotes,
        sudah_vote: pilihanSaya.has(p.id),
        pilihan_saya: pilihanSaya.get(p.id) ?? null,
      };
    });
    return res.status(200).json({ success: true, count: pollingList.length, data: pollingList });
  } catch (err) {
    console.error('GetPolling Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createPolling(req, res) {
  try {
    const { judul, deskripsi, tanggal_mulai, tanggal_selesai, options } = req.body;
    if (!judul || !tanggal_mulai || !tanggal_selesai) {
      return res.status(400).json({ success: false, message: 'Judul, tanggal mulai, dan tanggal selesai wajib diisi.' });
    }
    if (new Date(tanggal_selesai) < new Date(tanggal_mulai)) {
      return res.status(400).json({ success: false, message: 'Tanggal selesai tidak boleh mendahului tanggal mulai.' });
    }
    if (!options || !Array.isArray(options) || options.length < 2) {
      return res.status(400).json({ success: false, message: 'Minimal 2 opsi polling diperlukan.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const pollingResult = await client.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, created_by)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, judul, deskripsi, status, tanggal_mulai::text AS tanggal_mulai, tanggal_selesai::text AS tanggal_selesai, created_by, created_at, updated_at`,
        [judul, deskripsi || null, tanggal_mulai, tanggal_selesai, req.user.id]
      );
      const polling = pollingResult.rows[0];
      for (const opt of options) {
        await client.query('INSERT INTO polling_options (polling_id, label) VALUES ($1, $2)', [polling.id, opt]);
      }
      await client.query('COMMIT');
      await logActivity(req, TIPE.CREATE, `Membuat polling "${ringkas(polling.judul)}"`);

      // Siaran push notifikasi FCM polling baru secara non-blocking jika status aktif
      if ((polling.status || '').toLowerCase() === 'aktif') {
        dispatcher.dispatchAsync(() => sendNewPollingPushNotification(polling), 'PollingNew');
      }

      return res.status(201).json({ success: true, message: 'Polling berhasil dibuat.', data: polling });
    } catch (txErr) { 
      await client.query('ROLLBACK'); 
      throw txErr; 
    } finally { 
      client.release(); 
    }
  } catch (err) {
    console.error('CreatePolling Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function vote(req, res) {
  const { id } = req.params;
  const { option_id } = req.body;
  const parsedOptionId = parseInt(option_id, 10);

  if (!option_id || isNaN(parsedOptionId)) {
    return res.status(400).json({ success: false, message: 'option_id wajib diisi dengan format yang benar.' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Kunci baris polling untuk verifikasi status & deadline (mencegah race condition penutupan status)
    const pollingResult = await client.query(
      `SELECT id, judul, status,
        tanggal_mulai::text AS tanggal_mulai,
        tanggal_selesai::text AS tanggal_selesai,
        CASE 
          WHEN tanggal_selesai::text ~ 'T|\\s\\d{2}:' AND NOT tanggal_selesai::text ~ '00:00:00' 
            THEN (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta') > tanggal_selesai::timestamp
          ELSE (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date > tanggal_selesai::date
        END AS lewat_deadline,
        CASE 
          WHEN tanggal_mulai::text ~ 'T|\\s\\d{2}:' AND NOT tanggal_mulai::text ~ '00:00:00' 
            THEN (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta') < tanggal_mulai::timestamp
          ELSE (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date < tanggal_mulai::date
        END AS belum_mulai
      FROM polling 
      WHERE id = $1 
      FOR SHARE`,
      [id]
    );

    if (pollingResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Polling tidak ditemukan.' });
    }

    const polling = pollingResult.rows[0];
    const statusLower = (polling.status || '').toLowerCase();

    if (statusLower !== 'aktif') {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, message: 'Polling sudah ditutup atau tidak aktif.' });
    }

    if (polling.belum_mulai) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, message: 'Polling belum dimulai.' });
    }

    if (polling.lewat_deadline) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, message: 'Polling sudah melewati batas waktu (deadline).' });
    }

    // Pastikan pilihan opsi benar-benar terdaftar pada polling ini
    const opsiResult = await client.query(
      'SELECT id, label FROM polling_options WHERE id = $1 AND polling_id = $2',
      [parsedOptionId, id]
    );
    if (opsiResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, message: 'Pilihan tidak tersedia pada polling ini.' });
    }

    // Kunci baris vote milik pengguna ini jika sudah pernah memilih (mencegah double-submit / race condition)
    const existingVoteResult = await client.query(
      'SELECT id, option_id FROM polling_votes WHERE polling_id = $1 AND user_id = $2 FOR UPDATE',
      [id, req.user.id]
    );

    let isChange = false;
    if (existingVoteResult.rows.length > 0) {
      isChange = true;
      const existingVote = existingVoteResult.rows[0];
      const oldOptionId = existingVote.option_id;

      if (oldOptionId !== parsedOptionId) {
        // Update record vote eksisting (TIDAK menambah record baru)
        await client.query(
          'UPDATE polling_votes SET option_id = $1, created_at = NOW() WHERE id = $2',
          [parsedOptionId, existingVote.id]
        );

        // Update vote_count dengan urutan id terurut untuk mencegah deadlock pada konkurensi tinggi
        const idPertama = Math.min(oldOptionId, parsedOptionId);

        if (idPertama === oldOptionId) {
          await client.query('UPDATE polling_options SET vote_count = GREATEST(0, vote_count - 1) WHERE id = $1', [oldOptionId]);
          await client.query('UPDATE polling_options SET vote_count = vote_count + 1 WHERE id = $1', [parsedOptionId]);
        } else {
          await client.query('UPDATE polling_options SET vote_count = vote_count + 1 WHERE id = $1', [parsedOptionId]);
          await client.query('UPDATE polling_options SET vote_count = GREATEST(0, vote_count - 1) WHERE id = $1', [oldOptionId]);
        }
      }
      // Jika oldOptionId === parsedOptionId (A -> A), tidak ada perubahan vote_count
    } else {
      // Pemilihan pertama kali: Masukkan satu record baru
      await client.query(
        'INSERT INTO polling_votes (polling_id, option_id, user_id) VALUES ($1, $2, $3)',
        [id, parsedOptionId, req.user.id]
      );
      await client.query(
        'UPDATE polling_options SET vote_count = vote_count + 1 WHERE id = $1',
        [parsedOptionId]
      );
    }

    await client.query('COMMIT');

    // Catat log aktivitas sesuai konteks
    await logActivity(
      req,
      isChange ? TIPE.UPDATE : TIPE.CREATE,
      isChange ? `Mengubah suara pada polling #${id}` : `Memberikan suara pada polling #${id}`
    );

    return res.status(200).json({
      success: true,
      message: isChange ? 'Pilihan Anda berhasil diperbarui.' : 'Vote berhasil dicatat.',
      data: {
        polling_id: parseInt(id, 10),
        option_id: parsedOptionId,
        is_change: isChange,
      },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    // Fallback jika terjadi bentrok unique constraint dari transaksi paralel
    if (err.code === '23505') {
      return res.status(409).json({ success: false, message: 'Suara Anda sedang diproses. Silakan coba kembali.' });
    }
    console.error('Vote Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

async function updatePollingStatus(req, res) {
  try {
    const { id } = req.params;
    const { status } = req.body;
    const rawStatus = (status || '').toLowerCase();
    const validStatus = ['aktif', 'ditutup', 'selesai'];
    if (!rawStatus || !validStatus.includes(rawStatus)) {
      return res.status(400).json({ success: false, message: `Status harus salah satu dari: Aktif, Ditutup, Selesai` });
    }
    const formattedStatus = rawStatus.charAt(0).toUpperCase() + rawStatus.slice(1);
    const result = await pool.query(
      'UPDATE polling SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING id, judul, deskripsi, status, tanggal_mulai::text AS tanggal_mulai, tanggal_selesai::text AS tanggal_selesai, created_by, created_at, updated_at',
      [formattedStatus, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Polling tidak ditemukan.' });

    // Menutup polling menghentikan suara yang masuk.
    await logActivity(
      req,
      TIPE.UPDATE,
      `Mengubah status polling "${ringkas(result.rows[0].judul)}" menjadi ${formattedStatus}`
    );

    // Siaran push notifikasi jika status diaktifkan kembali
    if (formattedStatus.toLowerCase() === 'aktif') {
      dispatcher.dispatchAsync(() => sendNewPollingPushNotification(result.rows[0]), 'PollingActivated');
    }

    return res.status(200).json({ success: true, message: `Status polling berhasil diubah menjadi ${formattedStatus}.`, data: result.rows[0] });
  } catch (err) {
    console.error('UpdatePollingStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deletePolling(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM polling WHERE id = $1 RETURNING id, judul', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Polling tidak ditemukan.' });
    await logActivity(req, TIPE.DELETE, `Menghapus polling "${ringkas(result.rows[0].judul)}" beserta seluruh suara yang sudah masuk`);

    return res.status(200).json({ success: true, message: 'Polling berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeletePolling Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getPolling,
  createPolling,
  vote,
  updatePollingStatus,
  deletePolling,
  sendNewPollingPushNotification,
};

