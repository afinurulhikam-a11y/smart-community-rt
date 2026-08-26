const { pool } = require('../config/database');
const { logActivity, rupiah, bandingkan, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const { klausaRt, tolakLuarRt } = require('../utils/lingkup-rt');

const UUID_REGEX = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
function isUUID(val) {
  return typeof val === 'string' && UUID_REGEX.test(val.trim());
}

function toDateOnlyStr(val) {
  if (!val) return null;
  if (val instanceof Date) return val.toISOString().split('T')[0];
  return String(val).split('T')[0].trim();
}

function formatTanggalIndo(val) {
  if (!val) return '-';
  if (val instanceof Date) {
    const bulan = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    return `${val.getDate()} ${bulan[val.getMonth()]} ${val.getFullYear()}`;
  }
  const str = String(val).split('T')[0];
  const parts = str.split('-');
  if (parts.length === 3) {
    const y = parseInt(parts[0], 10);
    const m = parseInt(parts[1], 10) - 1;
    const d = parseInt(parts[2], 10);
    const bulan = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    if (!isNaN(y) && m >= 0 && m < 12 && !isNaN(d)) {
      return `${d} ${bulan[m]} ${y}`;
    }
  }
  return str;
}

function formatPeriodeBansos(row) {
  if (row.tanggal_bantuan) {
    return formatTanggalIndo(row.tanggal_bantuan);
  }
  if (row.tanggal_mulai) {
    const mulai = formatTanggalIndo(row.tanggal_mulai);
    if (row.tanggal_selesai) {
      return `${mulai} s.d. ${formatTanggalIndo(row.tanggal_selesai)}`;
    }
    return `${mulai} s.d. Selesai`;
  }
  if (row.tahun) {
    return String(row.tahun);
  }
  return '-';
}

/**
 * Mengirim notifikasi push FCM ke penerima manfaat saat status bantuan sosial aktif, disalurkan, atau diperbarui.
 *
 * Menggunakan Durable Database Idempotency (bantuan_sosial.fcm_last_status_dispatch).
 * Bersifat fail-safe & non-blocking: kegagalan FCM tidak membatalkan operasi bansos.
 */
async function sendBansosStatusPushNotification(bansos) {
  if (!bansos || !bansos.id) {
    return { skipped: true, reason: 'invalid_bansos' };
  }

  const targetStatus = bansos.status || 'Aktif';

  try {
    // 1. Klaim atomik status dispatch (Race Condition & Durable Idempotency Guard)
    const claimResult = await pool.query(
      `UPDATE bantuan_sosial
       SET fcm_last_status_dispatch = $1
       WHERE id = $2
         AND (fcm_last_status_dispatch IS NULL OR fcm_last_status_dispatch != $1)
       RETURNING id, user_id, jenis_bantuan, bentuk_bantuan, sumber_bantuan, no_sk,
                 tanggal_bantuan::text AS tanggal_bantuan,
                 tanggal_mulai::text AS tanggal_mulai,
                 tanggal_selesai::text AS tanggal_selesai,
                 tahun, nominal, status, keterangan`,
      [targetStatus, bansos.id]
    );

    if (claimResult.rows.length === 0) {
      console.log(`ℹ️ [FCM Bansos] Status Bantuan Sosial #${bansos.id} sudah pernah dikirim (${targetStatus}) atau tidak berubah, push dilewati.`);
      return { skipped: true, reason: 'already_sent_or_unchanged' };
    }

    const currentBansos = claimResult.rows[0];

    // 2. Ambil data user penerima manfaat yang aktif
    if (!currentBansos.user_id) {
      console.log(`ℹ️ [FCM Bansos] Bantuan Sosial #${bansos.id} tidak memiliki user_id penerima, push dilewati.`);
      return { skipped: true, reason: 'missing_user_id' };
    }

    const userRes = await pool.query(
      `SELECT id, nama, is_active FROM users WHERE id = $1`,
      [currentBansos.user_id]
    );

    if (userRes.rows.length === 0 || !userRes.rows[0].is_active) {
      console.log(`ℹ️ [FCM Bansos] Penerima bansos #${bansos.id} tidak ditemukan atau nonaktif, push dilewati.`);
      return { skipped: true, reason: 'inactive_or_missing_user' };
    }

    const recipientUser = userRes.rows[0];
    const namaProgram = currentBansos.jenis_bantuan || 'Bantuan Sosial';
    const descPeriode = formatPeriodeBansos(currentBansos);

    let title = `🎁 Bantuan Sosial: ${namaProgram}`;
    let body = `Anda terdaftar sebagai penerima program bantuan sosial "${namaProgram}" (${descPeriode}). Status: ${currentBansos.status}.`;

    if (targetStatus.toLowerCase() === 'selesai') {
      title = `✅ Bantuan Sosial Disalurkan: ${namaProgram}`;
      body = `Penyaluran bantuan sosial "${namaProgram}" (${descPeriode}) telah selesai disalurkan.`;
    } else if (targetStatus.toLowerCase() === 'dibatalkan') {
      title = `ℹ️ Status Bantuan Sosial: ${namaProgram}`;
      body = `Status kepesertaan bantuan sosial "${namaProgram}" (${descPeriode}) telah diperbarui menjadi Dibatalkan.`;
    }

    const pushResult = await dispatcher.sendToUser(recipientUser.id, {
      title,
      body,
      data: {
        entity_type: 'bansos',
        entity_id: String(currentBansos.id),
        action: 'BANSOS_STATUS_UPDATE',
        status: String(currentBansos.status || 'Aktif'),
        nama_program: String(namaProgram),
        periode: String(descPeriode),
        bentuk_bantuan: String(currentBansos.bentuk_bantuan || 'Tunai'),
        sumber_bantuan: String(currentBansos.sumber_bantuan || 'Pemerintah Pusat'),
        nominal: String(currentBansos.nominal || '0'),
      },
      priority: 'normal',
      collapseKey: `bansos_status_${currentBansos.id}`,
    });

    if (pushResult.success === false && !pushResult.simulated) {
      // Revert status claim on failure so retry can happen
      await pool.query('UPDATE bantuan_sosial SET fcm_last_status_dispatch = NULL WHERE id = $1', [currentBansos.id]).catch(() => {});
      console.error(`⚠️ [FCM Bansos] Gagal mengirim push status bansos #${currentBansos.id}:`, pushResult.error);
      return pushResult;
    }

    console.log(
      `🔔 [FCM Bansos] Notifikasi Status Bansos #${currentBansos.id} [${namaProgram} -> ${targetStatus}]:\n` +
      `   - Target Penerima : ${recipientUser.nama} (${recipientUser.id})\n` +
      `   - Total Token     : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil        : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal           : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode            : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query('UPDATE bantuan_sosial SET fcm_last_status_dispatch = NULL WHERE id = $1', [bansos.id]).catch(() => {});
    console.error(`⚠️ [FCM Bansos] Gagal memproses dispatch bansos #${bansos.id}:`, err.message);
    return { error: err.message };
  }
}

function buildDateFilter(tahun, start, end, params) {
  let dateClause = '';
  let startDate = start;
  let endDate = end;

  if (tahun && tahun !== 'Semua') {
    const y = parseInt(tahun, 10);
    if (!isNaN(y)) {
      startDate = `${y}-01-01`;
      endDate = `${y}-12-31`;
    }
  }

  if (startDate && endDate) {
    params.push(startDate);
    const pStart = params.length;
    params.push(endDate);
    const pEnd = params.length;
    params.push(parseInt(startDate.split('-')[0], 10));
    const pYear = params.length;

    dateClause = ` AND (
      (bs.tanggal_bantuan >= $${pStart} AND bs.tanggal_bantuan <= $${pEnd})
      OR (bs.tanggal_mulai <= $${pEnd} AND (bs.tanggal_selesai >= $${pStart} OR bs.tanggal_selesai IS NULL))
      OR (bs.tanggal_bantuan IS NULL AND bs.tanggal_mulai IS NULL AND bs.tahun = $${pYear})
    )`;
  } else if (startDate) {
    params.push(startDate);
    const pStart = params.length;
    params.push(parseInt(startDate.split('-')[0], 10));
    const pYear = params.length;

    dateClause = ` AND (
      bs.tanggal_bantuan >= $${pStart}
      OR bs.tanggal_mulai >= $${pStart}
      OR (bs.tanggal_bantuan IS NULL AND bs.tanggal_mulai IS NULL AND bs.tahun = $${pYear})
    )`;
  } else if (endDate) {
    params.push(endDate);
    const pEnd = params.length;
    params.push(parseInt(endDate.split('-')[0], 10));
    const pYear = params.length;

    dateClause = ` AND (
      bs.tanggal_bantuan <= $${pEnd}
      OR (bs.tanggal_mulai <= $${pEnd} AND (bs.tanggal_selesai <= $${pEnd} OR bs.tanggal_selesai IS NULL))
      OR (bs.tanggal_bantuan IS NULL AND bs.tanggal_mulai IS NULL AND bs.tahun = $${pYear})
    )`;
  }

  return dateClause;
}

async function getBantuanSosial(req, res) {
  try {
    const { tahun, tanggal_mulai, tanggal_selesai, jenis_bantuan, status, search } = req.query;
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(Math.max(1, parseInt(req.query.limit, 10) || 10), 100);
    const offset = (page - 1) * limit;

    let where = 'WHERE 1=1';
    const params = [];

    // Pelingkupan RT, dipasang sebelum penyaringan lain supaya daftar dan
    // penghitungan totalnya memakai batas yang sama persis.
    where += klausaRt(req, 'bs', params);

    if (req.user.role === 'warga') {
      params.push(req.user.id);
      where += ` AND bs.user_id = $${params.length}`;
    }

    where += buildDateFilter(tahun, tanggal_mulai, tanggal_selesai, params);

    if (jenis_bantuan && jenis_bantuan !== 'Semua Jenis') { params.push(jenis_bantuan); where += ` AND bs.jenis_bantuan = $${params.length}`; }
    if (status && status !== 'Semua Status') { params.push(status); where += ` AND bs.status = $${params.length}`; }
    if (search) { params.push(`%${search}%`); where += ` AND (u.nama ILIKE $${params.length} OR COALESCE(u.nik, u.username) ILIKE $${params.length})`; }

    const countResult = await pool.query(
      `SELECT COUNT(*) AS total FROM bantuan_sosial bs
       JOIN users u ON bs.user_id = u.id
       ${where}`,
      params
    );
    const totalData = parseInt(countResult.rows[0].total, 10);
    const totalPages = Math.ceil(totalData / limit);

    const result = await pool.query(
      `SELECT bs.*, u.nama AS nama_warga, COALESCE(u.nik, u.username) AS nik_warga, c.nama AS created_by_nama
       FROM bantuan_sosial bs
       JOIN users u ON bs.user_id = u.id
       LEFT JOIN users c ON bs.created_by = c.id
       ${where}
       ORDER BY bs.created_at DESC
       LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, limit, offset]
    );

    return res.status(200).json({
      success: true,
      count: result.rows.length,
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        per_page: limit,
      },
      data: result.rows,
    });
  } catch (err) {
    console.error('GetBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getBantuanSosialStats(req, res) {
  try {
    // Satu kueri, bukan empat — alasannya sama dengan getVisitorStats:
    // penyaring yang ditulis empat kali adalah penyaring yang cepat atau
    // lambat berbeda di salah satunya, dan kartu yang salah hitung tidak
    // punya gejala apa pun selain angkanya.
    const params = [];
    let where = 'WHERE 1=1';
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      where += ` AND user_id = $${params.length}`;
    }
    where += klausaRt(req, '', params);

    const hasil = await pool.query(`
      SELECT
        COUNT(*)::int AS total_penerima,
        COUNT(*) FILTER (WHERE status = 'Aktif')::int AS aktif,
        COUNT(*) FILTER (WHERE status = 'Selesai')::int AS selesai,
        COUNT(DISTINCT jenis_bantuan)
          FILTER (WHERE status = 'Aktif')::int AS jenis_aktif
      FROM bantuan_sosial
      ${where}
    `, params);

    return res.status(200).json({ success: true, data: hasil.rows[0] });
  } catch (err) {
    console.error('GetBantuanSosialStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createBantuanSosial(req, res) {
  try {
    const {
      user_id,
      jenis_bantuan,
      bentuk_bantuan,
      sumber_bantuan,
      no_sk,
      tanggal_bantuan,
      tanggal_mulai,
      tanggal_selesai,
      tahun,
      nominal,
      keterangan,
    } = req.body;

    if (!user_id || !jenis_bantuan) {
      return res.status(400).json({ success: false, message: 'user_id dan jenis_bantuan wajib diisi.' });
    }

    if (!isUUID(user_id)) {
      return res.status(400).json({ success: false, message: 'ID Warga tidak valid.' });
    }

    const tBantuan = tanggal_bantuan ? String(tanggal_bantuan).trim() : null;
    const tMulai = tanggal_mulai ? String(tanggal_mulai).trim() : null;
    const tSelesai = tanggal_selesai ? String(tanggal_selesai).trim() : null;
    const bBantuan = bentuk_bantuan ? String(bentuk_bantuan).trim() : 'Tunai';
    const sBantuan = sumber_bantuan ? String(sumber_bantuan).trim() : 'Pemerintah Pusat';
    const skFinal = no_sk ? String(no_sk).trim() : null;

    if (!tBantuan && !tMulai && !tahun) {
      return res.status(400).json({ success: false, message: 'Tanggal bantuan atau tanggal mulai wajib diisi.' });
    }

    if (tMulai && tSelesai && tSelesai < tMulai) {
      return res.status(400).json({ success: false, message: 'Tanggal selesai tidak boleh lebih awal dari tanggal mulai.' });
    }

    let nominalAngka = 0;
    if (nominal !== undefined && nominal !== null && nominal !== '') {
      const n = Number(nominal);
      if (!Number.isFinite(n) || n < 0) {
        return res.status(400).json({ success: false, message: 'Nominal wajib diisi dan tidak boleh negatif.' });
      }
      nominalAngka = n;
    } else if (bBantuan === 'Tunai') {
      return res.status(400).json({ success: false, message: 'Nominal wajib diisi untuk bantuan Tunai.' });
    }

    const ketFinal = (keterangan || '').toString().trim();
    if (nominalAngka === 0 && bBantuan === 'Tunai' && ketFinal === '') {
      return res.status(400).json({ success: false, message: 'Keterangan wajib diisi bila nominal Tunai 0.' });
    }

    const userCheck = await pool.query('SELECT id FROM users WHERE id = $1', [user_id]);
    if (userCheck.rows.length === 0) return res.status(404).json({ success: false, message: 'Warga tidak ditemukan.' });

    let tahunHitung = tahun ? parseInt(tahun, 10) : null;
    if (!tahunHitung) {
      const refDateStr = tBantuan || tMulai;
      if (refDateStr) {
        tahunHitung = parseInt(refDateStr.split('-')[0], 10) || new Date(refDateStr).getFullYear();
      }
    }

    const dupCheck = await pool.query(
      `SELECT id FROM bantuan_sosial
       WHERE user_id = $1 AND jenis_bantuan = $2
         AND (
           ($3::date IS NOT NULL AND tanggal_bantuan = $3::date)
           OR ($4::date IS NOT NULL AND (
             (tanggal_mulai IS NOT NULL AND tanggal_mulai <= COALESCE($5::date, '9999-12-31') AND COALESCE(tanggal_selesai, '9999-12-31') >= $4::date)
             OR (tanggal_bantuan IS NOT NULL AND tanggal_bantuan >= $4::date AND tanggal_bantuan <= COALESCE($5::date, '9999-12-31'))
           ))
           OR ($6::int IS NOT NULL AND tahun = $6::int AND tanggal_bantuan IS NULL AND tanggal_mulai IS NULL)
         )`,
      [user_id, jenis_bantuan, tBantuan, tMulai, tSelesai, tahunHitung]
    );
    if (dupCheck.rows.length > 0) {
      return res.status(409).json({ success: false, message: 'Warga sudah terdaftar untuk jenis bantuan ini pada tanggal/periode tersebut.' });
    }

    const result = await pool.query(
      `INSERT INTO bantuan_sosial (user_id, jenis_bantuan, bentuk_bantuan, sumber_bantuan, no_sk, tanggal_bantuan, tanggal_mulai, tanggal_selesai, tahun, nominal, keterangan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING *`,
      [user_id, jenis_bantuan, bBantuan, sBantuan, skFinal, tBantuan, tMulai, tSelesai, tahunHitung, nominalAngka, ketFinal || null, req.user.id]
    );

    const rowBaru = result.rows[0];
    const penerima = await pool.query('SELECT nama FROM users WHERE id = $1', [user_id]);
    const descPeriode = formatPeriodeBansos(rowBaru);
    await logActivity(
      req,
      TIPE.CREATE,
      `Menetapkan penerima bantuan sosial: ${penerima.rows[0]?.nama || user_id} — ` +
        `${jenis_bantuan} (${descPeriode}), ${bBantuan === 'Tunai' ? rupiah(nominalAngka) : bBantuan}`
    );

    // Siaran push notifikasi FCM penerimaan bansos secara non-blocking
    dispatcher.dispatchAsync(() => sendBansosStatusPushNotification(rowBaru), 'BansosNew');

    return res.status(201).json({ success: true, message: 'Penerima bantuan berhasil ditambahkan.', data: rowBaru });
  } catch (err) {
    console.error('CreateBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateBantuanSosial(req, res) {
  try {
    const { id } = req.params;
    const numId = parseInt(id, 10);
    if (isNaN(numId) || numId <= 0) {
      return res.status(400).json({ success: false, message: 'ID Bantuan Sosial tidak valid.' });
    }
    if (await tolakLuarRt(pool, req, res, 'bantuan_sosial', numId)) return;

    const {
      jenis_bantuan,
      bentuk_bantuan,
      sumber_bantuan,
      no_sk,
      tanggal_bantuan,
      tanggal_mulai,
      tanggal_selesai,
      tahun,
      nominal,
      status,
      keterangan,
    } = req.body;

    const oldData = await pool.query('SELECT * FROM bantuan_sosial WHERE id = $1', [numId]);
    if (oldData.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });

    const old = oldData.rows[0];

    const bBantuan = bentuk_bantuan !== undefined ? (bentuk_bantuan ? String(bentuk_bantuan).trim() : 'Tunai') : old.bentuk_bantuan;
    const sBantuan = sumber_bantuan !== undefined ? (sumber_bantuan ? String(sumber_bantuan).trim() : 'Pemerintah Pusat') : old.sumber_bantuan;
    const skFinal = no_sk !== undefined ? (no_sk ? String(no_sk).trim() : null) : old.no_sk;

    let nominalBaru = old.nominal ? Number(old.nominal) : 0;
    if (nominal !== undefined && nominal !== null && nominal !== '') {
      const n = Number(nominal);
      if (!Number.isFinite(n) || n < 0) {
        return res.status(400).json({ success: false, message: 'Nominal harus berupa angka tidak negatif.' });
      }
      nominalBaru = n;
    } else if (bBantuan === 'Tunai' && (nominal === '' || nominal === null)) {
      return res.status(400).json({ success: false, message: 'Nominal wajib diisi untuk bantuan Tunai.' });
    }

    const oldTBantuanStr = toDateOnlyStr(old.tanggal_bantuan);
    const oldTMulaiStr = toDateOnlyStr(old.tanggal_mulai);
    const oldTSelesaiStr = toDateOnlyStr(old.tanggal_selesai);

    const tBantuan = tanggal_bantuan !== undefined ? (tanggal_bantuan ? String(tanggal_bantuan).trim() : null) : oldTBantuanStr;
    const tMulai = tanggal_mulai !== undefined ? (tanggal_mulai ? String(tanggal_mulai).trim() : null) : oldTMulaiStr;
    const tSelesai = tanggal_selesai !== undefined ? (tanggal_selesai ? String(tanggal_selesai).trim() : null) : oldTSelesaiStr;

    if (tMulai && tSelesai && tSelesai < tMulai) {
      return res.status(400).json({ success: false, message: 'Tanggal selesai tidak boleh lebih awal dari tanggal mulai.' });
    }

    let tahunHitung = tahun !== undefined ? (tahun ? parseInt(tahun, 10) : null) : old.tahun;
    if (tanggal_bantuan !== undefined || tanggal_mulai !== undefined) {
      const refDateStr = tBantuan || tMulai;
      if (refDateStr) {
        tahunHitung = parseInt(String(refDateStr).split('-')[0], 10) || new Date(refDateStr).getFullYear();
      }
    }

    const result = await pool.query(
      `UPDATE bantuan_sosial SET
        jenis_bantuan = COALESCE($1, jenis_bantuan),
        bentuk_bantuan = COALESCE($2, bentuk_bantuan),
        sumber_bantuan = COALESCE($3, sumber_bantuan),
        no_sk = $4,
        tanggal_bantuan = $5::date,
        tanggal_mulai = $6::date,
        tanggal_selesai = $7::date,
        tahun = COALESCE($8, tahun),
        nominal = $9,
        status = COALESCE($10, status),
        keterangan = COALESCE($11, keterangan),
        updated_at = NOW()
       WHERE id = $12 RETURNING *`,
      [jenis_bantuan, bBantuan, sBantuan, skFinal, tBantuan, tMulai, tSelesai, tahunHitung, nominalBaru, status, keterangan, numId]
    );

    const changes = [];
    if (jenis_bantuan && old.jenis_bantuan !== jenis_bantuan) changes.push('Jenis Bantuan');
    if (bBantuan && old.bentuk_bantuan !== bBantuan) changes.push('Bentuk Bantuan');
    if (sBantuan && old.sumber_bantuan !== sBantuan) changes.push('Sumber Bantuan');
    if (skFinal !== old.no_sk) changes.push('No. SK');
    if (tBantuan !== oldTBantuanStr) changes.push('Tanggal Bantuan');
    if (tMulai !== oldTMulaiStr) changes.push('Tanggal Mulai');
    if (tSelesai !== oldTSelesaiStr) changes.push('Tanggal Selesai');
    if (nominal !== undefined && Number(old.nominal) !== Number(nominalBaru)) changes.push('Nominal');
    if (keterangan !== undefined && old.keterangan !== keterangan) changes.push('Keterangan');
    if (status && old.status !== status) changes.push('Status');

    if (changes.length > 0) {
      const ket_log = `Mengubah: ${changes.join(', ')}`;
      await pool.query(
        'INSERT INTO bantuan_sosial_log (bantuan_sosial_id, changed_by, old_status, new_status, keterangan_log) VALUES ($1, $2, $3, $4, $5)',
        [numId, req.user.id, old.status, status || old.status, ket_log]
      );

      const penerima = await pool.query(
        'SELECT u.nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id WHERE bs.id = $1',
        [numId]
      );
      const rincian = bandingkan(old, result.rows[0], {
        jenis_bantuan: 'jenis',
        bentuk_bantuan: 'bentuk',
        sumber_bantuan: 'sumber',
        no_sk: 'No. SK',
        tanggal_bantuan: 'tanggal bantuan',
        tanggal_mulai: 'tanggal mulai',
        tanggal_selesai: 'tanggal selesai',
        nominal: 'nominal',
        status: 'status',
      });
      await logActivity(
        req,
        TIPE.UPDATE,
        `Mengubah bantuan sosial ${penerima.rows[0]?.nama || numId} — ${rincian || ket_log}`
      );
    }

    // Siaran push notifikasi jika status bansos diperbarui
    if (status && old.status !== status) {
      dispatcher.dispatchAsync(() => sendBansosStatusPushNotification(result.rows[0]), 'BansosStatusUpdate');
    }

    return res.status(200).json({ success: true, message: 'Data bantuan berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getBantuanSosialHistory(req, res) {
  try {
    const { id } = req.params;
    const numId = parseInt(id, 10);
    if (isNaN(numId) || numId <= 0) {
      return res.status(400).json({ success: false, message: 'ID Bantuan Sosial tidak valid.' });
    }
    if (await tolakLuarRt(pool, req, res, 'bantuan_sosial', numId)) return;

    const result = await pool.query(
      `SELECT log.*, u.nama AS changed_by_name 
       FROM bantuan_sosial_log log 
       LEFT JOIN users u ON log.changed_by = u.id 
       WHERE log.bantuan_sosial_id = $1
         ${req.user.role === 'warga'
    ? 'AND EXISTS (SELECT 1 FROM bantuan_sosial bs WHERE bs.id = log.bantuan_sosial_id AND bs.user_id = $2)'
    : ''}
       ORDER BY log.created_at DESC`,
      req.user.role === 'warga' ? [numId, req.user.id] : [numId]
    );
    return res.status(200).json({ success: true, data: result.rows });
  } catch (err) {
    console.error('GetBantuanSosialHistory Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteBantuanSosial(req, res) {
  try {
    const { id } = req.params;
    const numId = parseInt(id, 10);
    if (isNaN(numId) || numId <= 0) {
      return res.status(400).json({ success: false, message: 'ID Bantuan Sosial tidak valid.' });
    }
    if (await tolakLuarRt(pool, req, res, 'bantuan_sosial', numId)) return;

    const item = await pool.query(
      'SELECT bs.*, u.nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id WHERE bs.id = $1',
      [numId]
    );
    if (item.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });

    const result = await pool.query('DELETE FROM bantuan_sosial WHERE id = $1 RETURNING id', [numId]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });

    const d = item.rows[0];
    const descPeriode = formatPeriodeBansos(d);
    await logActivity(
      req,
      TIPE.DELETE,
      `Menghapus data bantuan sosial: ${d.nama || numId} — ${d.jenis_bantuan} (${descPeriode})`
    );

    return res.status(200).json({ success: true, message: 'Data bantuan sosial berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function exportBantuanSosial(req, res) {
  try {
    const { tahun, tanggal_mulai, tanggal_selesai, jenis_bantuan, status, search, format = 'excel' } = req.query;
    let where = '';
    const params = [];

    // Sama seperti getBantuanSosial. Daftar dan ekspornya adalah dua jalur
    // untuk operasi yang sama, dan penjagaan yang hanya dipasang di salah
    // satunya adalah pola yang sudah pernah menggigit proyek ini — `payBill`
    // terkunci sementara `payBillsBulk` tidak. Di sini akibatnya justru lebih
    // besar: daftar yang tersaring tetapi ekspor yang tidak berarti seluruh
    // penerima bantuan se-RW terunduh menjadi satu berkas Excel.
    where += klausaRt(req, 'bs', params);

    const dateClause = buildDateFilter(tahun, tanggal_mulai, tanggal_selesai, params);
    where += dateClause;

    if (jenis_bantuan && jenis_bantuan !== 'Semua Jenis') { params.push(jenis_bantuan); where += ` AND bs.jenis_bantuan = $${params.length}`; }
    if (status && status !== 'Semua Status') { params.push(status); where += ` AND bs.status = $${params.length}`; }
    if (search) {
      params.push(`%${search}%`);
      where += ` AND (u.nama ILIKE $${params.length} OR u.nik ILIKE $${params.length} OR u.username ILIKE $${params.length} OR bs.jenis_bantuan ILIKE $${params.length} OR bs.no_sk ILIKE $${params.length})`;
    }

    if (req.user.role === 'warga') {
      params.push(req.user.id);
      where += ` AND bs.user_id = $${params.length}`;
    }

    let query = `SELECT bs.*, u.nama AS nama_warga, COALESCE(u.nik, u.username) AS nik_warga, c.nama AS created_by_nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id LEFT JOIN users c ON bs.created_by = c.id WHERE 1=1`;
    query += where;
    query += ' ORDER BY COALESCE(bs.tanggal_bantuan, bs.tanggal_mulai) DESC, bs.id DESC';

    const result = await pool.query(query, params);
    const data = result.rows;

    if (format === 'pdf') {
      const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-disposition', 'attachment; filename=Data_Bantuan_Sosial.pdf');
      doc.pipe(res);

      doc.fontSize(16).text('Laporan Data Bantuan Sosial RT', { align: 'center' });
      doc.fontSize(10).text(`Dicetak pada: ${new Date().toLocaleString('id-ID')}`, { align: 'center' });
      doc.moveDown(2);

      const tableData = {
        headers: ['No', 'Nama Penerima', 'NIK / ID', 'Jenis Bantuan', 'Bentuk', 'Sumber', 'No. SK', 'Tanggal/Periode', 'Status', 'Nominal'],
        rows: data.map((d, i) => [
          i + 1,
          d.nama_warga || '-',
          d.nik_warga || '-',
          d.jenis_bantuan || '-',
          d.bentuk_bantuan || 'Tunai',
          d.sumber_bantuan || 'Pemerintah Pusat',
          d.no_sk || '-',
          formatPeriodeBansos(d),
          d.status || 'Aktif',
          d.nominal ? rupiah(d.nominal) : '-'
        ])
      };

      await doc.table(tableData, {
        prepareHeader: () => doc.fontSize(8).font('Helvetica-Bold'),
        prepareRow: (row, indexColumn, indexRow, rectRow, rectCell) => {
          doc.fontSize(8).font('Helvetica');
          if (indexRow % 2 === 0) {
            doc.addBackground(rectCell, '#f9fafb', 1);
          }
        },
      });

      doc.end();
    } else {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Data Bansos');

      sheet.columns = [
        { header: 'No', key: 'no', width: 5 },
        { header: 'Nama Penerima', key: 'nama', width: 25 },
        { header: 'NIK / ID', key: 'nik', width: 20 },
        { header: 'Jenis Bantuan', key: 'jenis', width: 20 },
        { header: 'Bentuk Bantuan', key: 'bentuk', width: 18 },
        { header: 'Sumber Bantuan', key: 'sumber', width: 22 },
        { header: 'No. SK / Ref', key: 'no_sk', width: 20 },
        { header: 'Tanggal / Periode', key: 'periode', width: 25 },
        { header: 'Status', key: 'status', width: 15 },
        { header: 'Nominal', key: 'nominal', width: 15 },
        { header: 'Keterangan', key: 'ket', width: 30 }
      ];

      data.forEach((d, i) => {
        sheet.addRow({
          no: i + 1,
          nama: d.nama_warga,
          nik: d.nik_warga,
          jenis: d.jenis_bantuan,
          bentuk: d.bentuk_bantuan || 'Tunai',
          sumber: d.sumber_bantuan || 'Pemerintah Pusat',
          no_sk: d.no_sk || '-',
          periode: formatPeriodeBansos(d),
          status: d.status,
          nominal: d.nominal,
          ket: d.keterangan
        });
      });

      res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      res.setHeader('Content-Disposition', 'attachment; filename=Data_Bantuan_Sosial.xlsx');
      await workbook.xlsx.write(res);
      res.end();
    }
  } catch (err) {
    console.error('ExportBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal export data.' });
  }
}

module.exports = {
  getBantuanSosial,
  getBantuanSosialStats,
  createBantuanSosial,
  updateBantuanSosial,
  deleteBantuanSosial,
  exportBantuanSosial,
  getBantuanSosialHistory,
  sendBansosStatusPushNotification,
};
