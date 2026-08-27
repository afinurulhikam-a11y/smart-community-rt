const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const dispatcher = require('../services/notification.dispatcher');
const { klausaRt, tolakLuarRt, rtUntukSimpan, bolehLintasRt } = require('../utils/lingkup-rt');

/**
 * Mengirim notifikasi push FCM kepada seluruh warga/pengurus aktif saat pengumuman baru diterbitkan.
 *
 * Bersifat fail-safe dan non-blocking: kegagalan FCM atau ketiadaan token tidak
 * membatalkan pembuatan pengumuman di database.
 */
async function sendAnnouncementPushNotification(announcement) {
  try {
    if (!announcement || announcement.status !== 'publish') {
      console.log(`ℹ️ [FCM Announcement] Pengumuman #${announcement?.id} berstatus '${announcement?.status}', siaran FCM dilewati.`);
      return { skipped: true, reason: 'not_published' };
    }

    const title = `📢 Pengumuman: ${announcement.judul}`;
    const cleanIsi = String(announcement.isi || '').trim();
    const body = cleanIsi.length > 120 ? `${cleanIsi.slice(0, 117)}...` : cleanIsi;

    const pushResult = await dispatcher.sendToAllActive({
      title,
      body,
      data: {
        entity_type: 'announcement',
        entity_id: String(announcement.id),
        kategori: String(announcement.kategori || 'Umum'),
        created_at: announcement.created_at
          ? new Date(announcement.created_at).toISOString()
          : new Date().toISOString(),
      },
      priority: 'high',
      collapseKey: 'announcement_broadcast',
    }, {
      // Dilingkupi ke RT baris yang memicunya, bukan ke RT pengirimnya:
      // yang menentukan siapa yang perlu tahu adalah data itu sendiri.
      // `?? null` berarti seluruh RW — jaring pengaman untuk baris lama
      // yang `rt_id`-nya belum terisi, karena berhenti mengirim diam-diam
      // lebih buruk daripada mengirim terlalu luas.
      rtId: announcement.rt_id ?? null,
    });

    console.log(
      `🔔 [FCM Announcement] Hasil Siaran Pengumuman #${announcement.id}:\n` +
      `   - Total Token : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil    : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal       : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode        : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    console.error('⚠️ [FCM Announcement] Gagal mengirim push notification pengumuman:', err.message);
    return { error: err.message };
  }
}

async function getAnnouncements(req, res) {
  try {
    const { kategori, status, search } = req.query;
    let query = `SELECT a.*, u.nama AS created_by_nama FROM announcements a LEFT JOIN users u ON a.created_by = u.id WHERE 1=1`;
    const params = [];
    // Pelingkupan RT, dipasang sebelum penyaringan lain supaya daftar dan
    // penghitungan totalnya memakai batas yang sama persis.
    query += klausaRt(req, 'a', params);
    if (kategori && kategori !== 'Semua Kategori') { params.push(kategori); query += ` AND a.kategori = $${params.length}`; }
    if (status) { params.push(status); query += ` AND a.status = $${params.length}`; }
    if (search) { params.push(`%${search}%`); query += ` AND (a.judul ILIKE $${params.length} OR a.isi ILIKE $${params.length})`; }
    query += ' ORDER BY a.created_at DESC';
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetAnnouncements Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Menerbitkan pengumuman — untuk satu RT, atau untuk SELURUH RT sekaligus.
 *
 * ===================================================================
 * Cacat yang ditutup `semua_rt`
 * ===================================================================
 *
 * Pengumuman adalah SATU-SATUNYA modul yang boleh diisi Ketua RW, dan ia
 * rusak justru pada pemakaian yang paling wajar. Ketika lingkupnya "Semua
 * RT", `rtUntukSimpan()` jatuh ke `rt_id` akun pembuatnya — jadi pengumuman
 * se-RW sebenarnya hanya mendarat di RT tempat akun Ketua RW terdaftar.
 *
 * Terukur: dari dua RT, pengumumannya hanya muncul di RT 001. Warga RT 002
 * tidak pernah melihatnya, dan tidak ada satu pun pesan yang mengatakan
 * demikian. Pembuatnya melihat "berhasil".
 *
 * ===================================================================
 * Kenapa SATU BARIS PER RT, bukan satu baris ber-`rt_id` NULL
 * ===================================================================
 *
 * `rt_id` NULL akan berarti "milik semua RT", dan itu menuntut SETIAP kueri
 * daftar berubah dari `rt_id = $n` menjadi `(rt_id = $n OR rt_id IS NULL)` —
 * di pengendali, di ekspor, di reset, dan di penghitungan kartu. Satu klausa
 * yang terlewat menghilangkan pengumuman RW dari layar tanpa gejala.
 *
 * Lebih buruk lagi, NULL sudah punya arti lain di kolom itu: baris yang lahir
 * sebelum v43. Satu nilai untuk dua maksud adalah cara tercepat membuat kedua
 * maksud itu salah.
 *
 * Satu baris per RT membuat seluruh pelingkupan yang sudah ada tetap berlaku
 * apa adanya, dan pengurus tiap RT bisa menghapus salinan RT-nya sendiri
 * tanpa menyentuh RT lain.
 *
 * Seluruhnya dalam SATU transaksi: pengumuman yang terbit di separuh RT lebih
 * membingungkan daripada yang gagal seluruhnya.
 */
async function createAnnouncement(req, res) {
  const client = await pool.connect();
  try {
    const { judul, isi, kategori, status } = req.body;
    if (!judul || !isi) {
      return res.status(400).json({ success: false, message: 'Judul dan isi wajib diisi.' });
    }

    // Hanya peran lintas RT yang boleh menerbitkan ke seluruh RT. Untuk peran
    // lain nilainya diabaikan diam-diam, sama seperti `?rt=` — menolaknya
    // dengan galat hanya memberi tahu bahwa parameternya berarti sesuatu.
    const keSemuaRt = req.body.semua_rt === true && bolehLintasRt(req);

    let sasaran;
    if (keSemuaRt) {
      sasaran = (await client.query(
        'SELECT id, kode FROM rt WHERE deleted_at IS NULL ORDER BY kode'
      )).rows;
      if (sasaran.length === 0) {
        return res.status(400).json({
          success: false, message: 'Belum ada RT yang terdaftar.',
        });
      }
    } else {
      sasaran = [{ id: rtUntukSimpan(req), kode: null }];
    }

    await client.query('BEGIN');
    const dibuat = [];
    for (const rt of sasaran) {
      const r = await client.query(
        `INSERT INTO announcements (judul, isi, kategori, status, created_by, rt_id)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [judul, isi, kategori || 'Umum', status || 'publish', req.user.id, rt.id]
      );
      dibuat.push(r.rows[0]);
    }
    await client.query('COMMIT');

    const p = dibuat[0];
    await logActivity(
      req, TIPE.CREATE,
      `Membuat pengumuman "${ringkas(p.judul)}" — kategori ${p.kategori || '-'}, `
      + `status ${p.status}`
      + (keSemuaRt ? `, diterbitkan ke ${dibuat.length} RT sekaligus` : '')
    );

    // Siaran push notifikasi FCM secara non-blocking di latar.
    //
    // Satu siaran PER BARIS, bukan satu untuk semuanya: penerimanya dilingkupi
    // lewat `rt_id` baris itu, jadi menyiarkan sekali hanya akan memberi tahu
    // warga satu RT tentang pengumuman yang sebenarnya milik semua.
    for (const baris of dibuat) {
      dispatcher.dispatchAsync(() => sendAnnouncementPushNotification(baris), 'Announcement');
    }

    return res.status(201).json({
      success: true,
      message: keSemuaRt
        ? `Pengumuman berhasil diterbitkan ke ${dibuat.length} RT.`
        : 'Pengumuman berhasil dibuat.',
      data: p,
      jumlah_rt: dibuat.length,
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('CreateAnnouncement Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

async function updateAnnouncement(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'announcements', id)) return;
    const { judul, isi, kategori, status } = req.body;
    const result = await pool.query(
      `UPDATE announcements SET judul = COALESCE($1, judul), isi = COALESCE($2, isi), kategori = COALESCE($3, kategori), status = COALESCE($4, status), updated_at = NOW() WHERE id = $5 RETURNING *`,
      [judul, isi, kategori, status, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengumuman tidak ditemukan.' });
    const p = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah pengumuman "${ringkas(p.judul)}" — status ${p.status}, isi kini: "${ringkas(p.isi, 100)}"`);

    return res.status(200).json({ success: true, message: 'Pengumuman berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateAnnouncement Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteAnnouncement(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'announcements', id)) return;
    const result = await pool.query('DELETE FROM announcements WHERE id = $1 RETURNING id, judul', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Pengumuman tidak ditemukan.' });
    await logActivity(req, TIPE.DELETE, `Menghapus pengumuman "${ringkas(result.rows[0].judul)}"`);

    return res.status(200).json({ success: true, message: 'Pengumuman berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteAnnouncement Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getAnnouncements,
  createAnnouncement,
  updateAnnouncement,
  deleteAnnouncement,
  sendAnnouncementPushNotification,
};
