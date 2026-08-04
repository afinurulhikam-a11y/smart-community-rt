const { pool } = require('../config/database');

// Sesuai CHECK constraint pada tabel kategori_bop.
const TIPE_VALID = ['IN', 'OUT'];

async function getKategoriBop(req, res) {
  try {
    const hanyaAktif = req.query.aktif === 'true';
    const { tipe } = req.query;

    const kondisi = [];
    const params = [];
    if (hanyaAktif) kondisi.push('kb.is_aktif = true');
    if (tipe && TIPE_VALID.includes(tipe)) {
      params.push(tipe);
      kondisi.push(`kb.tipe = $${params.length}`);
    }
    const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';

    const result = await pool.query(`
      SELECT kb.id, kb.nama_kategori, kb.tipe, kb.is_aktif, kb.keterangan,
             COUNT(b.id)::int AS jumlah_transaksi
      FROM kategori_bop kb
      LEFT JOIN bop_finances b ON b.kategori_id = kb.id
      ${where}
      GROUP BY kb.id
      ORDER BY kb.is_aktif DESC, kb.tipe ASC, kb.nama_kategori ASC
    `, params);

    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetKategoriBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createKategoriBop(req, res) {
  try {
    const { nama_kategori, tipe, keterangan } = req.body;

    if (!nama_kategori || !nama_kategori.trim()) {
      return res.status(400).json({ success: false, message: 'Nama kategori wajib diisi.' });
    }
    if (!TIPE_VALID.includes(tipe)) {
      return res.status(400).json({ success: false, message: "Tipe harus 'IN' (pemasukan) atau 'OUT' (pengeluaran)." });
    }

    const kembar = await pool.query(
      'SELECT id FROM kategori_bop WHERE LOWER(TRIM(nama_kategori)) = LOWER(TRIM($1))',
      [nama_kategori]
    );
    if (kembar.rows.length > 0) {
      return res.status(409).json({ success: false, message: 'Kategori BOP dengan nama tersebut sudah ada.' });
    }

    const result = await pool.query(
      `INSERT INTO kategori_bop (nama_kategori, tipe, keterangan, is_aktif)
       VALUES ($1, $2, $3, true) RETURNING *`,
      [nama_kategori.trim(), tipe, keterangan || null]
    );
    return res.status(201).json({ success: true, message: 'Kategori BOP berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateKategoriBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateKategoriBop(req, res) {
  try {
    const { id } = req.params;
    const { nama_kategori, tipe, keterangan, is_aktif } = req.body;

    if (tipe !== undefined && !TIPE_VALID.includes(tipe)) {
      return res.status(400).json({ success: false, message: "Tipe harus 'IN' (pemasukan) atau 'OUT' (pengeluaran)." });
    }

    // Mengubah tipe kategori yang sudah dipakai akan membuat transaksi lama
    // bertentangan dengan tipenya sendiri.
    if (tipe !== undefined) {
      const dipakai = await pool.query('SELECT COUNT(*)::int AS c FROM bop_finances WHERE kategori_id = $1', [id]);
      const lama = await pool.query('SELECT tipe FROM kategori_bop WHERE id = $1', [id]);
      if (dipakai.rows[0].c > 0 && lama.rows[0] && lama.rows[0].tipe !== tipe) {
        return res.status(409).json({
          success: false,
          message: `Tipe kategori tidak bisa diubah karena sudah dipakai ${dipakai.rows[0].c} transaksi. Buat kategori baru bila perlu.`,
        });
      }
    }

    if (nama_kategori) {
      const kembar = await pool.query(
        'SELECT id FROM kategori_bop WHERE LOWER(TRIM(nama_kategori)) = LOWER(TRIM($1)) AND id <> $2',
        [nama_kategori, id]
      );
      if (kembar.rows.length > 0) {
        return res.status(409).json({ success: false, message: 'Kategori BOP dengan nama tersebut sudah ada.' });
      }
    }

    const result = await pool.query(
      `UPDATE kategori_bop SET
         nama_kategori = COALESCE($1, nama_kategori),
         tipe          = COALESCE($2, tipe),
         keterangan    = COALESCE($3, keterangan),
         is_aktif      = COALESCE($4, is_aktif)
       WHERE id = $5 RETURNING *`,
      [nama_kategori?.trim() || null, tipe || null, keterangan ?? null, is_aktif ?? null, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Kategori BOP tidak ditemukan.' });
    }
    return res.status(200).json({ success: true, message: 'Kategori BOP berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateKategoriBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteKategoriBop(req, res) {
  try {
    const { id } = req.params;

    const dipakai = await pool.query('SELECT COUNT(*)::int AS c FROM bop_finances WHERE kategori_id = $1', [id]);
    if (dipakai.rows[0].c > 0) {
      return res.status(409).json({
        success: false,
        message: `Kategori ini sudah dipakai ${dipakai.rows[0].c} transaksi sehingga tidak bisa dihapus. Nonaktifkan saja agar tidak muncul lagi saat mencatat transaksi baru.`,
      });
    }

    const result = await pool.query('DELETE FROM kategori_bop WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Kategori BOP tidak ditemukan.' });
    }
    return res.status(200).json({ success: true, message: 'Kategori BOP berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteKategoriBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getKategoriBop, createKategoriBop, updateKategoriBop, deleteKategoriBop };
