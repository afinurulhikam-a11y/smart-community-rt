const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const { pool } = require('../config/database');
const { logActivity } = require('../services/log.service');
const { jenisKelamin } = require('../utils/normalisasi');
const { klausaRt } = require('../utils/lingkup-rt');

function buildFamilyQuery(req) {
  const { search } = req.query;
  let query = `SELECT k.*,
      (SELECT COUNT(*)::int FROM anggota_keluarga ak WHERE ak.keluarga_id = k.id) AS jumlah_anggota,
      EXISTS (
        SELECT 1 FROM anggota_keluarga ak2
        WHERE ak2.keluarga_id = k.id AND ak2.status_keluarga = 'Kepala Keluarga'
      ) AS kepala_terkonfirmasi
    FROM keluarga k WHERE k.deleted_at IS NULL`;
  const params = [];

  // Menjaga daftar dan kedua export sekaligus, sama seperti klausa warga.
  query += klausaRt(req, 'k', params);

  if (req.user && req.user.role === 'warga') {
    params.push(req.user.id);
    query += ` AND k.no_kk = (SELECT no_kk FROM users WHERE id = $${params.length})`;
  }

  if (search) {
    params.push(`%${search}%`);
    query += ` AND (k.no_kk ILIKE $${params.length} OR k.kepala_keluarga ILIKE $${params.length} OR k.alamat ILIKE $${params.length})`;
  }
  return { query, params };
}

const KOLOM_KK = [
  { header: 'NO', key: 'no', width: 6 },
  { header: 'NO KK', key: 'no_kk', width: 22 },
  { header: 'KEPALA KELUARGA', key: 'kepala_keluarga', width: 26 },
  { header: 'ALAMAT & BLOK', key: 'alamat', width: 30 },
  { header: 'JUMLAH ANGGOTA', key: 'jumlah_anggota', width: 16 },
  { header: 'STATUS RUMAH', key: 'status_rumah', width: 18 },
  { header: 'LANGGANAN SAMPAH', key: 'langganan_sampah', width: 22 },
];

function toRowKK(kk, index) {
  return {
    no: index + 1,
    no_kk: kk.no_kk || '-',
    kepala_keluarga: kk.kepala_keluarga || '-',
    alamat: kk.alamat || '-',
    jumlah_anggota: kk.jumlah_anggota != null ? `${kk.jumlah_anggota} Orang` : '0 Orang',
    status_rumah: kk.status_rumah || '-',
    langganan_sampah: kk.langganan_sampah === true ? '✓ Berlangganan Sampah' : '✗ Tidak Berlangganan',
  };
}

