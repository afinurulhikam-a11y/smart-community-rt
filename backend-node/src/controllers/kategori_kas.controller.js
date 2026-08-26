const { pool } = require('../config/database');
const { logActivity, bandingkan, TIPE } = require('../services/log.service');
const { klausaRt, kondisiRt, rtUntukSimpan, tolakLuarRt } = require('../utils/lingkup-rt');

// Sesuai CHECK constraint yang sudah ada di tabel kategori_kas.
const TIPE_VALID = ['IN', 'OUT'];

async function getKategoriKas(req, res) {
  try {
    const hanyaAktif = req.query.aktif === 'true';
    const { tipe } = req.query;

    const kondisi = [];
    const params = [];
    if (hanyaAktif) kondisi.push('kk.is_aktif = true');
    if (tipe && TIPE_VALID.includes(tipe)) {
      params.push(tipe);
      kondisi.push(`kk.tipe = $${params.length}`);
    }
    // Sejak v45 tiap RT punya salinan kategorinya sendiri. Tanpa baris ini,
    // dropdown Kas RT memuat kategori seluruh RW — dan memilih kategori milik
    // RT lain menyimpan transaksi yang tidak pernah utuh di laporan mana pun.
    const rt = kondisiRt(req, 'kk', params);
    if (rt) kondisi.push(rt);
    const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';

    const result = await pool.query(`
      SELECT kk.id, kk.nama_kategori, kk.tipe, kk.is_aktif, kk.keterangan,
             COUNT(f.id)::int AS jumlah_transaksi
      FROM kategori_kas kk
      LEFT JOIN finances f ON f.kategori_id = kk.id
      ${where}
      GROUP BY kk.id
      ORDER BY kk.is_aktif DESC, kk.tipe ASC, kk.nama_kategori ASC
    `, params);

    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetKategoriKas Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createKategoriKas(req, res) {
  try {
    const { nama_kategori, tipe, keterangan } = req.body;

    if (!nama_kategori || !nama_kategori.trim()) {
      return res.status(400).json({ success: false, message: 'Nama kategori wajib diisi.' });
    }
    if (!TIPE_VALID.includes(tipe)) {
      return res.status(400).json({ success: false, message: "Tipe harus 'IN' (pemasukan) atau 'OUT' (pengeluaran)." });
    }

    // Nama kembar diperiksa DALAM RT ini saja. Memeriksanya se-basis-data
    // adalah keadaan sebelum v45, dan itu berarti satu RT yang sudah memakai
    // sebuah nama mengunci nama itu untuk seluruh RW.
    const pKembar = [nama_kategori];
    const kembar = await pool.query(
      `SELECT id FROM kategori_kas
        WHERE LOWER(TRIM(nama_kategori)) = LOWER(TRIM($1))
        ${klausaRt(req, '', pKembar)}`,
      pKembar
    );
    if (kembar.rows.length > 0) {
      return res.status(409).json({ success: false, message: 'Kategori dengan nama tersebut sudah ada.' });
    }

    const result = await pool.query(
      `INSERT INTO kategori_kas (nama_kategori, tipe, keterangan, is_aktif, rt_id)
       VALUES ($1, $2, $3, true, $4) RETURNING *`,
      [nama_kategori.trim(), tipe, keterangan || null, rtUntukSimpan(req)]
    );
    const baru = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Menambah kategori kas "${baru.nama_kategori}" (tipe ${baru.tipe})`);

    return res.status(201).json({ success: true, message: 'Kategori kas berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateKategoriKas Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateKategoriKas(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'kategori_kas', id)) return;
    const { nama_kategori, tipe, keterangan, is_aktif } = req.body;

    if (tipe !== undefined && !TIPE_VALID.includes(tipe)) {
      return res.status(400).json({ success: false, message: "Tipe harus 'IN' (pemasukan) atau 'OUT' (pengeluaran)." });
    }

    // Mengubah tipe kategori yang sudah dipakai akan membuat transaksi lama
    // bertentangan dengan tipenya sendiri (pemasukan berkategori pengeluaran).
    if (tipe !== undefined) {
      const dipakai = await pool.query('SELECT COUNT(*)::int AS c FROM finances WHERE kategori_id = $1', [id]);
      const lama = await pool.query('SELECT tipe FROM kategori_kas WHERE id = $1', [id]);
      if (dipakai.rows[0].c > 0 && lama.rows[0] && lama.rows[0].tipe !== tipe) {
        return res.status(409).json({
          success: false,
          message: `Tipe kategori tidak bisa diubah karena sudah dipakai ${dipakai.rows[0].c} transaksi. Buat kategori baru bila perlu.`,
        });
      }
    }

    if (nama_kategori) {
      const kembar = await pool.query(
        `SELECT id FROM kategori_kas
          WHERE LOWER(TRIM(nama_kategori)) = LOWER(TRIM($1)) AND id <> $2
            AND rt_id IS NOT DISTINCT FROM (SELECT rt_id FROM kategori_kas WHERE id = $2)`,
        [nama_kategori, id]
      );
      if (kembar.rows.length > 0) {
        return res.status(409).json({ success: false, message: 'Kategori dengan nama tersebut sudah ada.' });
      }
    }

    // Dibaca lebih dulu supaya log memuat nilai sebelum dan sesudahnya.
    const cekLama = await pool.query('SELECT * FROM kategori_kas WHERE id = $1', [id]);
    const sebelum = cekLama.rows[0] || {};

    const result = await pool.query(
      `UPDATE kategori_kas SET
         nama_kategori = COALESCE($1, nama_kategori),
         tipe          = COALESCE($2, tipe),
         keterangan    = COALESCE($3, keterangan),
         is_aktif      = COALESCE($4, is_aktif)
       WHERE id = $5 RETURNING *`,
      [nama_kategori?.trim() || null, tipe || null, keterangan ?? null, is_aktif ?? null, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Kategori kas tidak ditemukan.' });
    }
    const rincian = bandingkan(sebelum, result.rows[0], {
      nama_kategori: 'nama',
      tipe: 'tipe',
      is_aktif: 'aktif',
      keterangan: 'keterangan',
    });
    if (rincian) {
      await logActivity(req, TIPE.UPDATE, `Mengubah kategori kas "${sebelum.nama_kategori ?? result.rows[0].nama_kategori}" — ${rincian}`);
    }

    return res.status(200).json({ success: true, message: 'Kategori kas berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateKategoriKas Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteKategoriKas(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'kategori_kas', id)) return;

    // Menghapus kategori yang sudah dipakai akan membuat transaksi kehilangan
    // rujukannya. Tawarkan menonaktifkan sebagai gantinya.
    const dipakai = await pool.query('SELECT COUNT(*)::int AS c FROM finances WHERE kategori_id = $1', [id]);
    if (dipakai.rows[0].c > 0) {
      return res.status(409).json({
        success: false,
        message: `Kategori ini sudah dipakai ${dipakai.rows[0].c} transaksi sehingga tidak bisa dihapus. Nonaktifkan saja agar tidak muncul lagi saat mencatat transaksi baru.`,
      });
    }

    const result = await pool.query('DELETE FROM kategori_kas WHERE id = $1 RETURNING *', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Kategori kas tidak ditemukan.' });
    }
    const dihapus = result.rows[0];
    await logActivity(req, TIPE.DELETE, `Menghapus kategori kas "${dihapus.nama_kategori}" (tipe ${dihapus.tipe})`);

    return res.status(200).json({ success: true, message: 'Kategori kas berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteKategoriKas Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getKategoriKas, createKategoriKas, updateKategoriKas, deleteKategoriKas };
