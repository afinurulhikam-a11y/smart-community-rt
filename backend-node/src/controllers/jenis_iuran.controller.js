const { pool } = require('../config/database');

const PERIODE_VALID = ['bulanan', 'tahunan', 'sekali'];

async function getJenisIuran(req, res) {
  try {
    // Dropdown di layar hanya butuh yang aktif; halaman kelola butuh semuanya.
    const hanyaAktif = req.query.aktif === 'true';
    const result = await pool.query(`
      SELECT ji.id, ji.nama_iuran, ji.nominal_default::numeric AS nominal_default,
             ji.periode, ji.is_aktif, ji.keterangan,
             COUNT(b.id)::int AS jumlah_tagihan
      FROM jenis_iuran ji
      LEFT JOIN bills b ON b.jenis_iuran_id = ji.id
      ${hanyaAktif ? 'WHERE ji.is_aktif = true' : ''}
      GROUP BY ji.id
      ORDER BY ji.is_aktif DESC, ji.nama_iuran ASC
    `);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetJenisIuran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createJenisIuran(req, res) {
  try {
    const { nama_iuran, nominal_default, periode, keterangan } = req.body;
    if (!nama_iuran || !nama_iuran.trim()) {
      return res.status(400).json({ success: false, message: 'Nama iuran wajib diisi.' });
    }
    if (periode && !PERIODE_VALID.includes(periode)) {
      return res.status(400).json({ success: false, message: `Periode harus salah satu dari: ${PERIODE_VALID.join(', ')}` });
    }

    const kembar = await pool.query('SELECT id FROM jenis_iuran WHERE LOWER(TRIM(nama_iuran)) = LOWER(TRIM($1))', [nama_iuran]);
    if (kembar.rows.length > 0) {
      return res.status(409).json({ success: false, message: 'Jenis iuran dengan nama tersebut sudah ada.' });
    }

    const result = await pool.query(
      `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, keterangan, is_aktif)
       VALUES ($1, $2, $3, $4, true) RETURNING *`,
      [nama_iuran.trim(), nominal_default || 0, periode || 'bulanan', keterangan || null]
    );
    return res.status(201).json({ success: true, message: 'Jenis iuran berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateJenisIuran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateJenisIuran(req, res) {
  try {
    const { id } = req.params;
    const { nama_iuran, nominal_default, periode, keterangan, is_aktif } = req.body;

    if (periode && !PERIODE_VALID.includes(periode)) {
      return res.status(400).json({ success: false, message: `Periode harus salah satu dari: ${PERIODE_VALID.join(', ')}` });
    }

    if (nama_iuran) {
      const kembar = await pool.query(
        'SELECT id FROM jenis_iuran WHERE LOWER(TRIM(nama_iuran)) = LOWER(TRIM($1)) AND id <> $2',
        [nama_iuran, id]
      );
      if (kembar.rows.length > 0) {
        return res.status(409).json({ success: false, message: 'Jenis iuran dengan nama tersebut sudah ada.' });
      }
    }

    // COALESCE agar field yang tidak dikirim tidak ikut terhapus.
    const result = await pool.query(
      `UPDATE jenis_iuran SET
         nama_iuran      = COALESCE($1, nama_iuran),
         nominal_default = COALESCE($2, nominal_default),
         periode         = COALESCE($3, periode),
         keterangan      = COALESCE($4, keterangan),
         is_aktif        = COALESCE($5, is_aktif)
       WHERE id = $6 RETURNING *`,
      [nama_iuran?.trim() || null, nominal_default ?? null, periode || null, keterangan ?? null, is_aktif ?? null, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jenis iuran tidak ditemukan.' });
    }
    return res.status(200).json({ success: true, message: 'Jenis iuran berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateJenisIuran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteJenisIuran(req, res) {
  try {
    const { id } = req.params;

    // Menghapus jenis yang sudah dipakai akan membuat tagihan kehilangan
    // identitasnya. Tawarkan menonaktifkan sebagai gantinya.
    const dipakai = await pool.query('SELECT COUNT(*)::int AS c FROM bills WHERE jenis_iuran_id = $1', [id]);
    if (dipakai.rows[0].c > 0) {
      return res.status(409).json({
        success: false,
        message: `Jenis iuran ini sudah dipakai ${dipakai.rows[0].c} tagihan sehingga tidak bisa dihapus. Nonaktifkan saja agar tidak muncul lagi saat membuat tagihan baru.`,
      });
    }

    const result = await pool.query('DELETE FROM jenis_iuran WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jenis iuran tidak ditemukan.' });
    }
    return res.status(200).json({ success: true, message: 'Jenis iuran berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteJenisIuran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getJenisIuran, createJenisIuran, updateJenisIuran, deleteJenisIuran };
