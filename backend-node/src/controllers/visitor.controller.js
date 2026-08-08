const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');

async function getVisitors(req, res) {
  try {
    const { status, tipe, search, tanggal, page: rawPage, limit: rawLimit } = req.query;

    const page = Math.max(parseInt(rawPage, 10) || 1, 1);
    const limit = Math.min(Math.max(parseInt(rawLimit, 10) || 10, 1), 100);
    const offset = (page - 1) * limit;

    let baseQuery = `FROM visitors v LEFT JOIN users u ON v.created_by = u.id WHERE 1=1`;
    const params = [];

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
    const today = new Date().toISOString().split('T')[0];
    const isWarga = req.user.role === 'warga';
    const filter = isWarga ? ' AND created_by = $2' : '';
    const p = isWarga ? [null, req.user.id] : [null];
    p[0] = today;

    const todayResult = await pool.query(`SELECT COUNT(*) as count FROM visitors WHERE jam_masuk::DATE = $1::DATE${filter}`, p);
    const insideResult = await pool.query(`SELECT COUNT(*) as count FROM visitors WHERE status = 'Di Dalam'${isWarga ? ' AND created_by = $1' : ''}`, isWarga ? [req.user.id] : []);
    const stayingResult = await pool.query(`SELECT COUNT(*) as count FROM visitors WHERE tipe_keperluan = 'Menginap' AND status = 'Di Dalam'${isWarga ? ' AND created_by = $1' : ''}`, isWarga ? [req.user.id] : []);
    const totalResult = await pool.query(`SELECT COUNT(*) as count FROM visitors${isWarga ? ' WHERE created_by = $1' : ''}`, isWarga ? [req.user.id] : []);
    return res.status(200).json({
      success: true,
      data: {
        tamu_hari_ini: parseInt(todayResult.rows[0].count),
        sedang_di_dalam: parseInt(insideResult.rows[0].count),
        tamu_menginap: parseInt(stayingResult.rows[0].count),
        total_semua: parseInt(totalResult.rows[0].count),
      }
    });
  } catch (err) {
    console.error('GetVisitorStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createVisitor(req, res) {
  try {
    const { nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan } = req.body;

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

    const result = await pool.query(
      `INSERT INTO visitors (nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, plat_nomor, jenis_kendaraan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [nama_tamu.trim(), no_hp_tamu.trim(), blok_tujuan.trim(), no_hp_tujuan.trim(), tipe_keperluan || 'Kunjungan', detail_keperluan.trim(), plat_nomor ? plat_nomor.trim() : null, jenisK || null, req.user.id]
    );
    const t = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Mencatat tamu masuk: ${ringkas(t.nama_tamu)} → ${t.blok_tujuan || '-'}, keperluan ${t.tipe_keperluan || '-'}${t.plat_nomor ? `, kendaraan ${t.plat_nomor}` : ''}`);

    return res.status(201).json({ success: true, message: 'Tamu berhasil diregistrasi.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateVisitor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function checkoutVisitor(req, res) {
  try {
    const { id } = req.params;
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

module.exports = { getVisitors, getVisitorStats, createVisitor, checkoutVisitor, deleteVisitor };
