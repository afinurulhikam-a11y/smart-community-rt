const { pool } = require('../config/database');
const { logActivity, rupiah, bandingkan, TIPE } = require('../services/log.service');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');

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
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 10;
    const offset = (page - 1) * limit;

    let where = 'WHERE 1=1';
    const params = [];

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
    const milikWarga = req.user.role === 'warga';
    const p = milikWarga ? [req.user.id] : [];
    const filter = milikWarga ? ' AND user_id = $1' : '';

    const totalResult = await pool.query(`SELECT COUNT(*) as count FROM bantuan_sosial WHERE 1=1${filter}`, p);
    const aktifResult = await pool.query(`SELECT COUNT(*) as count FROM bantuan_sosial WHERE status = 'Aktif'${filter}`, p);
    const reviewResult = await pool.query(`SELECT COUNT(*) as count FROM bantuan_sosial WHERE status = 'Selesai'${filter}`, p);
    const jenisResult = await pool.query(`SELECT COUNT(DISTINCT jenis_bantuan) as count FROM bantuan_sosial WHERE status = 'Aktif'${filter}`, p);
    return res.status(200).json({
      success: true,
      data: {
        total_penerima: parseInt(totalResult.rows[0].count),
        aktif: parseInt(aktifResult.rows[0].count),
        selesai: parseInt(reviewResult.rows[0].count),
        jenis_aktif: parseInt(jenisResult.rows[0].count),
      }
    });
  } catch (err) {
    console.error('GetBantuanSosialStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createBantuanSosial(req, res) {
  try {
    const { user_id, jenis_bantuan, tanggal_bantuan, tanggal_mulai, tanggal_selesai, tahun, nominal, keterangan } = req.body;
    
    if (!user_id || !jenis_bantuan) {
      return res.status(400).json({ success: false, message: 'user_id dan jenis_bantuan wajib diisi.' });
    }

    const tBantuan = tanggal_bantuan ? String(tanggal_bantuan).trim() : null;
    const tMulai = tanggal_mulai ? String(tanggal_mulai).trim() : null;
    const tSelesai = tanggal_selesai ? String(tanggal_selesai).trim() : null;

    if (!tBantuan && !tMulai && !tahun) {
      return res.status(400).json({ success: false, message: 'Tanggal bantuan atau tanggal mulai wajib diisi.' });
    }

    if (tMulai && tSelesai && tSelesai < tMulai) {
      return res.status(400).json({ success: false, message: 'Tanggal selesai tidak boleh lebih awal dari tanggal mulai.' });
    }

    const nominalAngka = Number(nominal);
    if (nominal === undefined || nominal === null || nominal === '' || !Number.isFinite(nominalAngka) || nominalAngka < 0) {
      return res.status(400).json({ success: false, message: 'Nominal wajib diisi dan tidak boleh negatif.' });
    }
    const ketFinal = (keterangan || '').toString().trim();
    if (nominalAngka === 0 && ketFinal === '') {
      return res.status(400).json({ success: false, message: 'Keterangan wajib diisi bila nominal 0.' });
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
      `INSERT INTO bantuan_sosial (user_id, jenis_bantuan, tanggal_bantuan, tanggal_mulai, tanggal_selesai, tahun, nominal, keterangan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [user_id, jenis_bantuan, tBantuan, tMulai, tSelesai, tahunHitung, nominalAngka, ketFinal || null, req.user.id]
    );

    const rowBaru = result.rows[0];
    const penerima = await pool.query('SELECT nama FROM users WHERE id = $1', [user_id]);
    const descPeriode = formatPeriodeBansos(rowBaru);
    await logActivity(
      req,
      TIPE.CREATE,
      `Menetapkan penerima bantuan sosial: ${penerima.rows[0]?.nama || user_id} — ` +
        `${jenis_bantuan} (${descPeriode}), ${rupiah(nominalAngka)}`
    );

    return res.status(201).json({ success: true, message: 'Penerima bantuan berhasil ditambahkan.', data: rowBaru });
  } catch (err) {
    console.error('CreateBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateBantuanSosial(req, res) {
  try {
    const { id } = req.params;
    const { jenis_bantuan, tanggal_bantuan, tanggal_mulai, tanggal_selesai, tahun, nominal, status, keterangan } = req.body;

    let nominalBaru = null;
    if (nominal !== undefined && nominal !== null && nominal !== '') {
      const n = Number(nominal);
      if (!Number.isFinite(n) || n < 0) {
        return res.status(400).json({ success: false, message: 'Nominal harus berupa angka tidak negatif.' });
      }
      nominalBaru = n;
    }
    if (nominalBaru === 0) {
      const ketFinal = (keterangan || '').toString().trim();
      if (ketFinal === '') {
        return res.status(400).json({ success: false, message: 'Keterangan wajib diisi bila nominal 0.' });
      }
    }

    const oldData = await pool.query('SELECT * FROM bantuan_sosial WHERE id = $1', [id]);
    if (oldData.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });

    const old = oldData.rows[0];

    const tBantuan = tanggal_bantuan !== undefined ? (tanggal_bantuan ? String(tanggal_bantuan).trim() : null) : old.tanggal_bantuan;
    const tMulai = tanggal_mulai !== undefined ? (tanggal_mulai ? String(tanggal_mulai).trim() : null) : old.tanggal_mulai;
    const tSelesai = tanggal_selesai !== undefined ? (tanggal_selesai ? String(tanggal_selesai).trim() : null) : old.tanggal_selesai;

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
        tanggal_bantuan = $2::date,
        tanggal_mulai = $3::date,
        tanggal_selesai = $4::date,
        tahun = COALESCE($5, tahun),
        nominal = COALESCE($6, nominal),
        status = COALESCE($7, status),
        keterangan = COALESCE($8, keterangan),
        updated_at = NOW()
       WHERE id = $9 RETURNING *`,
      [jenis_bantuan, tBantuan, tMulai, tSelesai, tahunHitung, nominal, status, keterangan, id]
    );

    const changes = [];
    if (jenis_bantuan && old.jenis_bantuan !== jenis_bantuan) changes.push('Jenis Bantuan');
    if (tBantuan !== old.tanggal_bantuan) changes.push('Tanggal Bantuan');
    if (tMulai !== old.tanggal_mulai) changes.push('Tanggal Mulai');
    if (tSelesai !== old.tanggal_selesai) changes.push('Tanggal Selesai');
    if (nominal !== undefined && Number(old.nominal) !== Number(nominal)) changes.push('Nominal');
    if (keterangan !== undefined && old.keterangan !== keterangan) changes.push('Keterangan');
    if (status && old.status !== status) changes.push('Status');

    if (changes.length > 0) {
      const ket_log = `Mengubah: ${changes.join(', ')}`;
      await pool.query(
        'INSERT INTO bantuan_sosial_log (bantuan_sosial_id, changed_by, old_status, new_status, keterangan_log) VALUES ($1, $2, $3, $4, $5)',
        [id, req.user.id, old.status, status || old.status, ket_log]
      );

      const penerima = await pool.query(
        'SELECT u.nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id WHERE bs.id = $1',
        [id]
      );
      const rincian = bandingkan(old, result.rows[0], {
        jenis_bantuan: 'jenis',
        tanggal_bantuan: 'tanggal bantuan',
        tanggal_mulai: 'tanggal mulai',
        tanggal_selesai: 'tanggal selesai',
        nominal: 'nominal',
        status: 'status',
      });
      await logActivity(
        req,
        TIPE.UPDATE,
        `Mengubah bantuan sosial ${penerima.rows[0]?.nama || id} — ${rincian || ket_log}`
      );
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
    const result = await pool.query(
      `SELECT log.*, u.nama AS changed_by_name 
       FROM bantuan_sosial_log log 
       LEFT JOIN users u ON log.changed_by = u.id 
       WHERE log.bantuan_sosial_id = $1
         ${req.user.role === 'warga'
    ? 'AND EXISTS (SELECT 1 FROM bantuan_sosial bs WHERE bs.id = log.bantuan_sosial_id AND bs.user_id = $2)'
    : ''}
       ORDER BY log.created_at DESC`,
      req.user.role === 'warga' ? [id, req.user.id] : [id]
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
    const sebelum = await pool.query(
      'SELECT bs.*, u.nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id WHERE bs.id = $1',
      [id]
    );

    const result = await pool.query('DELETE FROM bantuan_sosial WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });

    const b = sebelum.rows[0] || {};
    const periodeDesc = formatPeriodeBansos(b);
    await logActivity(
      req,
      TIPE.DELETE,
      `Menghapus data bantuan sosial ${b.nama || id} — ${b.jenis_bantuan || '-'} (${periodeDesc}), ` +
        `${rupiah(b.nominal || 0)}, status ${b.status || '-'}`
    );

    return res.status(200).json({ success: true, message: 'Data bantuan berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function exportBantuanSosial(req, res) {
  try {
    const { tahun, tanggal_mulai, tanggal_selesai, jenis_bantuan, status, search, format } = req.query;
    let query = `SELECT bs.*, u.nama AS nama_warga, COALESCE(u.nik, u.username) AS nik_warga, c.nama AS created_by_nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id LEFT JOIN users c ON bs.created_by = c.id WHERE 1=1`;
    const params = [];

    if (req.user.role === 'warga') {
      params.push(req.user.id);
      query += ` AND bs.user_id = $${params.length}`;
    }

    query += buildDateFilter(tahun, tanggal_mulai, tanggal_selesai, params);
    if (jenis_bantuan && jenis_bantuan !== 'Semua Jenis') { params.push(jenis_bantuan); query += ` AND bs.jenis_bantuan = $${params.length}`; }
    if (status && status !== 'Semua Status') { params.push(status); query += ` AND bs.status = $${params.length}`; }
    if (search) { params.push(`%${search}%`); query += ` AND (u.nama ILIKE $${params.length} OR COALESCE(u.nik, u.username) ILIKE $${params.length})`; }
    query += ' ORDER BY bs.created_at DESC';
    const result = await pool.query(query, params);
    const data = result.rows;

    if (format === 'pdf') {
      const doc = new PDFDocument({ margin: 30, size: 'A4' });
      res.setHeader('Content-disposition', 'attachment; filename=Data_Bantuan_Sosial.pdf');
      res.setHeader('Content-type', 'application/pdf');
      doc.pipe(res);

      doc.fontSize(16).text('Laporan Data Bantuan Sosial', { align: 'center' }).moveDown();

      const table = {
        headers: ['No', 'Nama Warga', 'NIK', 'Jenis Bantuan', 'Tanggal / Periode', 'Status', 'Nominal', 'Keterangan'],
        rows: data.map((d, i) => [
          (i + 1).toString(),
          d.nama_warga || '-',
          d.nik_warga || '-',
          d.jenis_bantuan || '-',
          formatPeriodeBansos(d),
          d.status || '-',
          d.nominal ? `Rp ${parseInt(d.nominal).toLocaleString('id-ID')}` : '-',
          d.keterangan || '-'
        ])
      };

      await doc.table(table, {
        prepareHeader: () => doc.font('Helvetica-Bold').fontSize(9),
        prepareRow: () => doc.font('Helvetica').fontSize(9)
      });
      doc.end();
    } else {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Data Bantuan');

      sheet.columns = [
        { header: 'No', key: 'no', width: 5 },
        { header: 'Nama Warga', key: 'nama', width: 25 },
        { header: 'NIK', key: 'nik', width: 20 },
        { header: 'Jenis Bantuan', key: 'jenis', width: 20 },
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

module.exports = { getBantuanSosial, getBantuanSosialStats, createBantuanSosial, updateBantuanSosial, deleteBantuanSosial, exportBantuanSosial, getBantuanSosialHistory };
