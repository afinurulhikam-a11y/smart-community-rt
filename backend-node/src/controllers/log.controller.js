const { pool } = require('../config/database');

/**
 * Membaca jejak audit.
 *
 * Menyelidiki sebuah kejadian selalu berbentuk pertanyaan berwaktu — "apa saja
 * yang terjadi antara 1 sampai 5 Agustus" — jadi `dari` dan `sampai` adalah
 * penyaring yang paling sering dibutuhkan, dan sebelumnya tidak ada sama sekali.
 *
 * `total` dikembalikan terpisah dari `data` supaya layar bisa menampilkan
 * penomoran halaman yang jujur: tanpa itu, "25 baris" tidak bisa dibedakan
 * antara "memang hanya segitu" dan "masih ada 4.000 lagi di belakangnya".
 */
async function getActivityLogs(req, res) {
  try {
    const { limit = 50, offset = 0, search, tipe, user_id, dari, sampai } = req.query;

    const kondisi = [];
    const params = [];
    const p = () => `$${params.length}`;

    if (tipe && tipe !== 'Semua') {
      params.push(tipe);
      kondisi.push(`tipe = ${p()}`);
    }

    if (user_id) {
      params.push(user_id);
      kondisi.push(`user_id = ${p()}`);
    }

    if (dari) {
      params.push(dari);
      kondisi.push(`created_at >= ${p()}::date`);
    }

    if (sampai) {
      // `< tanggal + 1 hari`, bukan `<= tanggal`: kolomnya bertipe timestamp,
      // sehingga `<= '2026-08-05'` diam-diam berarti `<= 2026-08-05 00:00` dan
      // membuang seluruh kejadian pada hari itu juga.
      params.push(sampai);
      kondisi.push(`created_at < (${p()}::date + INTERVAL '1 day')`);
    }

    if (search) {
      params.push(`%${search}%`);
      kondisi.push(
        `(aktivitas ILIKE ${p()} OR user_nama ILIKE ${p()} OR ip_address ILIKE ${p()})`
      );
    }

    const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';

    const hitung = await pool.query(`SELECT COUNT(*)::int AS total FROM activity_logs ${where}`, params);

    const batas = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 500);
    const lompat = Math.max(parseInt(offset, 10) || 0, 0);
    params.push(batas, lompat);

    const result = await pool.query(
      `SELECT id, user_id, user_nama, user_role, tipe, aktivitas, ip_address, created_at
         FROM activity_logs ${where}
        ORDER BY created_at DESC
        LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return res.status(200).json({
      success: true,
      count: result.rows.length,
      total: hitung.rows[0].total,
      data: result.rows,
    });
  } catch (err) {
    console.error('GetActivityLogs Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Jejak audit TIDAK BISA dihapus — endpoint ini sengaja dihilangkan.
 *
 * Sebelumnya ada `DELETE /api/activity-logs` yang menjalankan
 * `DELETE FROM activity_logs` lalu mencatat satu baris "Membersihkan seluruh
 * log". Artinya seorang administrator bisa melenyapkan seluruh bukti
 * perbuatannya sendiri dan hanya meninggalkan satu baris yang tidak
 * menyebutkan apa pun tentang isi yang dihapus.
 *
 * Itu membuat log aktivitas tidak ada gunanya persis pada satu keadaan yang
 * paling membutuhkannya: ketika yang menyalahgunakan adalah pemegang akses
 * tertinggi.
 *
 * Sekarang ditutup berlapis:
 *   1. Endpoint & fungsinya dihapus (berkas ini)
 *   2. `activity_logs` dikeluarkan dari kelompok reset dan Reset Total,
 *      dan dimasukkan ke TABEL_DILINDUNGI (`src/config/reset-groups.js`)
 *   3. Trigger `trg_activity_logs_append_only` menolak UPDATE dan DELETE di
 *      tingkat database (`migration_v19_log_append_only.js`)
 *
 * Lapisan ketiga yang membuat dua lapisan pertama tidak bisa dilangkahi diam-
 * diam bila kelak ada yang menambahkan jalur hapus baru.
 */

module.exports = { getActivityLogs };
