const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');
const { klausaRt, tolakLuarRt, rtUntukSimpan, bolehLintasRt } = require('../utils/lingkup-rt');

const STATUS_AKTIF_AGENDA = ['Akan Datang', 'Terjadwal', 'Berjalan', 'publish', 'aktif'];

/**
 * Mengirim notifikasi push FCM ke seluruh Warga & Pengurus aktif saat Agenda Baru dibuat dan berstatus aktif/publish.
 *
 * Menggunakan Durable Database Idempotency (agenda.fcm_dispatch_status).
 * Bersifat fail-safe & non-blocking: kegagalan FCM tidak membatalkan pembuatan agenda.
 */
async function sendNewAgendaPushNotification(agenda) {
  if (!agenda || !agenda.id) {
    return { skipped: true, reason: 'invalid_agenda' };
  }

  const rawStatus = String(agenda.status || 'Akan Datang').trim();
  const isActive = STATUS_AKTIF_AGENDA.some((s) => s.toLowerCase() === rawStatus.toLowerCase());

  if (!isActive) {
    console.log(`ℹ️ [FCM Agenda] Agenda #${agenda.id} berstatus '${rawStatus}' (bukan aktif/publish), push dilewati.`);
    return { skipped: true, reason: 'agenda_not_active' };
  }

  try {
    // 1. Klaim atomik status dispatch agenda baru (Race Condition & Durable Idempotency Guard)
    const claimResult = await pool.query(
      `UPDATE agenda
       SET fcm_dispatch_status = 'pending'
       WHERE id = $1
         AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
       RETURNING id, fcm_dispatch_status`,
      [agenda.id]
    );

    if (claimResult.rows.length === 0) {
      const check = await pool.query(`SELECT fcm_dispatch_status FROM agenda WHERE id = $1`, [agenda.id]);
      const curStatus = check.rows[0]?.fcm_dispatch_status || 'unknown';
      console.log(`ℹ️ [FCM Agenda] Agenda #${agenda.id} tidak dapat diklaim (status: '${curStatus}'), siaran duplikat dicegah.`);
      return { skipped: true, reason: curStatus === 'sent' ? 'already_sent' : 'already_processing' };
    }

    const cleanJudul = String(agenda.judul || 'Agenda Kegiatan RT').trim();
    const cleanDeskripsi = String(agenda.deskripsi || '').trim();
    const tglStr = agenda.tanggal ? String(agenda.tanggal).slice(0, 10) : '';
    const waktuStr = agenda.waktu_mulai ? String(agenda.waktu_mulai).slice(0, 5) : '';
    const lokasiStr = String(agenda.lokasi || '').trim();

    const infoJadwal = [
      tglStr ? `Tgl: ${tglStr}` : null,
      waktuStr ? `Pukul: ${waktuStr} WIB` : null,
      lokasiStr ? `Lokasi: ${lokasiStr}` : null,
    ].filter(Boolean).join(' | ');

    const title = `📅 Agenda Baru: ${cleanJudul}`;
    const body = infoJadwal
      ? `${infoJadwal}${cleanDeskripsi ? ` — ${cleanDeskripsi.length > 80 ? `${cleanDeskripsi.slice(0, 77)}...` : cleanDeskripsi}` : ''}`
      : (cleanDeskripsi || 'Agenda kegiatan baru telah ditambahkan ke jadwal RT.');

    const pushResult = await dispatcher.sendToAllActive({
      title,
      body,
      data: {
        entity_type: 'agenda',
        entity_id: String(agenda.id),
        action: 'NEW_AGENDA',
        judul: cleanJudul,
        tipe: String(agenda.tipe || 'Kegiatan'),
        tanggal: tglStr,
        waktu_mulai: waktuStr,
        lokasi: lokasiStr,
        status: rawStatus,
        created_at: agenda.created_at
          ? new Date(agenda.created_at).toISOString()
          : new Date().toISOString(),
      },
      priority: 'normal',
      collapseKey: 'agenda_broadcast',
    }, {
      // Dilingkupi ke RT baris yang memicunya, bukan ke RT pengirimnya:
      // yang menentukan siapa yang perlu tahu adalah data itu sendiri.
      // `?? null` berarti seluruh RW — jaring pengaman untuk baris lama
      // yang `rt_id`-nya belum terisi, karena berhenti mengirim diam-diam
      // lebih buruk daripada mengirim terlalu luas.
      rtId: agenda.rt_id ?? null,
    });

    if (pushResult.skipped && pushResult.reason === 'no_active_users') {
      console.log('ℹ️ [FCM Agenda] Tidak ada user aktif untuk menerima notifikasi agenda baru.');
      await pool.query(
        `UPDATE agenda SET fcm_dispatch_status = 'sent' WHERE id = $1`,
        [agenda.id]
      );
      return pushResult;
    }

    if (pushResult.success === false && !pushResult.simulated) {
      await pool.query(
        `UPDATE agenda SET fcm_dispatch_status = 'failed' WHERE id = $1`,
        [agenda.id]
      );
      console.error(`⚠️ [FCM Agenda] Gagal mengirim push agenda baru #${agenda.id}:`, pushResult.error);
      return pushResult;
    }

    await pool.query(
      `UPDATE agenda SET fcm_dispatch_status = 'sent' WHERE id = $1`,
      [agenda.id]
    );

    console.log(
      `🔔 [FCM Agenda] Notifikasi Agenda Baru #${agenda.id} [${cleanJudul}]:\n` +
      `   - Total Token : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil    : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal       : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode        : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(
      `UPDATE agenda SET fcm_dispatch_status = 'failed' WHERE id = $1`,
      [agenda.id]
    ).catch(() => {});
    console.error('⚠️ [FCM Agenda] Error dispatch agenda baru:', err.message);
    return { error: err.message };
  }
}

async function getAgenda(req, res) {
  try {
    const { status, tipe } = req.query;
    let query = `SELECT a.*, a.tanggal::text AS tanggal, u.nama AS created_by_nama,
                 COUNT(*) OVER() AS total_data 
                 FROM agenda a 
                 LEFT JOIN users u ON a.created_by = u.id 
                 WHERE a.deleted_at IS NULL`;
    const params = [];
    // Pelingkupan RT, sebelum penyaringan lain, supaya daftar dan
    // penghitungan totalnya memakai batas yang sama persis.
    query += klausaRt(req, 'a', params);
    if (status && status !== 'Semua') { params.push(status); query += ` AND a.status = $${params.length}`; }
    if (tipe) { params.push(tipe); query += ` AND a.tipe = $${params.length}`; }
    query += ' ORDER BY a.tanggal DESC, a.waktu_mulai DESC';

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
    console.error('GetAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createAgenda(req, res) {
  try {
    const { judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status } = req.body;
    if (!judul || !tanggal) return res.status(400).json({ success: false, message: 'Judul dan tanggal wajib diisi.' });

    const cleanMulai = (waktu_mulai && typeof waktu_mulai === 'string' && waktu_mulai.trim()) || null;
    const cleanSelesai = (waktu_selesai && typeof waktu_selesai === 'string' && waktu_selesai.trim()) || null;
    const cleanDeskripsi = (deskripsi && typeof deskripsi === 'string' && deskripsi.trim()) || null;
    const cleanLokasi = (lokasi && typeof lokasi === 'string' && lokasi.trim()) || null;
    const cleanTipe = (tipe && typeof tipe === 'string' && tipe.trim()) || 'Kegiatan';
    const cleanStatus = (status && typeof status === 'string' && status.trim()) || 'Akan Datang';

    // ===================================================================
    // Pengumuman se-RW: satu baris PER RT
    // ===================================================================
    //
    // Yang diterbitkan lewat layar sebagai "Pengumuman" adalah baris `agenda`
    // bertipe Pengumuman, bukan tabel `announcements` — dan inilah satu-satunya
    // modul yang boleh diisi Ketua RW.
    //
    // Tanpa `semua_rt`, `rtUntukSimpan()` jatuh ke RT akun pembuatnya ketika
    // lingkupnya "Semua RT", sehingga pengumuman se-RW sebenarnya hanya
    // mendarat di satu RT. Warga RT lain tidak pernah melihatnya, dan
    // pembuatnya melihat "berhasil".
    //
    // Diterbitkan sebagai satu baris per RT lewat `SELECT ... FROM rt`, bukan
    // satu baris ber-`rt_id` NULL: NULL akan menuntut SETIAP kueri daftar,
    // ekspor, reset, dan kartu berubah menjadi `(rt_id = $n OR rt_id IS NULL)`,
    // dan satu klausa yang terlewat menghilangkan pengumuman RW tanpa gejala.
    //
    // `$10::boolean` yang bernilai true membuat penyaringnya lolos untuk setiap
    // RT; yang false menyisakan satu RT saja. Satu kueri untuk dua perilaku,
    // jadi tidak ada dua jalur yang bisa menyimpang.
    const keSemuaRt = req.body?.semua_rt === true && bolehLintasRt(req);

    const result = await pool.query(
      `INSERT INTO agenda (judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, created_by, rt_id)
       SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, r.id
         FROM rt r
        WHERE r.deleted_at IS NULL
          AND ($10::boolean OR r.id = COALESCE(
                $11::uuid,
                -- Cadangan yang MENIRU pemicu v44 isi_rt_id: RT dengan kode
                -- terkecil. Wajib ada karena bentuk SELECT ... FROM rt ini
                -- tidak lagi memicu pengisian otomatis itu; rt_id yang kosong
                -- dulu diisi pemicu, sekarang ia tidak cocok dengan baris mana
                -- pun dan agendanya TIDAK TERSIMPAN SAMA SEKALI, dengan galat
                -- yang menunjuk ke result.rows[0] alih-alih ke sebabnya.
                -- Tertangkap test-agenda-crud, bukan dengan membaca kode.
                --
                -- CATATAN: jangan pakai backtick di komentar ini. Seluruh kueri
                -- berada di dalam template literal JavaScript, dan satu backtick
                -- menutupnya di tengah jalan.
                (SELECT id FROM rt WHERE deleted_at IS NULL ORDER BY kode LIMIT 1)
              ))
       RETURNING *, tanggal::text AS tanggal`,
      [judul.trim(), cleanDeskripsi, cleanTipe, tanggal, cleanMulai, cleanSelesai, cleanLokasi, cleanStatus,
        req.user.id, keSemuaRt, rtUntukSimpan(req)]
    );
    if (result.rows.length === 0) {
      // Hanya mungkin bila tabel `rt` benar-benar kosong. Dikatakan terus
      // terang: "Terjadi kesalahan server" pada layar yang baru saja diisi
      // orang tidak memberi satu pun petunjuk untuk memperbaikinya.
      return res.status(400).json({
        success: false,
        message: 'Belum ada RT yang terdaftar, jadi agenda tidak punya tempat untuk disimpan.',
      });
    }

    const a = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Membuat agenda "${ringkas(a.judul)}"" — ${a.tipe || '-'}, tanggal ${a.tanggal ? String(a.tanggal).slice(0, 10) : '-'}`);

    // Siaran push notifikasi FCM ke seluruh warga secara non-blocking jika agenda aktif/publish
    const isActive = STATUS_AKTIF_AGENDA.some((s) => s.toLowerCase() === (cleanStatus || '').toLowerCase());
    if (isActive) {
      dispatcher.dispatchAsync(() => sendNewAgendaPushNotification(a), 'AgendaNew');
    }

    return res.status(201).json({ success: true, message: 'Agenda berhasil dibuat.', data: a });
  } catch (err) {
    console.error('CreateAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateAgenda(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'agenda', id)) return;
    const { judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, notulen_url } = req.body;

    const cleanMulai = waktu_mulai !== undefined ? ((waktu_mulai && typeof waktu_mulai === 'string' && waktu_mulai.trim()) || null) : undefined;
    const cleanSelesai = waktu_selesai !== undefined ? ((waktu_selesai && typeof waktu_selesai === 'string' && waktu_selesai.trim()) || null) : undefined;
    const cleanDeskripsi = deskripsi !== undefined ? ((deskripsi && typeof deskripsi === 'string' && deskripsi.trim()) || null) : undefined;
    const cleanLokasi = lokasi !== undefined ? ((lokasi && typeof lokasi === 'string' && lokasi.trim()) || null) : undefined;

    const result = await pool.query(
      `UPDATE agenda SET 
         judul = COALESCE($1, judul), 
         deskripsi = CASE WHEN $2::boolean THEN $3 ELSE deskripsi END, 
         tipe = COALESCE($4, tipe), 
         tanggal = COALESCE($5, tanggal), 
         waktu_mulai = CASE WHEN $6::boolean THEN $7 ELSE waktu_mulai END, 
         waktu_selesai = CASE WHEN $8::boolean THEN $9 ELSE waktu_selesai END, 
         lokasi = CASE WHEN $10::boolean THEN $11 ELSE lokasi END, 
         status = COALESCE($12, status), 
         notulen_url = CASE WHEN $13::boolean THEN $14 ELSE notulen_url END, 
         updated_at = NOW() 
       WHERE id = $15 AND deleted_at IS NULL 
       RETURNING *, tanggal::text AS tanggal`,
      [
        judul ? judul.trim() : null,
        deskripsi !== undefined,
        cleanDeskripsi,
        tipe ? tipe.trim() : null,
        tanggal || null,
        waktu_mulai !== undefined,
        cleanMulai,
        waktu_selesai !== undefined,
        cleanSelesai,
        lokasi !== undefined,
        cleanLokasi,
        status || null,
        notulen_url !== undefined,
        notulen_url || null,
        id
      ]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Agenda tidak ditemukan.' });
    const a = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah agenda "${ringkas(a.judul)}" — status ${a.status}, tanggal ${a.tanggal ? String(a.tanggal).slice(0, 10) : '-'}`);

    return res.status(200).json({ success: true, message: 'Agenda berhasil diperbarui.', data: a });
  } catch (err) {
    console.error('UpdateAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteAgenda(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'agenda', id)) return;
    const result = await pool.query('UPDATE agenda SET deleted_at = NOW() WHERE id = $1 RETURNING id, judul', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Agenda tidak ditemukan.' });
    await logActivity(req, TIPE.DELETE, `Menghapus agenda "${ringkas(result.rows[0].judul)}"`);

    return res.status(200).json({ success: true, message: 'Agenda berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteAgenda Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getAgenda,
  createAgenda,
  updateAgenda,
  deleteAgenda,
  sendNewAgendaPushNotification,
  STATUS_AKTIF_AGENDA,
};
