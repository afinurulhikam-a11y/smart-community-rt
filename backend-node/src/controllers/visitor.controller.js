const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');
const { klausaRt, tolakLuarRt, rtUntukSimpan } = require('../utils/lingkup-rt');

/**
 * Mengirim notifikasi push FCM ke warga tujuan saat tamu tiba / dicatat di pos keamanan.
 *
 * Menggunakan Durable Database Idempotency (visitors.fcm_dispatch_status).
 * Bersifat fail-safe & non-blocking: kegagalan FCM tidak membatalkan registrasi tamu.
 */
async function sendVisitorArrivalPushNotification(visitor, options = {}) {
  if (!visitor || !visitor.id) {
    return { skipped: true, reason: 'invalid_visitor' };
  }

  try {
    // 1. Klaim atomik status dispatch (Race Condition & Durable Idempotency Guard)
    const claimResult = await pool.query(
      `UPDATE visitors
       SET fcm_dispatch_status = 'pending'
       WHERE id = $1
         AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
       RETURNING id, nama_tamu, blok_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan, jam_masuk, created_by`,
      [visitor.id]
    );

    if (claimResult.rows.length === 0) {
      console.log(`ℹ️ [FCM Visitor] Kedatangan Tamu #${visitor.id} sudah pernah dikirim atau sedang diproses, siaran duplikat dicegah.`);
      return { skipped: true, reason: 'already_sent_or_pending' };
    }

    const currentVisitor = claimResult.rows[0];
    const targetUserId = options.target_user_id || options.user_id || currentVisitor.created_by;

    if (!targetUserId) {
      await pool.query(`UPDATE visitors SET fcm_dispatch_status = 'failed' WHERE id = $1`, [visitor.id]).catch(() => {});
      console.log(`ℹ️ [FCM Visitor] Warga tujuan untuk tamu #${visitor.id} tidak terdefinisi, push dilewati.`);
      return { skipped: true, reason: 'missing_target_user' };
    }

    // 2. Ambil informasi warga tujuan yang aktif
    const userRes = await pool.query(
      `SELECT id, nama, is_active FROM users WHERE id = $1`,
      [targetUserId]
    );

    if (userRes.rows.length === 0 || !userRes.rows[0].is_active) {
      await pool.query(`UPDATE visitors SET fcm_dispatch_status = 'failed' WHERE id = $1`, [visitor.id]).catch(() => {});
      console.log(`ℹ️ [FCM Visitor] Warga tujuan untuk tamu #${visitor.id} tidak ditemukan atau nonaktif, push dilewati.`);
      return { skipped: true, reason: 'inactive_or_missing_user' };
    }

    const hostUser = userRes.rows[0];
    const namaTamu = currentVisitor.nama_tamu || 'Tamu';
    const kendaraan = currentVisitor.plat_nomor
      ? ` (${currentVisitor.plat_nomor})`
      : (currentVisitor.jenis_kendaraan ? ` (${currentVisitor.jenis_kendaraan})` : '');
    const keperluan = currentVisitor.tipe_keperluan || 'Kunjungan';

    const title = `🚗 Tamu Tiba di Pos Keamanan: ${namaTamu}`;
    const body = `Tamu atas nama ${namaTamu}${kendaraan} telah tercatat tiba di pos keamanan untuk keperluan ${keperluan}.`;

    const pushResult = await dispatcher.sendToUser(hostUser.id, {
      title,
      body,
      data: {
        entity_type: 'visitor',
        entity_id: String(visitor.id),
        action: 'VISITOR_ARRIVED',
        nama_tamu: String(namaTamu),
        kendaraan: String(currentVisitor.plat_nomor || currentVisitor.jenis_kendaraan || '-'),
        blok_tujuan: String(currentVisitor.blok_tujuan || '-'),
        tipe_keperluan: String(keperluan),
        detail_keperluan: String(currentVisitor.detail_keperluan || '-'),
        jam_masuk: String(currentVisitor.jam_masuk || new Date().toISOString()),
      },
      priority: 'high',
      collapseKey: `visitor_arrived_${visitor.id}`,
    });

    if (pushResult.success === false && !pushResult.simulated) {
      await pool.query(`UPDATE visitors SET fcm_dispatch_status = 'failed' WHERE id = $1`, [visitor.id]).catch(() => {});
      console.error(`⚠️ [FCM Visitor] Gagal mengirim push kedatangan tamu #${visitor.id}:`, pushResult.error);
      return pushResult;
    }

    await pool.query(`UPDATE visitors SET fcm_dispatch_status = 'sent' WHERE id = $1`, [visitor.id]).catch(() => {});

    console.log(
      `🔔 [FCM Visitor] Notifikasi Tamu Tiba #${visitor.id} [${namaTamu} -> ${hostUser.nama}]:\n` +
      `   - Target Warga : ${hostUser.nama} (${hostUser.id})\n` +
      `   - Total Token  : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil     : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal        : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode         : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(`UPDATE visitors SET fcm_dispatch_status = 'failed' WHERE id = $1`, [visitor.id]).catch(() => {});
    console.error('⚠️ [FCM Visitor] Error dispatch kedatangan tamu:', err.message);
    return { error: err.message };
  }
}

async function getVisitors(req, res) {
  try {
    const { status, tipe, search, tanggal, page: rawPage, limit: rawLimit } = req.query;

    const page = Math.max(parseInt(rawPage, 10) || 1, 1);
    const limit = Math.min(Math.max(parseInt(rawLimit, 10) || 10, 1), 100);
    const offset = (page - 1) * limit;

    let baseQuery = `FROM visitors v LEFT JOIN users u ON v.created_by = u.id WHERE 1=1`;
    const params = [];
    // Pelingkupan RT. Dipasang sebelum penyaringan lain supaya daftar,
    // penghitungan total, dan export memakai batas yang sama persis.
    baseQuery += klausaRt(req, 'v', params);

    // Warga hanya melihat tamu yang didaftarkannya sendiri
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      baseQuery += ` AND v.created_by = $${params.length}`;
    }

    if (status && status !== 'Semua Status') { params.push(status); baseQuery += ` AND v.status = $${params.length}`; }
    if (tipe && tipe !== 'Semua Tipe') { params.push(tipe); baseQuery += ` AND v.tipe_keperluan = $${params.length}`; }
    if (tanggal) { params.push(tanggal); baseQuery += ` AND v.jam_masuk::DATE = $${params.length}::DATE`; }
    if (search) { params.push(`%${search}%`); baseQuery += ` AND (v.nama_tamu ILIKE $${params.length} OR v.blok_tujuan ILIKE $${params.length} OR v.plat_nomor ILIKE $${params.length})`; }

    const countResult = await pool.query(`SELECT COUNT(*) as count ${baseQuery}`, params);
    const totalData = parseInt(countResult.rows[0].count, 10);
    const totalPages = Math.max(Math.ceil(totalData / limit), 1);

    const dataParams = [...params, limit, offset];
    const dataQuery = `SELECT v.*, u.nama AS created_by_nama ${baseQuery} ORDER BY v.jam_masuk DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    const result = await pool.query(dataQuery, dataParams);

    return res.status(200).json({
      success: true,
      count: result.rows.length,
      data: result.rows,
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        per_page: limit,
      },
    });
  } catch (err) {
    console.error('GetVisitors Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getVisitorStats(req, res) {
  try {
    // Satu kueri, bukan empat.
    //
    // Keempatnya sebelumnya menuliskan penyaringnya sendiri, dengan nomor $n
    // yang berbeda-beda karena kebetulan jumlah parameternya berbeda: `$2`
    // pada yang pertama, `$1` pada tiga sisanya. Bentuk itu benar hanya
    // selama tidak ada penyaring baru — dan pelingkupan RT adalah penyaring
    // baru yang harus masuk ke keempatnya sekaligus. Menambahkannya empat
    // kali berarti empat kesempatan untuk salah menomori, dan satu kartu yang
    // luput menghitung seluruh RW terlihat persis seperti kartu yang benar.
    //
    // Digabung menjadi satu lintasan tabel dengan FILTER, jadi penyaringnya
    // ditulis SEKALI dan tidak mungkin berbeda antar kartu.
    const today = new Date().toISOString().split('T')[0];
    const params = [today];
    let where = 'WHERE 1=1';
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      where += ` AND created_by = $${params.length}`;
    }
    where += klausaRt(req, '', params);

    const hasil = await pool.query(`
      SELECT
        COUNT(*) FILTER (WHERE jam_masuk::DATE = $1::DATE)::int AS tamu_hari_ini,
        COUNT(*) FILTER (WHERE status = 'Di Dalam')::int AS sedang_di_dalam,
        COUNT(*) FILTER (
          WHERE tipe_keperluan = 'Menginap' AND status = 'Di Dalam'
        )::int AS tamu_menginap,
        COUNT(*)::int AS total_semua
      FROM visitors
      ${where}
    `, params);

    return res.status(200).json({ success: true, data: hasil.rows[0] });
  } catch (err) {
    console.error('GetVisitorStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createVisitor(req, res) {
  try {
    const { nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan, user_id, created_by } = req.body;

    // Validasi: kolom wajib diisi
    const kosong = [];
    if (!nama_tamu?.trim()) kosong.push('Nama Tamu');
    if (!no_hp_tamu?.trim()) kosong.push('No. HP Tamu');
    if (!blok_tujuan?.trim()) kosong.push('Blok Tujuan');
    if (!no_hp_tujuan?.trim()) kosong.push('No. HP Warga Tujuan');
    if (!detail_keperluan?.trim()) kosong.push('Detail Keperluan');

    const jenisK = jenis_kendaraan?.trim();
    if (!jenisK) {
      kosong.push('Jenis Kendaraan');
    } else if (jenisK === 'Lainnya') {
      kosong.push('Kendaraan Lainnya');
    }

    const platOptional = jenisK && !['Motor', 'Mobil', 'Jalan Kaki'].includes(jenisK);
    if (!platOptional && !plat_nomor?.trim()) {
      kosong.push('Plat Nomor');
    }

    if (kosong.length > 0) {
      return res.status(400).json({
        success: false,
        message: `Kolom berikut wajib diisi: ${kosong.join(', ')}.`,
      });
    }

    const creatorId = (req.user.role === 'warga') ? req.user.id : (created_by || user_id || req.user.id);

    const result = await pool.query(
      `INSERT INTO visitors (nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan, created_by, rt_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
      [nama_tamu.trim(), no_hp_tamu.trim(), blok_tujuan.trim(), no_hp_tujuan.trim(), tipe_keperluan || 'Kunjungan', detail_keperluan.trim(), plat_nomor ? plat_nomor.trim() : null, jenisK || null, creatorId,
        rtUntukSimpan(req)]
    );
    const t = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Mencatat tamu masuk: ${ringkas(t.nama_tamu)} → ${t.blok_tujuan || '-'}, keperluan ${t.tipe_keperluan || '-'}${t.plat_nomor ? `, kendaraan ${t.plat_nomor}` : ''}`);

    // Siaran push notifikasi FCM kedatangan tamu secara non-blocking
    dispatcher.dispatchAsync(() => sendVisitorArrivalPushNotification(t), 'VisitorArrived');

    return res.status(201).json({ success: true, message: 'Tamu berhasil diregistrasi.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function checkoutVisitor(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'visitors', id)) return;
    const result = await pool.query(
      "UPDATE visitors SET status = 'Checkout', jam_keluar = NOW() WHERE id = $1 AND status = 'Di Dalam' RETURNING *", [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Tamu tidak ditemukan atau sudah checkout.' });
    await logActivity(req, TIPE.UPDATE, `Mencatat tamu keluar: ${ringkas(result.rows[0].nama_tamu)}`);

    return res.status(200).json({ success: true, message: 'Checkout berhasil.', data: result.rows[0] });
  } catch (err) {
    console.error('CheckoutVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteVisitor(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'visitors', id)) return;
    // RETURNING lengkap: catatan tamu adalah catatan keamanan lingkungan.
    // Menghapusnya berarti menghilangkan bukti siapa masuk dan kapan, jadi
    // seluruh isinya ikut disalin ke log sebelum barisnya lenyap.
    const result = await pool.query('DELETE FROM visitors WHERE id = $1 RETURNING *', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Data tamu tidak ditemukan.' });

    const d = result.rows[0];
    await logActivity(
      req,
      TIPE.DELETE,
      `Menghapus catatan tamu: ${ringkas(d.nama_tamu)} → ${d.blok_tujuan || '-'} ` +
        `(masuk ${d.jam_masuk ? new Date(d.jam_masuk).toLocaleString('id-ID') : '-'}, ` +
        `kendaraan ${d.plat_nomor || '-'})`
    );

    return res.status(200).json({ success: true, message: 'Data tamu berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getVisitors,
  getVisitorStats,
  createVisitor,
  checkoutVisitor,
  deleteVisitor,
  sendVisitorArrivalPushNotification,
};
