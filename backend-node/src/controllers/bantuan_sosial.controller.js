const { pool } = require('../config/database');
const { logActivity, rupiah, bandingkan, TIPE } = require('../services/log.service');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');

async function getBantuanSosial(req, res) {
  try {
    const { tahun, jenis_bantuan, status, search } = req.query;
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 10;
    const offset = (page - 1) * limit;

    let where = 'WHERE 1=1';
    const params = [];

    // Daftar penerima bantuan sosial adalah salah satu data paling sensitif di
    // sistem ini — ia menyebutkan siapa saja yang tidak mampu, lengkap dengan
    // nama dan NIK. Warga hanya boleh melihat catatannya sendiri.
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      where += ` AND bs.user_id = $${params.length}`;
    }

    if (tahun && tahun !== 'Semua') { params.push(parseInt(tahun)); where += ` AND bs.tahun = $${params.length}`; }
    if (jenis_bantuan && jenis_bantuan !== 'Semua Jenis') { params.push(jenis_bantuan); where += ` AND bs.jenis_bantuan = $${params.length}`; }
    if (status && status !== 'Semua Status') { params.push(status); where += ` AND bs.status = $${params.length}`; }
    if (search) { params.push(`%${search}%`); where += ` AND (u.nama ILIKE $${params.length} OR COALESCE(u.nik, u.username) ILIKE $${params.length})`; }

    // Jumlah total dihitung dengan filter yang SAMA supaya halaman terakhir
    // tidak salah menyatakan berapa banyak data yang ada.
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
    // Kartu ringkasan harus disaring dengan aturan yang sama seperti daftarnya.
    // Kalau tidak, angkanya menghitung baris yang tidak boleh dilihat pemanggil
    // — dan jumlah penerima bantuan se-RT bocor lewat sebuah angka, tanpa satu
    // nama pun ditampilkan.
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
    const { user_id, jenis_bantuan, tahun, nominal, keterangan } = req.body;
    if (!user_id || !jenis_bantuan || !tahun) return res.status(400).json({ success: false, message: 'user_id, jenis_bantuan, dan tahun wajib diisi.' });

    // Nominal wajib, dan itu ditegakkan di sini — bukan hanya di form.
    //
    // Sebelumnya nilainya `nominal || 0`, sehingga permintaan tanpa nominal
    // tetap tersimpan sebagai Rp 0. Ini pencatatan alokasi uang kepada orang
    // tertentu: baris bernilai nol tidak bisa dibedakan antara "bantuan barang
    // tanpa nilai uang" dan "petugas lupa mengisi", dan keduanya ikut terbawa
    // ke rekap serta baris log.
    const nominalAngka = Number(nominal);
    if (nominal === undefined || nominal === null || nominal === '' || !Number.isFinite(nominalAngka) || nominalAngka <= 0) {
      return res.status(400).json({ success: false, message: 'Nominal wajib diisi dan harus lebih besar dari 0.' });
    }

    // Validasi user exists
    const userCheck = await pool.query('SELECT id FROM users WHERE id = $1', [user_id]);
    if (userCheck.rows.length === 0) return res.status(404).json({ success: false, message: 'Warga tidak ditemukan.' });

    // Validasi duplikasi
    const dupCheck = await pool.query('SELECT id FROM bantuan_sosial WHERE user_id = $1 AND jenis_bantuan = $2 AND tahun = $3', [user_id, jenis_bantuan, tahun]);
    if (dupCheck.rows.length > 0) return res.status(409).json({ success: false, message: 'Warga sudah terdaftar untuk jenis bantuan ini di tahun tersebut.' });

    const result = await pool.query(
      `INSERT INTO bantuan_sosial (user_id, jenis_bantuan, tahun, nominal, keterangan, created_by) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [user_id, jenis_bantuan, tahun, nominalAngka, keterangan || null, req.user.id]
    );
    // Nama penerima diambil supaya lognya bisa dibaca tanpa membuka tabel lain.
    // Ini alokasi uang kepada orang tertentu — baris log yang hanya memuat UUID
    // tidak bisa dipakai siapa pun untuk memeriksa kewajarannya.
    const penerima = await pool.query('SELECT nama FROM users WHERE id = $1', [user_id]);
    await logActivity(
      req,
      TIPE.CREATE,
      `Menetapkan penerima bantuan sosial: ${penerima.rows[0]?.nama || user_id} — ` +
        `${jenis_bantuan} tahun ${tahun}, ${rupiah(nominalAngka)}`
    );

    return res.status(201).json({ success: true, message: 'Penerima bantuan berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateBantuanSosial Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateBantuanSosial(req, res) {
  try {
    const { id } = req.params;
    const { jenis_bantuan, tahun, nominal, status, keterangan } = req.body;

    // Ini update parsial: kolom yang tidak dikirim dipertahankan lewat COALESCE.
    // Jadi `nominal` boleh saja absen — yang tidak boleh adalah dikirim dengan
    // nilai yang tidak sah, karena itu akan menimpa angka yang sudah benar.
    if (nominal !== undefined && nominal !== null && nominal !== '') {
      const n = Number(nominal);
      if (!Number.isFinite(n) || n <= 0) {
        return res.status(400).json({ success: false, message: 'Nominal harus berupa angka lebih besar dari 0.' });
      }
    }

    // Get old data
    const oldData = await pool.query('SELECT * FROM bantuan_sosial WHERE id = $1', [id]);
    if (oldData.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });
    
    const old = oldData.rows[0];

    const result = await pool.query(
      `UPDATE bantuan_sosial SET jenis_bantuan = COALESCE($1, jenis_bantuan), tahun = COALESCE($2, tahun), nominal = COALESCE($3, nominal), status = COALESCE($4, status), keterangan = COALESCE($5, keterangan), updated_at = NOW() WHERE id = $6 RETURNING *`,
      [jenis_bantuan, tahun, nominal, status, keterangan, id]
    );
    
    // Log if anything changed
    const changes = [];
    if (jenis_bantuan && old.jenis_bantuan !== jenis_bantuan) changes.push('Jenis Bantuan');
    if (tahun && old.tahun !== Number(tahun)) changes.push('Tahun');
    if (nominal !== undefined && Number(old.nominal) !== Number(nominal)) changes.push('Nominal');
    if (keterangan !== undefined && old.keterangan !== keterangan) changes.push('Keterangan');
    if (status && old.status !== status) changes.push('Status');

    if (changes.length > 0) {
      const ket_log = `Mengubah: ${changes.join(', ')}`;
      await pool.query(
        'INSERT INTO bantuan_sosial_log (bantuan_sosial_id, changed_by, old_status, new_status, keterangan_log) VALUES ($1, $2, $3, $4, $5)',
        [id, req.user.id, old.status, status || old.status, ket_log]
      );

      // `bantuan_sosial_log` di atas adalah jejak khusus modul ini dan hanya
      // terlihat dari layar Bantuan Sosial. Log Aktivitas pusat perlu ikut
      // tahu — di sanalah seorang pengawas melihat SELURUH sistem dalam satu
      // urutan waktu, dan hanya tabel itu yang tidak bisa dihapus siapa pun.
      const penerima = await pool.query(
        'SELECT u.nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id WHERE bs.id = $1',
        [id]
      );
      const rincian = bandingkan(old, result.rows[0], {
        jenis_bantuan: 'jenis',
        tahun: 'tahun',
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
    // Identitas penerima dibaca SEBELUM baris bantuannya hilang.
    const sebelum = await pool.query(
      'SELECT bs.*, u.nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id WHERE bs.id = $1',
      [id]
    );

    const result = await pool.query('DELETE FROM bantuan_sosial WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Data bantuan tidak ditemukan.' });

    const b = sebelum.rows[0] || {};
    await logActivity(
      req,
      TIPE.DELETE,
      `Menghapus data bantuan sosial ${b.nama || id} — ${b.jenis_bantuan || '-'} tahun ${b.tahun || '-'}, ` +
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
    const { tahun, jenis_bantuan, status, search, format } = req.query;
    let query = `SELECT bs.*, u.nama AS nama_warga, COALESCE(u.nik, u.username) AS nik_warga, c.nama AS created_by_nama FROM bantuan_sosial bs JOIN users u ON bs.user_id = u.id LEFT JOIN users c ON bs.created_by = c.id WHERE 1=1`;
    const params = [];

    // Export disaring sama seperti daftarnya. Melewatkan ini justru yang paling
    // berbahaya: hasilnya berupa berkas yang bisa disimpan dan disebarkan.
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      query += ` AND bs.user_id = $${params.length}`;
    }

    if (tahun && tahun !== 'Semua') { params.push(parseInt(tahun)); query += ` AND bs.tahun = $${params.length}`; }
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
        headers: ['No', 'Nama Warga', 'NIK', 'Jenis Bantuan', 'Tahun', 'Status', 'Nominal', 'Keterangan'],
        rows: data.map((d, i) => [
          (i + 1).toString(),
          d.nama_warga || '-',
          d.nik_warga || '-',
          d.jenis_bantuan || '-',
          d.tahun?.toString() || '-',
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
      // Default to excel
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Data Bantuan');
      
      sheet.columns = [
        { header: 'No', key: 'no', width: 5 },
        { header: 'Nama Warga', key: 'nama', width: 25 },
        { header: 'NIK', key: 'nik', width: 20 },
        { header: 'Jenis Bantuan', key: 'jenis', width: 20 },
        { header: 'Tahun', key: 'tahun', width: 10 },
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
          tahun: d.tahun,
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
