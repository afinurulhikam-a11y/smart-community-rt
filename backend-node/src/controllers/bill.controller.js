const { pool } = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const { generatePaymentPDF } = require('../utils/pdf-generator');
const { logActivity, rupiah } = require('../services/log.service');

const STATUS_BELUM = 'unpaid';
const STATUS_LUNAS = 'lunas';

/**
 * Tata letak kolom export. Excel dan PDF sama-sama membacanya, supaya keduanya
 * tidak bisa lepas sinkron — pola yang sama dipakai di warga.controller.js.
 */
const KOLOM = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'NO KK', key: 'no_kk', width: 20 },
  { header: 'KEPALA KELUARGA', key: 'kepala_keluarga', width: 28 },
  { header: 'ALAMAT', key: 'alamat', width: 30 },
  { header: 'JENIS IURAN', key: 'jenis_iuran', width: 24 },
  { header: 'PERIODE', key: 'bulan', width: 12 },
  { header: 'NOMINAL', key: 'nominal', width: 15 },
  { header: 'STATUS', key: 'status', width: 14 },
  { header: 'TGL BAYAR', key: 'tgl_bayar', width: 15 },
  { header: 'METODE', key: 'metode_bayar', width: 14 },
  { header: 'NO INVOICE', key: 'invoice_number', width: 26 },
];

/**
 * Tagihan melekat ke kartu keluarga, bukan ke perorangan. LATERAL dipakai agar
 * hanya pembayaran terakhir tiap tagihan yang ikut, tanpa menggandakan baris.
 */
const BASE_SELECT = `
  SELECT b.*,
         k.no_kk, k.kepala_keluarga, k.alamat, k.rt, k.rw,
         ji.nama_iuran, ji.periode,
         bp.paid_at, bp.metode_bayar, bp.invoice_number,
         kh.no_hp,
         -- Nama kepala keluarga bisa berupa nama anggota pertama yang dipakai
         -- sementara. Bendera ini membedakannya dari kepala keluarga sungguhan.
         EXISTS (
           SELECT 1 FROM anggota_keluarga ak2
           WHERE ak2.keluarga_id = k.id AND ak2.status_keluarga = 'Kepala Keluarga'
         ) AS kepala_terkonfirmasi
  FROM bills b
  JOIN keluarga k ON b.keluarga_id = k.id
  LEFT JOIN jenis_iuran ji ON b.jenis_iuran_id = ji.id
  LEFT JOIN LATERAL (
    SELECT paid_at, metode_bayar, invoice_number
    FROM bill_payments WHERE bill_id = b.id
    ORDER BY paid_at DESC LIMIT 1
  ) bp ON true
  -- Nomor HP kepala keluarga, dipakai tombol penagihan lewat WhatsApp.
  -- Diambil dari anggota_keluarga lebih dulu, lalu jatuh ke akun users-nya:
  -- form Tambah Warga menyimpan nomor ke users, sedangkan kolom no_hp pada
  -- anggota_keluarga baru ada sejak migrasi v5 sehingga data lama kosong.
  LEFT JOIN LATERAL (
    SELECT COALESCE(
             NULLIF(NULLIF(TRIM(ak.no_hp), ''), '-'),
             NULLIF(NULLIF(TRIM(u.no_hp), ''), '-')
           ) AS no_hp
    FROM anggota_keluarga ak
    LEFT JOIN users u ON u.nik = ak.nik
    WHERE ak.keluarga_id = k.id AND ak.status_keluarga = 'Kepala Keluarga'
    ORDER BY ak.id LIMIT 1
  ) kh ON true
`;

const pad = (n) => n.toString().padStart(2, '0');

