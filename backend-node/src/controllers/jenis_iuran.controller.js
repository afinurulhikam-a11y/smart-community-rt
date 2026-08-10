const { pool } = require('../config/database');
const { logActivity, rupiah, bandingkan, TIPE } = require('../services/log.service');
const { TIPE_TETAP, TIPE_METERAN } = require('../utils/tagihan-air');

const PERIODE_VALID = ['bulanan', 'tahunan', 'sekali'];

async function getJenisIuran(req, res) {
  try {
    // Dropdown di layar hanya butuh yang aktif; halaman kelola butuh semuanya.
    const hanyaAktif = req.query.aktif === 'true';
    const result = await pool.query(`
      SELECT ji.id, ji.nama_iuran, ji.nominal_default::numeric AS nominal_default,
             ji.periode, ji.is_aktif, ji.keterangan,
             -- Aturan tarif ikut dikirim: layar master perlu menampilkannya,
             -- dan klien perlu tahu jenis ini bermeteran atau bernominal tetap
             -- untuk memutuskan formulir mana yang ditampilkan.
             ji.tipe_hitung, ji.tarif_per_m3, ji.abondement, ji.biaya_sampah,
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
    const {
      nama_iuran, nominal_default, periode, keterangan,
      tipe_hitung, tarif_per_m3, abondement, biaya_sampah,
    } = req.body;
    if (!nama_iuran || !nama_iuran.trim()) {
      return res.status(400).json({ success: false, message: 'Nama iuran wajib diisi.' });
    }
    if (periode && !PERIODE_VALID.includes(periode)) {
      return res.status(400).json({ success: false, message: `Periode harus salah satu dari: ${PERIODE_VALID.join(', ')}` });
    }

    const tipeHitung = tipe_hitung || TIPE_TETAP;
    if (![TIPE_TETAP, TIPE_METERAN].includes(tipeHitung)) {
      return res.status(400).json({
        success: false,
        message: `Tipe hitung harus salah satu dari: ${TIPE_TETAP}, ${TIPE_METERAN}`,
      });
    }
    // Tanpa tarif, jenis bermeteran tidak bisa menghitung apa pun — tagihannya
    // akan terbit sebesar biaya tetap saja dan diam-diam tidak menagih airnya.
    if (tipeHitung === TIPE_METERAN && !(Number(tarif_per_m3) > 0)) {
      return res.status(400).json({
        success: false,
        message: 'Tarif per m³ wajib diisi dan harus lebih dari 0 untuk iuran berbasis meteran.',
      });
    }

    const kembar = await pool.query('SELECT id FROM jenis_iuran WHERE LOWER(TRIM(nama_iuran)) = LOWER(TRIM($1))', [nama_iuran]);
    if (kembar.rows.length > 0) {
      return res.status(409).json({ success: false, message: 'Jenis iuran dengan nama tersebut sudah ada.' });
    }

    const result = await pool.query(
      `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, keterangan, is_aktif,
                                tipe_hitung, tarif_per_m3, abondement, biaya_sampah)
       VALUES ($1, $2, $3, $4, true, $5, $6, $7, $8) RETURNING *`,
      [
        nama_iuran.trim(), nominal_default || 0, periode || 'bulanan', keterangan || null,
        tipeHitung, tipeHitung === TIPE_METERAN ? (tarif_per_m3 || 0) : null,
        abondement || 0, biaya_sampah || 0,
      ]
    );
    const baru = result.rows[0];
    await logActivity(
      req,
      TIPE.CREATE,
      `Menambah jenis iuran "${baru.nama_iuran}" — nominal ${rupiah(baru.nominal_default)}, periode ${baru.periode}`
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
    const {
      nama_iuran, nominal_default, periode, keterangan, is_aktif,
      tipe_hitung, tarif_per_m3, abondement, biaya_sampah,
    } = req.body;

    if (tipe_hitung && ![TIPE_TETAP, TIPE_METERAN].includes(tipe_hitung)) {
      return res.status(400).json({
        success: false,
        message: `Tipe hitung harus salah satu dari: ${TIPE_TETAP}, ${TIPE_METERAN}`,
      });
    }

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

    // Keadaan lama dibaca lebih dulu. Nominal iuran adalah angka yang
    // menentukan berapa uang yang ditagihkan ke setiap kartu keluarga —
    // menurunkannya diam-diam adalah penyalahgunaan yang tidak akan terlihat
    // dari mana pun kecuali dari baris log yang memuat nilai sebelumnya.
    const cekLama = await pool.query('SELECT * FROM jenis_iuran WHERE id = $1', [id]);
    const sebelum = cekLama.rows[0] || {};

    // COALESCE agar field yang tidak dikirim tidak ikut terhapus.
    const result = await pool.query(
      `UPDATE jenis_iuran SET
         nama_iuran      = COALESCE($1, nama_iuran),
         nominal_default = COALESCE($2, nominal_default),
         periode         = COALESCE($3, periode),
         keterangan      = COALESCE($4, keterangan),
         is_aktif        = COALESCE($5, is_aktif),
         tipe_hitung     = COALESCE($7, tipe_hitung),
         tarif_per_m3    = COALESCE($8, tarif_per_m3),
         abondement      = COALESCE($9, abondement),
         biaya_sampah    = COALESCE($10, biaya_sampah)
       WHERE id = $6 RETURNING *`,
      [
        nama_iuran?.trim() || null, nominal_default ?? null, periode || null,
        keterangan ?? null, is_aktif ?? null, id,
        tipe_hitung || null, tarif_per_m3 ?? null, abondement ?? null, biaya_sampah ?? null,
      ]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jenis iuran tidak ditemukan.' });
    }

    const rincian = bandingkan(sebelum, result.rows[0], {
      nama_iuran: 'nama',
      nominal_default: 'nominal',
      periode: 'periode',
      is_aktif: 'aktif',
      keterangan: 'keterangan',
    });
    if (rincian) {
      await logActivity(
        req,
        TIPE.UPDATE,
        `Mengubah jenis iuran "${sebelum.nama_iuran ?? result.rows[0].nama_iuran}" — ${rincian}`
      );
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

    // RETURNING lengkap, bukan cuma id: setelah barisnya hilang, namanya tidak
    // bisa dicari lagi di mana pun — log yang hanya memuat UUID tidak berguna.
    const result = await pool.query('DELETE FROM jenis_iuran WHERE id = $1 RETURNING *', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Jenis iuran tidak ditemukan.' });
    }

    const dihapus = result.rows[0];
    await logActivity(
      req,
      TIPE.DELETE,
      `Menghapus jenis iuran "${dihapus.nama_iuran}" (nominal ${rupiah(dihapus.nominal_default)}, periode ${dihapus.periode})`
    );

    return res.status(200).json({ success: true, message: 'Jenis iuran berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteJenisIuran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getJenisIuran, createJenisIuran, updateJenisIuran, deleteJenisIuran };
