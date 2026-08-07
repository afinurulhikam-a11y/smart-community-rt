const { pool } = require('../config/database');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const { logActivity, rupiah } = require('../services/log.service');

/**
 * Tata letak kolom export. Excel dan PDF sama-sama membacanya supaya keduanya
 * tidak bisa lepas sinkron — pola yang sama dipakai di warga.controller.js
 * dan bill.controller.js.
 */
const KOLOM = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'TANGGAL', key: 'tanggal', width: 14 },
  { header: 'JENIS', key: 'jenis', width: 14 },
  { header: 'KATEGORI', key: 'kategori', width: 28 },
  { header: 'KETERANGAN', key: 'deskripsi', width: 40 },
  { header: 'PEMASUKAN', key: 'pemasukan', width: 16 },
  { header: 'PENGELUARAN', key: 'pengeluaran', width: 16 },
  { header: 'SALDO', key: 'saldo_berjalan', width: 16 },
  { header: 'SUMBER', key: 'sumber', width: 12 },
  { header: 'DICATAT OLEH', key: 'created_by_nama', width: 22 },
];

const pad = (n) => n.toString().padStart(2, '0');

function formatTanggal(nilai) {
  if (!nilai) return '';
  const d = nilai instanceof Date ? nilai : new Date(nilai);
  if (isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Bangun klausa WHERE bersama untuk daftar dan export. */
function buildFilter(req) {
  const { tipe, sumber, bulan, tahun, kategori_id, search, dari, sampai } = req.query;
  const kondisi = [];
  const params = [];
  const p = () => `$${params.length}`;

  if (tipe) { params.push(tipe); kondisi.push(`f.tipe = ${p()}`); }
  // `sumber` membedakan transaksi manual dari hasil pembayaran iuran.
  // 'non_iuran' berarti hanya kolom yang BUKAN iuran (eksplisit manual atau
  // baris lama yang tak mencatat sumber), tanpa menyentuh tipe — jadi baik
  // pemasukan maupun pengeluaran ikut terlihat.
  if (sumber === 'non_iuran') {
    kondisi.push(`COALESCE(f.sumber, 'manual') <> 'iuran'`);
  } else if (sumber) {
    params.push(sumber); kondisi.push(`f.sumber = ${p()}`);
  }
  if (bulan) { params.push(`${bulan}%`); kondisi.push(`f.tanggal::TEXT LIKE ${p()}`); }
  if (tahun && !bulan) { params.push(`${tahun}-%`); kondisi.push(`f.tanggal::TEXT LIKE ${p()}`); }
  if (kategori_id) { params.push(kategori_id); kondisi.push(`f.kategori_id = ${p()}`); }
  if (dari) { params.push(dari); kondisi.push(`f.tanggal >= ${p()}`); }
  if (sampai) { params.push(sampai); kondisi.push(`f.tanggal <= ${p()}`); }
  if (search) {
    params.push(`%${search}%`);
    kondisi.push(`(f.deskripsi ILIKE ${p()} OR f.kategori ILIKE ${p()})`);
  }

  const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';
  return { where, params };
}

/**
 * Saldo berjalan dihitung di SQL lewat window function, bukan di klien, supaya
 * daftar dan laporan memakai angka yang sama persis.
 */
function buildQuery(where) {
  return `
    WITH CTE AS (
      SELECT f.*,
             u.nama AS created_by_nama,
             kk.tipe AS kategori_tipe,
             SUM(CASE WHEN f.tipe = 'pemasukan' THEN f.jumlah ELSE -f.jumlah END)
               OVER (ORDER BY f.tanggal, f.created_at
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS saldo_berjalan
      FROM finances f
      LEFT JOIN users u ON f.created_by = u.id
      LEFT JOIN kategori_kas kk ON f.kategori_id = kk.id
      WHERE f.deleted_at IS NULL
    )
    SELECT *, COUNT(*) OVER() AS total_data 
    FROM CTE AS f
    ${where}
    ORDER BY f.tanggal DESC, f.created_at DESC
  `;
}

async function getTransactions(req, res) {
  try {
    const { where, params } = buildFilter(req);
    let query = buildQuery(where);

    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 25;
    const offset = (page - 1) * limit;

    params.push(limit, offset);
    query += ` LIMIT $${params.length - 1} OFFSET $${params.length}`;

    const result = await pool.query(query, params);
    
    const totalData = result.rows.length > 0 ? parseInt(result.rows[0].total_data, 10) : 0;
    const totalPages = Math.ceil(totalData / limit);

    return res.status(200).json({ 
      success: true, 
      count: result.rows.length, 
      data: result.rows,
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        limit: limit
      }
    });
  } catch (err) {
    console.error('GetTransactions Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Ringkasan untuk tiga kartu di layar Kas RT, yang cakupannya BERBEDA:
 * dua kartu pertama bulan berjalan, kartu ketiga saldo sepanjang masa.
 *
 * Field total_pemasukan/total_pengeluaran/saldo dipertahankan apa adanya
 * karena dipakai layar BOP, Laporan Keuangan, dan dashboard.
 */
async function getSummary(req, res) {
  try {
    const { bulan, sumber } = req.query;

    // `sumber: non_iuran` diteruskan dari filter "Jenis" layar Kas RT, supaya
    // kartu 1-2 konsisten dengan isi tabel. Saldo_total sengaja TIDAK ikut
    // tersaring: saldo adalah jumlah RIIL semua uang di kas, termasuk yang
    // berasal dari iuran — hanya menampilkan non-iuran di sini justru
    // melaporkan saldo yang lebih rendah dari kenyataan.
    //
    // Parameter memakai indeks eksplisit ($1, $2, ...) karena kedua query
    // menggabungkan beberapa klausa; menghitung indeks "dari sisa" rapuh.
    const sumberKondisi = (pos) => {
      if (sumber === 'non_iuran') return `COALESCE(sumber, 'manual') <> 'iuran'`;
      if (sumber) return `sumber = $${pos}`;
      return '';
    };

    // Query LAMA: total sepanjang filter bulan (+ sumber), dipakai field
    // total_pemasukan/total_pengeluaran/saldo.
    const lmp = [];
    let lmwhere = 'WHERE deleted_at IS NULL';
    if (bulan) {
      lmp.push(`${bulan}%`);
      lmwhere += ` AND tanggal::TEXT LIKE $${lmp.length}`;
    }
    const lms = sumberKondisi(lmp.length + 1);
    if (lms) lmwhere += ` AND ${lms}`;

    // Query BARU: pemasukan/pengeluaran "bulan ini" + saldo sepanjang masa.
    // Parameter pertama ($1) selalu periode; sumber eksplisit (bila ada)
    // menempati $2.
    const bsource = (sumber && sumber !== 'non_iuran') ? sumber : null;
    let bwhere = 'WHERE deleted_at IS NULL';
    if (sumber === 'non_iuran') bwhere += ` AND COALESCE(sumber, 'manual') <> 'iuran'`;
    if (bsource) bwhere += ` AND sumber = $2`;

    const periode = bulan || `${new Date().getFullYear()}-${pad(new Date().getMonth() + 1)}`;

    const [lama, baru] = await Promise.all([
      pool.query(`
        SELECT
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' THEN jumlah ELSE 0 END), 0)::float8 AS total_pemasukan,
          COALESCE(SUM(CASE WHEN tipe = 'pengeluaran' THEN jumlah ELSE 0 END), 0)::float8 AS total_pengeluaran,
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' THEN jumlah ELSE -jumlah END), 0)::float8 AS saldo
        FROM finances ${lmwhere}
      `, [...lmp, ...(sumber && sumber !== 'non_iuran' ? [sumber] : [])]),
      pool.query(`
        SELECT
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' AND tanggal::TEXT LIKE $1 THEN jumlah ELSE 0 END), 0)::float8 AS pemasukan_bulan,
          COALESCE(SUM(CASE WHEN tipe = 'pengeluaran' AND tanggal::TEXT LIKE $1 THEN jumlah ELSE 0 END), 0)::float8 AS pengeluaran_bulan,
          -- Saldo kas selalu sepanjang masa, tidak pernah disaring periode.
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' THEN jumlah ELSE -jumlah END), 0)::float8 AS saldo_total,
          COUNT(*)::int AS jumlah_transaksi
        FROM finances
        ${bwhere}
      `, [`${periode}%`, ...(bsource ? [bsource] : [])]),
    ]);

    return res.status(200).json({
      success: true,
      data: { periode, ...lama.rows[0], ...baru.rows[0] },
    });
  } catch (err) {
    console.error('GetSummary Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Agregat pemasukan/pengeluaran per bulan untuk grafik dashboard.
 *
 * Dihitung di SQL, bukan di klien dari daftar transaksi — daftar itu
 * ter-paginate (mis. 10 baris), jadi chart yang dibangun dari `data` hanya
 * melihat halaman pertama dan salah melaporkan bulan-bulan lain. Query ini
 * menjumlahkan SEMUA baris per bulan, tanpa LIMIT.
 */
async function getBulanan(req, res) {
  try {
    const rentang = parseInt(req.query.rentang, 10) || 6;
    const dibatasi = Math.min(Math.max(rentang, 1), 24);

    const result = await pool.query(`
      SELECT
        to_char(f.tanggal, 'YYYY-MM') AS bulan,
        COALESCE(SUM(CASE WHEN f.tipe = 'pemasukan' THEN f.jumlah ELSE 0 END), 0)::float8 AS pemasukan,
        COALESCE(SUM(CASE WHEN f.tipe = 'pengeluaran' THEN f.jumlah ELSE 0 END), 0)::float8 AS pengeluaran
      FROM finances f
      WHERE f.deleted_at IS NULL
        AND f.tanggal >= date_trunc('month', CURRENT_DATE - make_interval(months => $1 - 1))
      GROUP BY 1
      ORDER BY 1
    `, [dibatasi]);

    return res.status(200).json({ success: true, data: result.rows });
  } catch (err) {
    console.error('GetBulanan Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Ambil kategori dan pastikan tipenya cocok dengan jenis transaksi.
 * Kategori IN hanya untuk pemasukan, OUT hanya untuk pengeluaran.
 */
async function validasiKategori(kategoriId, tipe) {
  if (!kategoriId) return { ok: true, kategori: null };

  const r = await pool.query('SELECT * FROM kategori_kas WHERE id = $1', [kategoriId]);
  if (r.rows.length === 0) {
    return { ok: false, pesan: 'Kategori kas tidak ditemukan.' };
  }
  const kategori = r.rows[0];
  const diharapkan = kategori.tipe === 'IN' ? 'pemasukan' : 'pengeluaran';
  if (tipe !== diharapkan) {
    return {
      ok: false,
      pesan: `Kategori "${kategori.nama_kategori}" hanya bisa dipakai untuk ${diharapkan}.`,
    };
  }
  return { ok: true, kategori };
}

async function createTransaction(req, res) {
  try {
    const { tipe, jumlah, deskripsi, kategori_id, kategori, tanggal } = req.body;

    // Pakai perbandingan eksplisit: `!jumlah` akan menganggap angka 0 sebagai
    // kosong sehingga pesan salahnya menyesatkan.
    if (!tipe || jumlah === undefined || jumlah === null || jumlah === '' || !deskripsi) {
      return res.status(400).json({ success: false, message: 'tipe, jumlah, dan deskripsi wajib diisi.' });
    }
    if (!['pemasukan', 'pengeluaran'].includes(tipe)) {
      return res.status(400).json({ success: false, message: 'tipe harus "pemasukan" atau "pengeluaran".' });
    }
    if (Number(jumlah) <= 0) {
      return res.status(400).json({ success: false, message: 'Jumlah harus lebih dari 0.' });
    }

    const cek = await validasiKategori(kategori_id, tipe);
    if (!cek.ok) return res.status(400).json({ success: false, message: cek.pesan });

    // Nama kategori disimpan sebagai snapshot agar catatan lama tidak ikut
    // berubah bila master di-rename.
    const namaKategori = cek.kategori ? cek.kategori.nama_kategori : (kategori || 'Umum');

    const result = await pool.query(
      `INSERT INTO finances (tipe, jumlah, deskripsi, kategori, kategori_id, tanggal, created_by, sumber)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'manual') RETURNING *`,
      [
        tipe, jumlah, deskripsi, namaKategori, kategori_id || null,
        tanggal || new Date().toISOString().split('T')[0], req.user.id,
      ]
    );
    await logActivity(
      req,
      'CREATE',
      `Mencatat ${tipe} Kas RT ${rupiah(jumlah)} — ${namaKategori}: ${deskripsi || '-'}`
    );
    return res.status(201).json({ success: true, message: 'Transaksi berhasil dicatat.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateTransaction Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Transaksi hasil pembayaran iuran tidak boleh disunting dari buku kas. */
async function pastikanManual(id) {
  const r = await pool.query('SELECT sumber, deskripsi FROM finances WHERE id = $1', [id]);
  if (r.rows.length === 0) return { ok: false, kode: 404, pesan: 'Transaksi tidak ditemukan.' };
  if (r.rows[0].sumber && r.rows[0].sumber !== 'manual') {
    return {
      ok: false,
      kode: 409,
      pesan: 'Transaksi ini berasal dari pembayaran iuran sehingga tidak bisa diubah atau dihapus dari Kas RT. Perbaiki lewat data Iuran Warga bila keliru.',
    };
  }
  return { ok: true };
}

async function updateTransaction(req, res) {
  try {
    const { id } = req.params;
    const { tipe, jumlah, deskripsi, kategori_id, tanggal } = req.body;

    const boleh = await pastikanManual(id);
    if (!boleh.ok) return res.status(boleh.kode).json({ success: false, message: boleh.pesan });

    if (tipe && !['pemasukan', 'pengeluaran'].includes(tipe)) {
      return res.status(400).json({ success: false, message: 'tipe harus "pemasukan" atau "pengeluaran".' });
    }
    if (jumlah !== undefined && Number(jumlah) <= 0) {
      return res.status(400).json({ success: false, message: 'Jumlah harus lebih dari 0.' });
    }

    let namaKategori = null;
    if (kategori_id) {
      const lama = await pool.query('SELECT tipe FROM finances WHERE id = $1', [id]);
      const cek = await validasiKategori(kategori_id, tipe || lama.rows[0].tipe);
      if (!cek.ok) return res.status(400).json({ success: false, message: cek.pesan });
      namaKategori = cek.kategori ? cek.kategori.nama_kategori : null;
    }

    const result = await pool.query(
      `UPDATE finances SET
         tipe        = COALESCE($1, tipe),
         jumlah      = COALESCE($2, jumlah),
         deskripsi   = COALESCE($3, deskripsi),
         kategori    = COALESCE($4, kategori),
         kategori_id = COALESCE($5, kategori_id),
         tanggal     = COALESCE($6, tanggal),
         updated_at  = NOW()
       WHERE id = $7 RETURNING *`,
      [tipe || null, jumlah ?? null, deskripsi || null, namaKategori, kategori_id || null, tanggal || null, id]
    );
    const baru = result.rows[0];
    await logActivity(
      req,
      'UPDATE',
      `Mengubah transaksi Kas RT ${rupiah(baru.jumlah)} — ${baru.kategori}: ${baru.deskripsi || '-'}`
    );
    return res.status(200).json({ success: true, message: 'Transaksi berhasil diperbarui.', data: baru });
  } catch (err) {
    console.error('UpdateTransaction Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}


/** Ubah satu baris database menjadi baris export sesuai urutan KOLOM. */
function toRow(t, index) {
  const masuk = t.tipe === 'pemasukan';
  return {
    no: index + 1,
    tanggal: formatTanggal(t.tanggal),
    jenis: masuk ? 'Pemasukan' : 'Pengeluaran',
    kategori: t.kategori || '-',
    deskripsi: t.deskripsi || '-',
    pemasukan: masuk ? Number(t.jumlah) : 0,
    pengeluaran: masuk ? 0 : Number(t.jumlah),
    saldo_berjalan: Number(t.saldo_berjalan) || 0,
    sumber: t.sumber === 'iuran' ? 'Iuran' : 'Manual',
    created_by_nama: t.created_by_nama || '-',
  };
}

async function exportFinances(req, res) {
  try {
    const format = (req.query.format || 'excel').toLowerCase();
    const { where, params } = buildFilter(req);
    const result = await pool.query(buildQuery(where), params);
    const rows = result.rows;

    const totalMasuk = rows.filter((r) => r.tipe === 'pemasukan').reduce((s, r) => s + Number(r.jumlah), 0);
    const totalKeluar = rows.filter((r) => r.tipe === 'pengeluaran').reduce((s, r) => s + Number(r.jumlah), 0);

    if (format === 'pdf') {
      const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', 'attachment; filename=Buku_Kas_RT.pdf');
      doc.pipe(res);

      doc.fontSize(18).text('Buku Kas RT', { align: 'center' });
      doc.fontSize(10).text(
        `Pemasukan: Rp ${totalMasuk.toLocaleString('id-ID')}  |  ` +
        `Pengeluaran: Rp ${totalKeluar.toLocaleString('id-ID')}  |  ` +
        `Saldo: Rp ${(totalMasuk - totalKeluar).toLocaleString('id-ID')}`,
        { align: 'center' }
      );
      doc.moveDown();

      await doc.table({
        title: 'Riwayat Transaksi',
        headers: KOLOM.map((k) => k.header),
        rows: rows.map((t, i) => {
          const r = toRow(t, i);
          return KOLOM.map((k) => {
            const v = r[k.key];
            return ['pemasukan', 'pengeluaran', 'saldo_berjalan'].includes(k.key)
              ? (v === 0 && k.key !== 'saldo_berjalan' ? '-' : `Rp ${v.toLocaleString('id-ID')}`)
              : String(v);
          });
        }),
      }, {
        prepareHeader: () => doc.font('Helvetica-Bold').fontSize(8),
        prepareRow: () => doc.font('Helvetica').fontSize(7),
      });

      doc.end();
      return;
    }

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Buku Kas RT');
    worksheet.columns = KOLOM;
    worksheet.getRow(1).font = { bold: true };

    rows.forEach((t, i) => {
      const row = worksheet.addRow(toRow(t, i));
      ['pemasukan', 'pengeluaran', 'saldo_berjalan'].forEach((k) => {
        row.getCell(k).numFmt = '#,##0';
      });
    });

    // Baris total di akhir agar laporan bisa dibaca tanpa menghitung ulang.
    const total = worksheet.addRow({
      deskripsi: 'TOTAL',
      pemasukan: totalMasuk,
      pengeluaran: totalKeluar,
      saldo_berjalan: totalMasuk - totalKeluar,
    });
    total.font = { bold: true };
    ['pemasukan', 'pengeluaran', 'saldo_berjalan'].forEach((k) => {
      total.getCell(k).numFmt = '#,##0';
    });

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=Buku_Kas_RT.xlsx');
    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error('ExportFinances Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export.' });
    }
  }
}

/** Hapus satu transaksi kas manual. Baris dari iuran ditolak — dikoreksi
 *  lewat Iuran Warga, bukan dari buku kas. */
async function deleteTransaction(req, res) {
  try {
    const { id } = req.params;

    const boleh = await pastikanManual(id);
    if (!boleh.ok) return res.status(boleh.kode).json({ success: false, message: boleh.pesan });

    const result = await pool.query(
      'DELETE FROM finances WHERE id = $1 RETURNING id, tipe, jumlah, deskripsi',
      [id]
    );
    const hapus = result.rows[0];
    await logActivity(
      req,
      'DELETE',
      `Menghapus ${hapus.tipe} Kas RT ${rupiah(hapus.jumlah)} — ${hapus.deskripsi || '-'}`
    );
    return res.status(200).json({ success: true, message: 'Transaksi berhasil dihapus.', data: hapus });
  } catch (err) {
    console.error('Delete Finance Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getTransactions,
  getSummary,
  getBulanan,
  createTransaction,
  updateTransaction,
  deleteTransaction,
  exportFinances,
};