function formatTanggal(nilai) {
  if (!nilai) return '';
  const d = nilai instanceof Date ? nilai : new Date(nilai);
  if (isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/**
 * Bangun klausa WHERE bersama untuk daftar, statistik, dan export, agar angka
 * di ketiganya selalu berasal dari penyaringan yang sama.
 */
function buildFilter(req, mulaiDari = 0) {
  const { bulan, tahun, status, jenis_iuran_id, search, keluarga_id } = req.query;
  const kondisi = [];
  const params = [];
  const p = () => `$${mulaiDari + params.length}`;

  // Warga hanya boleh melihat tagihan kartu keluarganya sendiri.
  if (req.user.role === 'warga') {
    params.push(req.user.id);
    kondisi.push(`k.no_kk = (SELECT no_kk FROM users WHERE id = ${p()})`);
  } else if (keluarga_id) {
    params.push(keluarga_id);
    kondisi.push(`b.keluarga_id = ${p()}`);
  }

  if (bulan) { params.push(bulan); kondisi.push(`b.bulan = ${p()}`); }
  if (tahun) { params.push(`${tahun}-%`); kondisi.push(`b.bulan LIKE ${p()}`); }
  if (status) { params.push(status); kondisi.push(`b.status = ${p()}`); }
  if (jenis_iuran_id) { params.push(jenis_iuran_id); kondisi.push(`b.jenis_iuran_id = ${p()}`); }
  if (search) {
    params.push(`%${search}%`);
    kondisi.push(`(k.kepala_keluarga ILIKE ${p()} OR k.no_kk ILIKE ${p()} OR k.alamat ILIKE ${p()} OR ji.nama_iuran ILIKE ${p()})`);
  }

  const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';
  return { where, params };
}

async function getBills(req, res) {
  try {
    const { where, params } = buildFilter(req);
    const result = await pool.query(
      `${BASE_SELECT} ${where} ORDER BY b.bulan DESC, k.kepala_keluarga ASC`,
      params
    );
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetBills Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getBillStats(req, res) {
  try {
    const { where, params } = buildFilter(req);
    const result = await pool.query(`
      SELECT
        COUNT(*)::int AS total_tagihan,
        COUNT(*) FILTER (WHERE b.status = '${STATUS_LUNAS}')::int AS jumlah_lunas,
        COUNT(*) FILTER (WHERE b.status <> '${STATUS_LUNAS}')::int AS jumlah_tunggakan,
        COALESCE(SUM(b.nominal) FILTER (WHERE b.status = '${STATUS_LUNAS}'), 0)::float8 AS nominal_terkumpul,
        COALESCE(SUM(b.nominal) FILTER (WHERE b.status <> '${STATUS_LUNAS}'), 0)::float8 AS nominal_tertunggak,
        COALESCE(SUM(b.nominal), 0)::float8 AS nominal_total,
        COUNT(DISTINCT b.keluarga_id)::int AS jumlah_kk
      FROM bills b
      JOIN keluarga k ON b.keluarga_id = k.id
      LEFT JOIN jenis_iuran ji ON b.jenis_iuran_id = ji.id
      ${where}
    `, params);

    const s = result.rows[0];
    const persen = s.total_tagihan > 0
      ? Math.round((s.jumlah_lunas / s.total_tagihan) * 1000) / 10
      : 0;

    return res.status(200).json({ success: true, data: { ...s, persentase_lunas: persen } });
  } catch (err) {
    console.error('GetBillStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Ambil jenis iuran sekaligus memvalidasinya. */
async function ambilJenis(client, jenisIuranId) {
  const r = await client.query('SELECT * FROM jenis_iuran WHERE id = $1', [jenisIuranId]);
  return r.rows[0] || null;
}

async function createBill(req, res) {
  try {
    const { keluarga_id, jenis_iuran_id, bulan, nominal, keterangan, jatuh_tempo } = req.body;

    if (!keluarga_id || !jenis_iuran_id || !bulan) {
      return res.status(400).json({ success: false, message: 'keluarga_id, jenis_iuran_id, dan bulan wajib diisi.' });
    }
    if (!/^\d{4}-\d{2}$/.test(bulan)) {
      return res.status(400).json({ success: false, message: 'Format periode harus YYYY-MM (contoh: 2026-07).' });
    }

    const kk = await pool.query('SELECT id, kepala_keluarga FROM keluarga WHERE id = $1', [keluarga_id]);
    if (kk.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Kartu keluarga tidak ditemukan.' });
    }

    const jenis = await ambilJenis(pool, jenis_iuran_id);
    if (!jenis) return res.status(404).json({ success: false, message: 'Jenis iuran tidak ditemukan.' });

    // Nominal kosong → pakai nominal default milik jenis iuran.
    const nominalFinal = nominal !== undefined && nominal !== null && nominal !== ''
      ? nominal
      : jenis.nominal_default;

    const duplikat = await pool.query(
      'SELECT id FROM bills WHERE keluarga_id = $1 AND jenis_iuran_id = $2 AND bulan = $3',
      [keluarga_id, jenis_iuran_id, bulan]
    );
    if (duplikat.rows.length > 0) {
      return res.status(409).json({
        success: false,
        message: `Tagihan ${jenis.nama_iuran} periode ${bulan} untuk KK ini sudah ada.`,
      });
    }

    const result = await pool.query(
      `INSERT INTO bills (keluarga_id, jenis_iuran_id, jenis_tagihan, bulan, nominal, keterangan, jatuh_tempo, status, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [keluarga_id, jenis_iuran_id, jenis.nama_iuran, bulan, nominalFinal, keterangan || null, jatuh_tempo || null, STATUS_BELUM, req.user.id]
    );

    const tagihanBaru = result.rows[0];
    await logActivity(
      req,
      'CREATE',
      `Membuat tagihan ${tagihanBaru.jenis_tagihan} periode ${tagihanBaru.bulan} ` +
        `sebesar ${rupiah(tagihanBaru.nominal)}`
    );
    return res.status(201).json({ success: true, message: 'Tagihan berhasil dibuat.', data: tagihanBaru });
  } catch (err) {
    console.error('CreateBill Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Membuat satu tagihan untuk SETIAP kartu keluarga pada satu jenis + periode.
 *
 * Satu perintah INSERT ... SELECT, bukan perulangan query per baris seperti
 * createBillBatch yang lama. ON CONFLICT bersandar pada indeks unik parsial
 * dari migrasi v6, sehingga aman dijalankan berulang.
 */
async function generateBills(req, res) {
  const client = await pool.connect();
  try {
    const { jenis_iuran_id, bulan, nominal, keterangan, jatuh_tempo } = req.body;

    if (!jenis_iuran_id || !bulan) {
      return res.status(400).json({ success: false, message: 'jenis_iuran_id dan bulan wajib diisi.' });
    }
    if (!/^\d{4}-\d{2}$/.test(bulan)) {
      return res.status(400).json({ success: false, message: 'Format periode harus YYYY-MM (contoh: 2026-07).' });
    }

    const jenis = await ambilJenis(client, jenis_iuran_id);
    if (!jenis) return res.status(404).json({ success: false, message: 'Jenis iuran tidak ditemukan.' });

    const nominalFinal = nominal !== undefined && nominal !== null && nominal !== ''
      ? nominal
      : jenis.nominal_default;
    if (!nominalFinal || Number(nominalFinal) <= 0) {
      return res.status(400).json({ success: false, message: 'Nominal harus lebih dari 0. Isi nominal atau set nominal default pada jenis iuran.' });
    }

    await client.query('BEGIN');

    const totalKk = await client.query('SELECT COUNT(*)::int AS c FROM keluarga');
    const dibuat = await client.query(
      `INSERT INTO bills (keluarga_id, jenis_iuran_id, jenis_tagihan, bulan, nominal, keterangan, jatuh_tempo, status, created_by)
       SELECT k.id, $1, $2, $3, $4, $5, $6, $7, $8
       FROM keluarga k
       ON CONFLICT (keluarga_id, jenis_iuran_id, bulan) WHERE keluarga_id IS NOT NULL
       DO NOTHING
       RETURNING id`,
      [jenis_iuran_id, jenis.nama_iuran, bulan, nominalFinal, keterangan || null, jatuh_tempo || null, STATUS_BELUM, req.user.id]
    );

    await client.query('COMMIT');

    const jumlahDibuat = dibuat.rows.length;
    const jumlahDilewati = totalKk.rows[0].c - jumlahDibuat;

    await logActivity(
      req,
      'CREATE',
      `Menerbitkan tagihan ${jenis.nama_iuran} periode ${bulan}: ` +
        `${jumlahDibuat} dibuat, ${jumlahDilewati} dilewati`
    );

    // Panggil WhatsApp Service secara otomatis untuk memberitahu warga (Async)
    const { sendBillWA } = require('../services/whatsapp.service');
    (async () => {
      if (jumlahDibuat > 0) {
        const wargaList = await pool.query(
          `SELECT u.nama, u.no_hp FROM users u JOIN keluarga k ON u.no_kk = k.no_kk WHERE u.no_hp IS NOT NULL AND u.no_hp <> ''`
        );
        for (const w of wargaList.rows) {
          await sendBillWA({
            userNama: w.nama,
            noHp: w.no_hp,
            namaIuran: jenis.nama_iuran,
            nominal: nominalFinal,
            bulan: bulan,
          });
        }
      }
    })().catch((e) => console.log('ℹ️ Catatan WA Tagihan:', e.message));

    return res.status(201).json({
      success: true,
      message: `Tagihan ${jenis.nama_iuran} periode ${bulan}: ${jumlahDibuat} dibuat, ${jumlahDilewati} dilewati (sudah ada).`,
      data: { dibuat: jumlahDibuat, dilewati: jumlahDilewati, total_kk: totalKk.rows[0].c },
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('GenerateBills Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal membuat tagihan: ' + err.message });
  } finally {
    client.release();
  }
}

/**
 * Catat pembayaran iuran sebagai pemasukan di buku Kas RT.
 *
 * Dipanggil di dalam transaksi yang sama dengan INSERT bill_payments, sehingga
 * mustahil pembayaran tercatat tanpa baris kas atau sebaliknya. ON CONFLICT
 * bersandar pada indeks unik finances_ref_uniq dari migrasi v8, jadi satu
 * pembayaran tidak akan pernah tercatat dua kali.
 */
async function catatKeKasRt(client, { payment, bill, userId }) {
  const detail = await client.query(
    `SELECT COALESCE(ji.nama_iuran, b.jenis_tagihan) AS nama_iuran,
            k.kepala_keluarga, k.no_kk
     FROM bills b
     JOIN keluarga k ON b.keluarga_id = k.id
     LEFT JOIN jenis_iuran ji ON b.jenis_iuran_id = ji.id
     WHERE b.id = $1`,
    [bill.id]
  );
  const d = detail.rows[0] || {};

  // Pakai kategori kas bertipe IN yang menyangkut iuran bila ada; kalau tidak,
  // kolom kategori tetap terisi teks agar laporan tidak kosong.
  const kategori = await client.query(
    `SELECT id, nama_kategori FROM kategori_kas
     WHERE tipe = 'IN' AND nama_kategori ILIKE '%iuran%'
     ORDER BY id LIMIT 1`
  );
  const kategoriId = kategori.rows[0]?.id || null;
  const namaKategori = kategori.rows[0]?.nama_kategori || 'Iuran Warga';

  let bulanText = bill.bulan || '';
  if (bulanText.includes('-')) {
    const [thn, bln] = bulanText.split('-');
    const namaBulanMap = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    const idx = parseInt(bln, 10) - 1;
    if (idx >= 0 && idx < 12) {
      bulanText = `${namaBulanMap[idx]} ${thn}`;
    }
  }
  const deskripsi = `${d.nama_iuran || 'Iuran'} (Periode ${bulanText}) — ${d.kepala_keluarga || d.no_kk || 'Warga'}`;

  await client.query(
    `INSERT INTO finances (tipe, kategori, kategori_id, jumlah, deskripsi, tanggal, created_by, sumber, ref_id)
     VALUES ('pemasukan', $1, $2, $3, $4, CURRENT_DATE, $5, 'iuran', $6)
     ON CONFLICT (ref_id) WHERE ref_id IS NOT NULL DO NOTHING`,
    [namaKategori, kategoriId, bill.nominal, deskripsi, userId, payment.id]
  );
}

/** Pastikan warga hanya menyentuh tagihan kartu keluarganya sendiri. */
async function bolehMengaksesTagihan(req, bill) {
  if (req.user.role !== 'warga') return true;
  const r = await pool.query(
    `SELECT 1 FROM users u JOIN keluarga k ON k.no_kk = u.no_kk
     WHERE u.id = $1 AND k.id = $2`,
    [req.user.id, bill.keluarga_id]
  );
  return r.rows.length > 0;
}

async function payBill(req, res) {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const { metode_bayar } = req.body;

    const billResult = await pool.query('SELECT * FROM bills WHERE id = $1', [id]);
    if (billResult.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Tagihan tidak ditemukan.' });
    }
    const bill = billResult.rows[0];

    if (!(await bolehMengaksesTagihan(req, bill))) {
      return res.status(403).json({ success: false, message: 'Anda hanya bisa membayar tagihan keluarga sendiri.' });
    }
    if (bill.status === STATUS_LUNAS) {
      return res.status(400).json({ success: false, message: 'Tagihan ini sudah lunas.' });
    }

    const invoiceNumber = `INV-${Date.now()}-${uuidv4().split('-')[0].toUpperCase()}`;
    await client.query('BEGIN');
    const paymentResult = await client.query(
      `INSERT INTO bill_payments (bill_id, user_id, jumlah_bayar, metode_bayar, invoice_number)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [id, req.user.id, bill.nominal, metode_bayar || 'tunai', invoiceNumber]
    );
    await client.query(
      "UPDATE bills SET status = $1, user_id = $2, updated_at = NOW() WHERE id = $3",
      [STATUS_LUNAS, req.user.id, id]
    );
    await catatKeKasRt(client, { payment: paymentResult.rows[0], bill, userId: req.user.id });
    await client.query('COMMIT');

    // Dicatat SETELAH COMMIT: jejaknya harus mewakili pembayaran yang benar
    // sungguh tersimpan, bukan yang sempat dibatalkan rollback.
    await logActivity(
      req,
      'PEMBAYARAN',
      `Menerima pembayaran iuran ${bill.bulan} ${rupiah(bill.nominal)} ` +
        `(${metode_bayar || 'tunai'}) — invoice ${invoiceNumber}`
    );
    return res.status(200).json({
      success: true,
      message: 'Pembayaran berhasil.',
      data: { payment: paymentResult.rows[0], invoice_number: invoiceNumber },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('PayBill Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

/** Pelunasan beberapa tagihan sekaligus, satu transaksi. */
async function payBillsBulk(req, res) {
  const client = await pool.connect();
  try {
    const { bill_ids, metode_bayar } = req.body;
    if (!Array.isArray(bill_ids) || bill_ids.length === 0) {
      return res.status(400).json({ success: false, message: 'bill_ids wajib berupa daftar dan tidak boleh kosong.' });
    }

    await client.query('BEGIN');

    // Kunci baris agar dua petugas tidak melunasi tagihan yang sama bersamaan.
    const tagihan = await client.query(
      'SELECT * FROM bills WHERE id = ANY($1::uuid[]) FOR UPDATE',
      [bill_ids]
    );

    let berhasil = 0;
    let dilewati = 0;
    const invoices = [];

    for (const bill of tagihan.rows) {
      if (bill.status === STATUS_LUNAS) { dilewati++; continue; }

      const invoiceNumber = `INV-${Date.now()}-${uuidv4().split('-')[0].toUpperCase()}`;
      const bayar = await client.query(
        `INSERT INTO bill_payments (bill_id, user_id, jumlah_bayar, metode_bayar, invoice_number)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [bill.id, req.user.id, bill.nominal, metode_bayar || 'tunai', invoiceNumber]
      );
      await client.query(
        'UPDATE bills SET status = $1, user_id = $2, updated_at = NOW() WHERE id = $3',
        [STATUS_LUNAS, req.user.id, bill.id]
      );
      await catatKeKasRt(client, { payment: bayar.rows[0], bill, userId: req.user.id });
      invoices.push(invoiceNumber);
      berhasil++;
    }

    await client.query('COMMIT');

    const tidakDitemukan = bill_ids.length - tagihan.rows.length;
    if (berhasil > 0) {
      await logActivity(
        req,
        'PEMBAYARAN',
        `Menerima pembayaran ${berhasil} tagihan iuran sekaligus` +
          (dilewati > 0 ? ` (${dilewati} dilewati karena sudah lunas)` : '')
      );
    }
    return res.status(200).json({
      success: true,
      message: `${berhasil} tagihan dilunasi, ${dilewati} dilewati (sudah lunas)${tidakDitemukan > 0 ? `, ${tidakDitemukan} tidak ditemukan` : ''}.`,
      data: { berhasil, dilewati, tidak_ditemukan: tidakDitemukan, invoices },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('PayBillsBulk Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

async function deleteBill(req, res) {
  try {
    const { id } = req.params;
    const bill = await pool.query(
      'SELECT status, bulan, nominal, jenis_tagihan FROM bills WHERE id = $1',
      [id]
    );
    if (bill.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Tagihan tidak ditemukan.' });
    }
    // Menghapus tagihan lunas akan memutus jejak pembayaran yang sudah tercatat.
    if (bill.rows[0].status === STATUS_LUNAS) {
      return res.status(409).json({ success: false, message: 'Tagihan yang sudah lunas tidak bisa dihapus karena sudah punya catatan pembayaran.' });
    }
    await pool.query('DELETE FROM bills WHERE id = $1', [id]);
    const dihapus = bill.rows[0];
    await logActivity(
      req,
      'DELETE',
      `Menghapus tagihan ${dihapus.jenis_tagihan} periode ${dihapus.bulan} ` +
        `sebesar ${rupiah(dihapus.nominal)}`
    );
    return res.status(200).json({ success: true, message: 'Tagihan berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteBill Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Ubah satu baris database menjadi baris export sesuai urutan KOLOM. */
function toRow(b, index) {
  return {
    no: index + 1,
    no_kk: b.no_kk || '-',
    kepala_keluarga: b.kepala_keluarga || '-',
    alamat: b.alamat || '-',
    jenis_iuran: b.nama_iuran || b.jenis_tagihan || '-',
    bulan: b.bulan || '-',
    nominal: Number(b.nominal) || 0,
    status: b.status === STATUS_LUNAS ? 'Lunas' : 'Belum Bayar',
    tgl_bayar: formatTanggal(b.paid_at) || '-',
    metode_bayar: b.metode_bayar || '-',
    invoice_number: b.invoice_number || '-',
  };
}

async function exportBills(req, res) {
  try {
    const format = (req.query.format || 'excel').toLowerCase();
    const { where, params } = buildFilter(req);
    const result = await pool.query(
      `${BASE_SELECT} ${where} ORDER BY b.bulan DESC, k.kepala_keluarga ASC`,
      params
    );
    const rows = result.rows;

    if (format === 'pdf') {
      const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', 'attachment; filename=Data_Iuran.pdf');
      doc.pipe(res);

      doc.fontSize(18).text('Data Iuran Warga RT', { align: 'center' });
      doc.moveDown();

      await doc.table({
        title: 'Rekapitulasi Iuran',
        headers: KOLOM.map((k) => k.header),
        rows: rows.map((b, i) => {
          const r = toRow(b, i);
          return KOLOM.map((k) => (k.key === 'nominal' ? `Rp ${r.nominal.toLocaleString('id-ID')}` : String(r[k.key])));
        }),
      }, {
        prepareHeader: () => doc.font('Helvetica-Bold').fontSize(8),
        prepareRow: () => doc.font('Helvetica').fontSize(7),
      });

      doc.end();
      return;
    }

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Data Iuran');
    worksheet.columns = KOLOM;
    worksheet.getRow(1).font = { bold: true };

    rows.forEach((b, i) => {
      const row = worksheet.addRow(toRow(b, i));
      row.getCell('nominal').numFmt = '#,##0';
    });

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=Data_Iuran.xlsx');
    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error('ExportBills Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export.' });
    }
  }
}

async function downloadReceipt(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT bp.*, b.bulan, b.nominal, b.keluarga_id,
              COALESCE(ji.nama_iuran, b.jenis_tagihan) AS jenis_tagihan,
              k.kepala_keluarga AS nama_warga, k.alamat, k.no_kk
       FROM bill_payments bp
       JOIN bills b ON bp.bill_id = b.id
       JOIN keluarga k ON b.keluarga_id = k.id
       LEFT JOIN jenis_iuran ji ON b.jenis_iuran_id = ji.id
       WHERE bp.bill_id = $1 ORDER BY bp.paid_at DESC LIMIT 1`,
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Data pembayaran tidak ditemukan.' });
    }
    const payment = result.rows[0];

    if (!(await bolehMengaksesTagihan(req, payment))) {
      return res.status(403).json({ success: false, message: 'Anda hanya bisa mengunduh kwitansi keluarga sendiri.' });
    }

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=kwitansi-${payment.invoice_number}.pdf`);
    generatePaymentPDF(payment, res);
  } catch (err) {
    console.error('DownloadReceipt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getBills,
  getBillStats,
  createBill,
  generateBills,
  payBill,
  payBillsBulk,
  deleteBill,
  exportBills,
  downloadReceipt,
  // Dipakai payment.controller.js agar pembayaran Midtrans memposting ke Kas RT
  // lewat jalur yang SAMA PERSIS dengan pembayaran tunai. Menyalin logikanya ke
  // sana akan menciptakan dua cara memposting kas yang bisa berbeda diam-diam.
  catatKeKasRt,
  STATUS_BELUM,
  STATUS_LUNAS,
};
