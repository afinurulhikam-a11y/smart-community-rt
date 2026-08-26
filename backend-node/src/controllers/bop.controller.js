const { pool } = require('../config/database');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const { logActivity, rupiah } = require('../services/log.service');
const { kondisiRt, klausaRt, whereRt, tolakLuarRt, rtUntukSimpan } = require('../utils/lingkup-rt');

/**
 * Tata letak kolom export, dibaca Excel dan PDF sekaligus supaya keduanya
 * tidak bisa lepas sinkron — pola yang sama dipakai di finance.controller.js.
 */
const KOLOM = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'TANGGAL', key: 'tanggal', width: 14 },
  { header: 'JENIS', key: 'jenis', width: 14 },
  { header: 'KATEGORI', key: 'kategori', width: 26 },
  { header: 'KETERANGAN', key: 'deskripsi', width: 40 },
  { header: 'PEMASUKAN', key: 'pemasukan', width: 16 },
  { header: 'PENGELUARAN', key: 'pengeluaran', width: 16 },
  { header: 'SALDO', key: 'saldo_berjalan', width: 16 },
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
  const { tipe, bulan, tahun, kategori_id, search, dari, sampai } = req.query;
  const kondisi = [];
  const params = [];
  const p = () => `$${params.length}`;

  if (tipe) { params.push(tipe); kondisi.push(`b.tipe = ${p()}`); }
  if (bulan) { params.push(`${bulan}%`); kondisi.push(`b.tanggal::TEXT LIKE ${p()}`); }
  if (tahun && !bulan) { params.push(`${tahun}-%`); kondisi.push(`b.tanggal::TEXT LIKE ${p()}`); }
  if (kategori_id) { params.push(kategori_id); kondisi.push(`b.kategori_id = ${p()}`); }
  if (dari) { params.push(dari); kondisi.push(`b.tanggal >= ${p()}`); }
  if (sampai) { params.push(sampai); kondisi.push(`b.tanggal <= ${p()}`); }
  if (search) {
    params.push(`%${search}%`);
    kondisi.push(`(b.deskripsi ILIKE ${p()} OR b.kategori ILIKE ${p()})`);
  }

  // Pelingkupan RT dipasang di sini, bukan di tiap pemanggil: buildFilter
  // yang sama menyuapi daftar, ringkasan, grafik bulanan, dan export.
  const rt = kondisiRt(req, 'b', params);
  if (rt) kondisi.push(rt);

  const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';
  return { where, params };
}

/**
 * ROWS BETWEEN, bukan RANGE bawaan: baris yang dibuat dalam satu transaksi
 * punya created_at identik (CURRENT_TIMESTAMP adalah waktu mulai transaksi),
 * dan RANGE akan menggabungkannya sehingga saldo berjalannya salah.
 */
function buildQuery(where) {
  return `
    SELECT b.*,
           u.nama AS created_by_nama,
           kb.tipe AS kategori_tipe,
           COUNT(*) OVER() AS total_data,
           SUM(CASE WHEN b.tipe = 'pemasukan' THEN b.jumlah ELSE -b.jumlah END)
             OVER (ORDER BY b.tanggal, b.created_at
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS saldo_berjalan
    FROM bop_finances b
    LEFT JOIN users u ON b.created_by = u.id
    LEFT JOIN kategori_bop kb ON b.kategori_id = kb.id
    ${where}
    ORDER BY b.tanggal DESC, b.created_at DESC
  `;
}