async function getFamilies(req, res) {
  try {
    const { query, params } = buildFamilyQuery(req);
    const countQuery = `SELECT COUNT(*) FROM (${query}) AS total`;
    const countResult = await pool.query(countQuery, params);
    const totalData = parseInt(countResult.rows[0].count);

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 25;
    const offset = (page - 1) * limit;
    const totalPages = Math.ceil(totalData / limit);

    const finalQuery = `${query} ORDER BY k.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    const finalParams = [...params, limit, offset];

    const result = await pool.query(finalQuery, finalParams);
    return res.status(200).json({ 
      success: true, 
      count: result.rows.length, 
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        per_page: limit
      },
      data: result.rows 
    });
  } catch (err) {
    console.error('GetFamilies Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function exportFamiliesExcel(req, res) {
  try {
    const { query, params } = buildFamilyQuery(req);
    const finalQuery = `${query} ORDER BY k.created_at DESC`;
    const result = await pool.query(finalQuery, params);

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Data KK');
    worksheet.columns = KOLOM_KK;

    worksheet.getColumn('no').alignment = { horizontal: 'left' };

    result.rows.forEach((kk, index) => worksheet.addRow(toRowKK(kk, index)));

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=Data_KK.xlsx');

    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error('Export Families Excel Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export excel.' });
  }
}

async function exportFamiliesPdf(req, res) {
  try {
    const { query, params } = buildFamilyQuery(req);
    const finalQuery = `${query} ORDER BY k.created_at DESC`;
    const result = await pool.query(finalQuery, params);

    const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename=Data_KK.pdf');
    doc.pipe(res);

    doc.fontSize(18).text('Data Kartu Keluarga (KK) RT', { align: 'center' });
    doc.moveDown();

    const table = {
      title: 'Rekapitulasi Kartu Keluarga',
      headers: KOLOM_KK.map(k => k.header),
      rows: result.rows.map((kk, index) => {
        const row = toRowKK(kk, index);
        return KOLOM_KK.map(k => (row[k.key] === '' ? '-' : row[k.key].toString()));
      }),
    };

    await doc.table(table, {
      prepareHeader: () => doc.font('Helvetica-Bold').fontSize(8),
      prepareRow: () => doc.font('Helvetica').fontSize(7),
    });

    doc.end();
  } catch (err) {
    console.error('Export Families PDF Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export PDF.' });
    }
  }
}

async function getFamilyDetail(req, res) {
  try {
    const { id } = req.params;
    // Rute detail ikut disempitkan. Menyaring daftar tetapi membiarkan
    // `/:id` terbuka adalah kelalaian yang paling sering terjadi: id-nya
    // bisa ditebak atau didapat dari tempat lain, dan seluruh penyaringan
    // di daftar menjadi tidak ada artinya.
    const params = [id];
    let syaratWarga = '';
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      syaratWarga = ` AND no_kk = (SELECT no_kk FROM users WHERE id = $${params.length})`;
    }

    const familyResult = await pool.query(
      `SELECT * FROM keluarga WHERE id = $1 AND deleted_at IS NULL${syaratWarga}`,
      params
    );
    if (familyResult.rows.length === 0) return res.status(404).json({ success: false, message: 'Kartu Keluarga tidak ditemukan.' });
    const membersResult = await pool.query('SELECT * FROM anggota_keluarga WHERE keluarga_id = $1 ORDER BY id', [id]);
    return res.status(200).json({ success: true, data: { ...familyResult.rows[0], anggota: membersResult.rows } });
  } catch (err) {
    console.error('GetFamilyDetail Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createFamily(req, res) {
  try {
    const { no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, anggota } = req.body;
    if (!no_kk || !kepala_keluarga || !alamat || !rt || !rw) return res.status(400).json({ success: false, message: 'No KK, kepala keluarga, alamat, RT, dan RW wajib diisi.' });
    const existing = await pool.query('SELECT id FROM keluarga WHERE no_kk = $1 AND deleted_at IS NULL', [no_kk]);
    if (existing.rows.length > 0) return res.status(409).json({ success: false, message: 'Nomor KK sudah terdaftar.' });
    const existingNama = await pool.query(
      'SELECT id, no_kk, kepala_keluarga FROM keluarga WHERE LOWER(TRIM(kepala_keluarga)) = LOWER(TRIM($1)) AND deleted_at IS NULL',
      [kepala_keluarga]
    );
    if (existingNama.rows.length > 0) {
      return res.status(409).json({
        success: false,
        message: `Kartu Keluarga atas nama '${existingNama.rows[0].kepala_keluarga}' sudah terdaftar (No KK: ${existingNama.rows[0].no_kk}). Periksa kembali untuk mencegah duplikasi.`,
      });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const familyResult = await client.query(
        `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [no_kk, kepala_keluarga, alamat || null, rt || '001', rw || '001', kelurahan || null, kecamatan || null]
      );
      const family = familyResult.rows[0];
      if (anggota && Array.isArray(anggota)) {
        for (const a of anggota) {
          await client.query(
            `INSERT INTO anggota_keluarga (keluarga_id, nik, nama, jenis_kelamin, tempat_lahir, tanggal_lahir, agama, status_keluarga, pekerjaan, pendidikan) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
            // jenis_kelamin bertipe varchar(1): mengirim "Laki-laki" apa
            // adanya membuat seluruh permintaan gagal dengan 500 yang tidak
            // menjelaskan apa-apa. Dinormalisasi lebih dulu.
            [family.id, a.nik || null, a.nama, jenisKelamin(a.jenis_kelamin), a.tempat_lahir || null, a.tanggal_lahir || null, a.agama || null, a.status_keluarga || null, a.pekerjaan || null, a.pendidikan || null]
          );
        }
      }
      await client.query('COMMIT');
      await logActivity(req, 'CREATE', `Menambah kartu keluarga ${family.no_kk} atas nama ${family.kepala_keluarga}`);
      return res.status(201).json({ success: true, message: 'Kartu Keluarga berhasil ditambahkan.', data: family });
    } catch (txErr) { await client.query('ROLLBACK'); throw txErr; }
    finally { client.release(); }
  } catch (err) {
    console.error('CreateFamily Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateFamily(req, res) {
  try {
    const { id } = req.params;
    const { kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, status_rumah, langganan_sampah } = req.body;
    const result = await pool.query(
      `UPDATE keluarga SET 
         kepala_keluarga = COALESCE($1, kepala_keluarga), 
         alamat = COALESCE($2, alamat), 
         rt = COALESCE($3, rt), 
         rw = COALESCE($4, rw), 
         kelurahan = COALESCE($5, kelurahan), 
         kecamatan = COALESCE($6, kecamatan),
         status_rumah = COALESCE($7, status_rumah),
         langganan_sampah = COALESCE($8, langganan_sampah),
         updated_at = NOW() 
       WHERE id = $9 RETURNING *`,
      [
        kepala_keluarga !== undefined ? kepala_keluarga : null,
        alamat !== undefined ? alamat : null,
        rt !== undefined ? rt : null,
        rw !== undefined ? rw : null,
        kelurahan !== undefined ? kelurahan : null,
        kecamatan !== undefined ? kecamatan : null,
        status_rumah !== undefined ? status_rumah : null,
        typeof langganan_sampah === 'boolean' ? langganan_sampah : null,
        id,
      ]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Kartu Keluarga tidak ditemukan.' });
    const kk = result.rows[0];
    await logActivity(req, 'UPDATE', `Mengubah kartu keluarga ${kk.no_kk} atas nama ${kk.kepala_keluarga}`);
    return res.status(200).json({ success: true, message: 'Kartu Keluarga berhasil diperbarui.', data: kk });
  } catch (err) {
    console.error('UpdateFamily Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteFamily(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('UPDATE keluarga SET deleted_at = NOW() WHERE id = $1 RETURNING id, no_kk', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Kartu Keluarga tidak ditemukan.' });
    await logActivity(req, 'DELETE', `Menghapus kartu keluarga ${result.rows[0].no_kk}`);
    return res.status(200).json({ success: true, message: 'Kartu Keluarga berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteFamily Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getFamilies,
  getFamilyDetail,
  createFamily,
  updateFamily,
  deleteFamily,
  exportFamiliesExcel,
  exportFamiliesPdf,
};