async function getTransactions(req, res) {
  try {
    const { where, params } = buildFilter(req);
    let query = buildQuery(where);

    // Pagination disamakan dengan finance.controller.
    //
    // Sebelumnya LIMIT hanya dipasang BILA klien kebetulan mengirim `?limit=`.
    // Layar mana pun yang memanggil endpoint ini tanpa parameter itu menerima
    // SELURUH tabel bop_finances — lengkap dengan window function yang dihitung
    // atas setiap baris — pada setiap pemuatan.
    //
    // Kas RT dan Dana BOP punya bentuk baris yang sama dan dimaksudkan
    // berperilaku sama; hanya endpoint daftarnya yang menyimpang.
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 25;
    const offset = (page - 1) * limit;

    params.push(limit, offset);
    query += ` LIMIT $${params.length - 1} OFFSET $${params.length}`;

    const result = await pool.query(query, params);

    const totalData = result.rows.length > 0 ? parseInt(result.rows[0].total_data, 10) : 0;

    return res.status(200).json({
      success: true,
      count: result.rows.length,
      data: result.rows,
      pagination: {
        total_data: totalData,
        total_pages: Math.ceil(totalData / limit),
        current_page: page,
        limit,
      },
    });
  } catch (err) {
    console.error('Get BOP Transactions Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * TIDAK ada penyaringan `deleted_at` di sini, dan itu memang benar.
 *
 * Sempat ada satu baris `WHERE deleted_at IS NULL` pada kueri di bawah, tetapi
 * `bop_finances` tidak punya kolom itu — migrasi soft-delete hanya menyentuh
 * users, keluarga, inventory, complaints, letters, agenda, dan finances.
 * Akibatnya endpoint ini selalu 500 dan keempat kartu Dana BOP tidak pernah
 * tampil sama sekali.
 *
 * Yang menutupinya: `getTransactions` dan `exportBop` di berkas yang sama juga
 * tidak menyaringnya, dan `deleteTransaction` BOP memang menghapus permanen
 * (`DELETE FROM bop_finances`), bukan menandai. Jadi barisnya bukan aturan yang
 * hilang penerapannya — ia memang tidak pernah punya tempat di modul ini.
 *
 * Kalau suatu saat BOP hendak memakai soft delete, kolomnya harus ditambahkan
 * lebih dulu DAN daftar, export, serta penghapusannya ikut menyesuaikan —
 * bukan hanya ringkasannya.
 *
 * ---
 *
 * Empat angka kartu dengan cakupan yang sengaja berbeda:
 *  - alokasi / terpakai / sisa_pagu → berbasis TAHUN (pagu memang tahunan)
 *  - pemasukan_bulan / pengeluaran_bulan → periode yang dipilih
 *  - saldo → uang di tangan sepanjang masa
 *
 * total_pemasukan/total_pengeluaran/saldo dipertahankan apa adanya karena
 * dipakai dashboard admin dan layar pengurus.
 */
async function getSummary(req, res) {
  try {
    const sekarang = new Date();
    const tahun = parseInt(req.query.tahun, 10) || sekarang.getFullYear();
    const periode = req.query.bulan || `${sekarang.getFullYear()}-${pad(sekarang.getMonth() + 1)}`;

    // Pagu dan realisasinya harus dilingkupi BERSAMA. Melingkupi salah satu
    // saja menghasilkan angka yang lebih buruk daripada dua-duanya tidak
    // dilingkupi: `sisa_pagu` = alokasi − terpakai, jadi alokasi satu RT
    // dikurangi belanja seluruh RW akan tampil minus, dan bendahara membaca
    // pagunya jebol padahal tidak.
    const paramsKas = [`${periode}%`, tahun];
    const paramsPagu = [tahun];

    const [kas, pagu] = await Promise.all([
      pool.query(`
        SELECT
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' THEN jumlah ELSE 0 END), 0)::float8 AS total_pemasukan,
          COALESCE(SUM(CASE WHEN tipe = 'pengeluaran' THEN jumlah ELSE 0 END), 0)::float8 AS total_pengeluaran,
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' THEN jumlah ELSE -jumlah END), 0)::float8 AS saldo,
          COALESCE(SUM(CASE WHEN tipe = 'pemasukan' AND tanggal::TEXT LIKE $1 THEN jumlah ELSE 0 END), 0)::float8 AS pemasukan_bulan,
          COALESCE(SUM(CASE WHEN tipe = 'pengeluaran' AND tanggal::TEXT LIKE $1 THEN jumlah ELSE 0 END), 0)::float8 AS pengeluaran_bulan,
          COALESCE(SUM(CASE WHEN tipe = 'pengeluaran' AND date_part('year', tanggal) = $2 THEN jumlah ELSE 0 END), 0)::float8 AS terpakai
        FROM bop_finances
        ${whereRt(req, '', paramsKas)}
      `, paramsKas),
      pool.query(
        `SELECT COALESCE(SUM(nominal), 0)::float8 AS alokasi FROM alokasi_bop
          WHERE tahun = $1 ${klausaRt(req, '', paramsPagu)}`,
        paramsPagu
      ),
    ]);

    const k = kas.rows[0];
    const alokasi = pagu.rows[0].alokasi;

    return res.status(200).json({
      success: true,
      data: {
        tahun,
        periode,
        alokasi,
        terpakai: k.terpakai,
        sisa_pagu: alokasi - k.terpakai,
        pemasukan_bulan: k.pemasukan_bulan,
        pengeluaran_bulan: k.pengeluaran_bulan,
        total_pemasukan: k.total_pemasukan,
        total_pengeluaran: k.total_pengeluaran,
        saldo: k.saldo,
      },
    });
  } catch (err) {
    console.error('Get BOP Summary Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Agregat pemasukan/pengeluaran per bulan untuk grafik dashboard BOP.
 * Dihitung di SQL dari SEMUA baris, bukan dari daftar ter-paginate.
 */
async function getBulanan(req, res) {
  try {
    const tahun = parseInt(req.query.tahun, 10);
    if (tahun && tahun >= 2000 && tahun <= 2100) {
      const params = [tahun];
      const result = await pool.query(`
        SELECT
          to_char(f.tanggal, 'YYYY-MM') AS bulan,
          COALESCE(SUM(CASE WHEN f.tipe = 'pemasukan' THEN f.jumlah ELSE 0 END), 0)::float8 AS pemasukan,
          COALESCE(SUM(CASE WHEN f.tipe = 'pengeluaran' THEN f.jumlah ELSE 0 END), 0)::float8 AS pengeluaran
        FROM bop_finances f
        WHERE EXTRACT(YEAR FROM f.tanggal) = $1
          ${klausaRt(req, 'f', params)}
        GROUP BY 1
        ORDER BY 1
      `, params);

      return res.status(200).json({ success: true, data: result.rows });
    }

    const rentang = parseInt(req.query.rentang, 10) || 12;
    const dibatasi = Math.min(Math.max(rentang, 1), 24);

    const params = [dibatasi];
    const result = await pool.query(`
      SELECT
        to_char(f.tanggal, 'YYYY-MM') AS bulan,
        COALESCE(SUM(CASE WHEN f.tipe = 'pemasukan' THEN f.jumlah ELSE 0 END), 0)::float8 AS pemasukan,
        COALESCE(SUM(CASE WHEN f.tipe = 'pengeluaran' THEN f.jumlah ELSE 0 END), 0)::float8 AS pengeluaran
      FROM bop_finances f
      WHERE f.tanggal >= date_trunc('month', CURRENT_DATE - make_interval(months => $1 - 1))
        ${klausaRt(req, 'f', params)}
      GROUP BY 1
      ORDER BY 1
    `, params);

    return res.status(200).json({ success: true, data: result.rows });
  } catch (err) {
    console.error('Get BOP Bulanan Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Kategori IN hanya untuk pemasukan, OUT hanya untuk pengeluaran. */
async function validasiKategori(kategoriId, tipe) {
  if (!kategoriId) return { ok: true, kategori: null };

  const r = await pool.query('SELECT * FROM kategori_bop WHERE id = $1', [kategoriId]);
  if (r.rows.length === 0) {
    return { ok: false, pesan: 'Kategori BOP tidak ditemukan.' };
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

/**
 * Susun peringatan bila belanja setahun melampaui pagu.
 *
 * Sengaja TIDAK memblokir: bendahara harus tetap bisa mencatat kenyataan yang
 * sudah terjadi. Yang penting pelampauannya terlihat jelas.
 */
async function cekPagu(req, tahun, tambahan = 0, kecualikanId = null) {
  // `req` adalah argumen PERTAMA, bukan tambahan di ujung, supaya pemanggil
  // yang lupa mengirimnya gagal seketika alih-alih diam-diam membandingkan
  // pagu satu RT dengan belanja seluruh RW.
  const pParamsPagu = [tahun];
  const pParamsPakai = [tahun, kecualikanId];
  const [pagu, pakai] = await Promise.all([
    pool.query(
      `SELECT COALESCE(SUM(nominal), 0)::float8 AS n FROM alokasi_bop
        WHERE tahun = $1 ${klausaRt(req, '', pParamsPagu)}`,
      pParamsPagu
    ),
    pool.query(
      `SELECT COALESCE(SUM(jumlah), 0)::float8 AS n FROM bop_finances
       WHERE tipe = 'pengeluaran' AND date_part('year', tanggal) = $1
         AND ($2::uuid IS NULL OR id <> $2::uuid)
         ${klausaRt(req, '', pParamsPakai)}`,
      pParamsPakai
    ),
  ]);

  const alokasi = pagu.rows[0].n;
  const total = pakai.rows[0].n + Number(tambahan);

  if (alokasi === 0) {
    return `Belum ada alokasi dana BOP untuk tahun ${tahun}, jadi realisasi belum bisa dibandingkan dengan pagu.`;
  }
  if (total > alokasi) {
    const rp = (n) => `Rp ${Math.round(n).toLocaleString('id-ID')}`;
    return `Belanja tahun ${tahun} menjadi ${rp(total)}, melampaui pagu ${rp(alokasi)} sebesar ${rp(total - alokasi)}. Transaksi tetap dicatat.`;
  }
  return null;
}

async function createTransaction(req, res) {
  try {
    const { tipe, jumlah, deskripsi, kategori_id, tanggal } = req.body;

    // Perbandingan eksplisit: `!jumlah` akan menganggap angka 0 sebagai kosong.
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

    const namaKategori = cek.kategori ? cek.kategori.nama_kategori : 'Umum';
    const tgl = tanggal || new Date().toISOString().split('T')[0];

    const result = await pool.query(
      `INSERT INTO bop_finances (tipe, jumlah, deskripsi, kategori, kategori_id, tanggal, created_by, rt_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [tipe, jumlah, deskripsi, namaKategori, kategori_id || null, tgl, req.user.id, rtUntukSimpan(req)]
    );

    const peringatan = tipe === 'pengeluaran'
      ? await cekPagu(req, new Date(tgl).getFullYear(), 0)
      : null;

    await logActivity(
      req,
      'CREATE',
      `Mencatat ${tipe} Dana BOP ${rupiah(jumlah)} — ${namaKategori}: ${deskripsi}` +
        (peringatan ? ' [melampaui pagu]' : '')
    );
    return res.status(201).json({
      success: true,
      message: 'Transaksi BOP berhasil dicatat.',
      data: result.rows[0],
      ...(peringatan ? { peringatan } : {}),
    });
  } catch (err) {
    console.error('Create BOP Transaction Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateTransaction(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'bop_finances', id)) return;
    const { tipe, jumlah, deskripsi, kategori_id, tanggal } = req.body;

    const lama = await pool.query('SELECT * FROM bop_finances WHERE id = $1', [id]);
    if (lama.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Transaksi BOP tidak ditemukan.' });
    }

    if (tipe && !['pemasukan', 'pengeluaran'].includes(tipe)) {
      return res.status(400).json({ success: false, message: 'tipe harus "pemasukan" atau "pengeluaran".' });
    }
    if (jumlah !== undefined && Number(jumlah) <= 0) {
      return res.status(400).json({ success: false, message: 'Jumlah harus lebih dari 0.' });
    }

    let namaKategori = null;
    if (kategori_id) {
      const cek = await validasiKategori(kategori_id, tipe || lama.rows[0].tipe);
      if (!cek.ok) return res.status(400).json({ success: false, message: cek.pesan });
      namaKategori = cek.kategori ? cek.kategori.nama_kategori : null;
    }

    const result = await pool.query(
      `UPDATE bop_finances SET
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
    const peringatan = baru.tipe === 'pengeluaran'
      ? await cekPagu(req, new Date(baru.tanggal).getFullYear(), 0)
      : null;

    await logActivity(
      req,
      'UPDATE',
      `Mengubah transaksi Dana BOP ${rupiah(baru.jumlah)} — ${baru.kategori}: ${baru.deskripsi}`
    );
    return res.status(200).json({
      success: true,
      message: 'Transaksi BOP berhasil diperbarui.',
      data: baru,
      ...(peringatan ? { peringatan } : {}),
    });
  } catch (err) {
    console.error('Update BOP Transaction Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteTransaction(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'bop_finances', id)) return;
    const result = await pool.query(
      'DELETE FROM bop_finances WHERE id = $1 RETURNING id, deskripsi, jumlah, tipe',
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Transaksi BOP tidak ditemukan.' });
    }
    const hapus = result.rows[0];
    await logActivity(
      req,
      'DELETE',
      `Menghapus ${hapus.tipe} Dana BOP ${rupiah(hapus.jumlah)} — ${hapus.deskripsi || '-'}`
    );
    return res.status(200).json({ success: true, message: 'Transaksi BOP berhasil dihapus.', data: hapus });
  } catch (err) {
    console.error('Delete BOP Transaction Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

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
    created_by_nama: t.created_by_nama || '-',
  };
}

async function exportBop(req, res) {
  try {
    const format = (req.query.format || 'excel').toLowerCase();
    const { where, params } = buildFilter(req);
    const result = await pool.query(buildQuery(where), params);
    const rows = result.rows;

    const totalMasuk = rows.filter((r) => r.tipe === 'pemasukan').reduce((s, r) => s + Number(r.jumlah), 0);
    const totalKeluar = rows.filter((r) => r.tipe === 'pengeluaran').reduce((s, r) => s + Number(r.jumlah), 0);

    // Ringkasan pagu ikut dicetak karena inilah yang dibutuhkan untuk
    // pertanggungjawaban dana BOP.
    const tahun = parseInt(req.query.tahun, 10) || new Date().getFullYear();
    const pagu = await pool.query(
      'SELECT COALESCE(SUM(nominal), 0)::float8 AS n FROM alokasi_bop WHERE tahun = $1',
      [tahun]
    );
    const alokasi = pagu.rows[0].n;
    const rp = (n) => `Rp ${Math.round(n).toLocaleString('id-ID')}`;

    if (format === 'pdf') {
      const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', 'attachment; filename=Laporan_Dana_BOP.pdf');
      doc.pipe(res);

      doc.fontSize(18).text('Laporan Dana BOP', { align: 'center' });
      doc.fontSize(10).text(
        `Pagu ${tahun}: ${rp(alokasi)}  |  Realisasi: ${rp(totalKeluar)}  |  ` +
        `Sisa Pagu: ${rp(alokasi - totalKeluar)}  |  Saldo Kas: ${rp(totalMasuk - totalKeluar)}`,
        { align: 'center' }
      );
      doc.moveDown();

      await doc.table({
        title: 'Riwayat Transaksi BOP',
        headers: KOLOM.map((k) => k.header),
        rows: rows.map((t, i) => {
          const r = toRow(t, i);
          return KOLOM.map((k) => {
            const v = r[k.key];
            return ['pemasukan', 'pengeluaran', 'saldo_berjalan'].includes(k.key)
              ? (v === 0 && k.key !== 'saldo_berjalan' ? '-' : rp(v))
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
    const worksheet = workbook.addWorksheet('Dana BOP');
    worksheet.columns = KOLOM;
    worksheet.getRow(1).font = { bold: true };

    rows.forEach((t, i) => {
      const row = worksheet.addRow(toRow(t, i));
      ['pemasukan', 'pengeluaran', 'saldo_berjalan'].forEach((k) => {
        row.getCell(k).numFmt = '#,##0';
      });
    });

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

    worksheet.addRow({});
    const barisPagu = worksheet.addRow({
      deskripsi: `PAGU ${tahun}`,
      pengeluaran: alokasi,
      saldo_berjalan: alokasi - totalKeluar,
    });
    barisPagu.font = { bold: true, italic: true };
    worksheet.addRow({ deskripsi: 'Kolom PENGELUARAN berisi pagu, kolom SALDO berisi sisa pagu.' });

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=Laporan_Dana_BOP.xlsx');
    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error('Export BOP Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export.' });
    }
  }
}

module.exports = {
  getTransactions,
  getSummary,
  getBulanan,
  createTransaction,
  updateTransaction,
  deleteTransaction,
  exportBop,
};
