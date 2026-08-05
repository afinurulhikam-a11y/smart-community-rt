const { pool } = require('../config/database');
const { logActivity, rupiah, ringkas, TIPE } = require('../services/log.service');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');

const STATUS_DIPINJAM = 'Dipinjam';
const STATUS_KEMBALI = 'Dikembalikan';

/**
 * Status "Terlambat" DITURUNKAN, tidak disimpan.
 *
 * Peminjaman menjadi terlambat karena berlalunya waktu, bukan karena suatu
 * kejadian. Menyimpannya sebagai status akan menuntut penjadwal harian yang
 * membalik baris; menghitungnya saat dibaca selalu benar tanpa proses apa pun.
 */
const STATUS_EFEKTIF = `
  CASE
    WHEN b.status = '${STATUS_DIPINJAM}'
     AND b.tanggal_rencana_kembali IS NOT NULL
     AND b.tanggal_rencana_kembali < CURRENT_DATE THEN 'Terlambat'
    ELSE b.status
  END
`;

const KOLOM_BARANG = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'NAMA BARANG', key: 'nama_barang', width: 30 },
  { header: 'KATEGORI', key: 'kategori', width: 18 },
  { header: 'TOTAL', key: 'jumlah_total', width: 10 },
  { header: 'DIPINJAM', key: 'sedang_dipinjam', width: 10 },
  { header: 'TERSEDIA', key: 'tersedia', width: 10 },
  { header: 'KONDISI', key: 'kondisi', width: 14 },
  { header: 'LOKASI', key: 'lokasi', width: 22 },
  { header: 'NILAI SATUAN', key: 'nilai_barang', width: 16 },
  { header: 'NILAI TOTAL', key: 'nilai_total', width: 16 },
  { header: 'KETERANGAN', key: 'keterangan', width: 30 },
];

const KOLOM_PINJAM = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'NAMA BARANG', key: 'nama_barang', width: 28 },
  { header: 'PEMINJAM', key: 'nama_peminjam', width: 26 },
  { header: 'JUMLAH', key: 'jumlah', width: 10 },
  { header: 'TGL PINJAM', key: 'tanggal_pinjam', width: 14 },
  { header: 'RENCANA KEMBALI', key: 'tanggal_rencana_kembali', width: 18 },
  { header: 'TGL KEMBALI', key: 'tanggal_kembali', width: 14 },
  { header: 'STATUS', key: 'status_efektif', width: 14 },
  { header: 'TERLAMBAT (HARI)', key: 'hari_terlambat', width: 18 },
  { header: 'KETERANGAN', key: 'keterangan', width: 28 },
];

const pad = (n) => n.toString().padStart(2, '0');

function formatTanggal(nilai) {
  if (!nilai) return '';
  const d = nilai instanceof Date ? nilai : new Date(nilai);
  if (isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// ======================== INVENTORY ========================

/**
 * Jumlah tersedia DIHITUNG, tidak disimpan.
 *
 * Kolom inventory.jumlah berarti total barang yang dimiliki dan tidak pernah
 * dikurangi saat dipinjam — kalau dikurangi, RT kehilangan catatan berapa
 * barang yang sebenarnya mereka punya, dan stok bisa hilang permanen bila
 * baris peminjaman terhapus.
 */
const DIPINJAM_SUBQUERY = `
  COALESCE((
    SELECT SUM(b.jumlah) FROM borrowings b
    WHERE b.inventory_id = i.id AND b.status = '${STATUS_DIPINJAM}'
  ), 0)::int
`;

const SELECT_BARANG = `
  SELECT i.*,
         u.nama AS created_by_nama,
         i.jumlah AS jumlah_total,
         ${DIPINJAM_SUBQUERY} AS sedang_dipinjam,
         (i.jumlah - ${DIPINJAM_SUBQUERY}) AS tersedia,
         (i.jumlah * COALESCE(i.nilai_barang, 0))::float8 AS nilai_total
  FROM inventory i
  LEFT JOIN users u ON i.created_by = u.id
`;

function filterBarang(req) {
  const { kategori, kondisi, search } = req.query;
  const kondisiArr = [];
  const params = [];
  const p = () => `$${params.length}`;

  if (kategori) { params.push(kategori); kondisiArr.push(`i.kategori = ${p()}`); }
  if (kondisi) { params.push(kondisi); kondisiArr.push(`i.kondisi = ${p()}`); }
  if (search) {
    params.push(`%${search}%`);
    kondisiArr.push(`(i.nama_barang ILIKE ${p()} OR i.lokasi ILIKE ${p()} OR i.kategori ILIKE ${p()})`);
  }

  return { where: kondisiArr.length ? `WHERE ${kondisiArr.join(' AND ')}` : '', params };
}

async function getInventory(req, res) {
  try {
    const { where, params } = filterBarang(req);
    const result = await pool.query(
      `${SELECT_BARANG} ${where} ORDER BY i.nama_barang ASC`,
      params
    );
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetInventory Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getInventoryStats(req, res) {
  try {
    const { where, params } = filterBarang(req);
    const result = await pool.query(`
      SELECT
        COUNT(*)::int AS total_aset,
        COALESCE(SUM(i.jumlah), 0)::int AS total_unit,
        COUNT(*) FILTER (WHERE i.kondisi = 'Baik')::int AS kondisi_baik,
        COUNT(*) FILTER (WHERE i.kondisi <> 'Baik')::int AS perlu_perbaikan,
        COALESCE(SUM(i.jumlah * COALESCE(i.nilai_barang, 0)), 0)::float8 AS total_nilai,
        COALESCE(SUM(${DIPINJAM_SUBQUERY}), 0)::int AS unit_dipinjam
      FROM inventory i
      ${where}
    `, params);

    const s = result.rows[0];
    return res.status(200).json({
      success: true,
      data: { ...s, unit_tersedia: s.total_unit - s.unit_dipinjam },
    });
  } catch (err) {
    console.error('GetInventoryStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Detail satu barang beserta riwayat peminjamannya. */
async function getInventoryDetail(req, res) {
  try {
    const { id } = req.params;
    const barang = await pool.query(`${SELECT_BARANG} WHERE i.id = $1`, [id]);
    if (barang.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Barang tidak ditemukan.' });
    }

    const riwayat = await pool.query(`
      SELECT b.*,
             COALESCE(b.nama_peminjam, u.nama) AS nama_peminjam,
             ${STATUS_EFEKTIF} AS status_efektif
      FROM borrowings b
      LEFT JOIN users u ON b.user_id = u.id
      WHERE b.inventory_id = $1
      ORDER BY b.tanggal_pinjam DESC, b.id DESC
      LIMIT 50
    `, [id]);

    return res.status(200).json({
      success: true,
      data: { ...barang.rows[0], riwayat: riwayat.rows },
    });
  } catch (err) {
    console.error('GetInventoryDetail Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createInventory(req, res) {
  try {
    const { nama_barang, kategori, jumlah, kondisi, lokasi, keterangan,
      nilai_barang, tanggal_perolehan } = req.body;

    if (!nama_barang || !nama_barang.trim()) {
      return res.status(400).json({ success: false, message: 'Nama barang wajib diisi.' });
    }
    if (jumlah !== undefined && Number(jumlah) < 0) {
      return res.status(400).json({ success: false, message: 'Jumlah tidak boleh negatif.' });
    }

    const result = await pool.query(
      `INSERT INTO inventory (nama_barang, kategori, jumlah, kondisi, lokasi, keterangan,
                              nilai_barang, tanggal_perolehan, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [
        nama_barang.trim(), kategori || null, jumlah ?? 1, kondisi || 'Baik',
        lokasi || null, keterangan || null, nilai_barang || 0,
        tanggal_perolehan || null, req.user.id,
      ]
    );
    const b = result.rows[0];
    await logActivity(req, TIPE.CREATE, `Menambah barang inventaris "${ringkas(b.nama_barang)}" — ${b.jumlah} unit, nilai ${rupiah(b.nilai_barang)}, kondisi ${b.kondisi}`);

    return res.status(201).json({ success: true, message: 'Barang berhasil ditambahkan.', data: result.rows[0] });
  } catch (err) {
    console.error('CreateInventory Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateInventory(req, res) {
  try {
    const { id } = req.params;
    const { nama_barang, kategori, jumlah, kondisi, lokasi, keterangan,
      nilai_barang, tanggal_perolehan } = req.body;

    // Total tidak boleh dikurangi di bawah yang sedang dipinjam, karena itu
    // berarti mengaku memiliki lebih sedikit barang daripada yang ada di luar.
    if (jumlah !== undefined) {
      if (Number(jumlah) < 0) {
        return res.status(400).json({ success: false, message: 'Jumlah tidak boleh negatif.' });
      }
      const dipinjam = await pool.query(
        `SELECT COALESCE(SUM(jumlah), 0)::int AS n FROM borrowings
         WHERE inventory_id = $1 AND status = $2`,
        [id, STATUS_DIPINJAM]
      );
      if (Number(jumlah) < dipinjam.rows[0].n) {
        return res.status(409).json({
          success: false,
          message: `Total barang tidak bisa dikurangi menjadi ${jumlah} karena ${dipinjam.rows[0].n} unit sedang dipinjam.`,
        });
      }
    }

    const result = await pool.query(
      `UPDATE inventory SET
         nama_barang       = COALESCE($1, nama_barang),
         kategori          = COALESCE($2, kategori),
         jumlah            = COALESCE($3, jumlah),
         kondisi           = COALESCE($4, kondisi),
         lokasi            = COALESCE($5, lokasi),
         keterangan        = COALESCE($6, keterangan),
         nilai_barang      = COALESCE($7, nilai_barang),
         tanggal_perolehan = COALESCE($8, tanggal_perolehan),
         updated_at        = NOW()
       WHERE id = $9 RETURNING *`,
      [
        nama_barang?.trim() || null, kategori ?? null, jumlah ?? null, kondisi || null,
        lokasi ?? null, keterangan ?? null, nilai_barang ?? null,
        tanggal_perolehan || null, id,
      ]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Barang tidak ditemukan.' });
    }
    const b = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah barang inventaris "${ringkas(b.nama_barang)}" — kini ${b.jumlah} unit, kondisi ${b.kondisi}, nilai ${rupiah(b.nilai_barang)}`);

    return res.status(200).json({ success: true, message: 'Barang berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    console.error('UpdateInventory Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteInventory(req, res) {
  try {
    const { id } = req.params;

    // Penjagaan ini sebelumnya tidak ada sama sekali: barang bisa dihapus
    // walau sedang berada di tangan warga, dan borrowings ikut terhapus
    // karena ON DELETE CASCADE.
    const dipinjam = await pool.query(
      `SELECT COALESCE(SUM(jumlah), 0)::int AS n FROM borrowings
       WHERE inventory_id = $1 AND status = $2`,
      [id, STATUS_DIPINJAM]
    );
    if (dipinjam.rows[0].n > 0) {
      return res.status(409).json({
        success: false,
        message: `Barang ini tidak bisa dihapus karena ${dipinjam.rows[0].n} unit sedang dipinjam. Tunggu sampai dikembalikan.`,
      });
    }

    const result = await pool.query('DELETE FROM inventory WHERE id = $1 RETURNING id, nama_barang', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Barang tidak ditemukan.' });
    }
    const b = result.rows[0];
    await logActivity(req, TIPE.DELETE, `Menghapus barang inventaris "${ringkas(b.nama_barang)}" — ${b.jumlah ?? "-"} unit, nilai ${rupiah(b.nilai_barang || 0)}`);

    return res.status(200).json({ success: true, message: 'Barang berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeleteInventory Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== BORROWINGS ========================

const SELECT_PINJAM = `
  SELECT b.*,
         i.nama_barang, i.kategori,
         COALESCE(b.nama_peminjam, u.nama) AS nama_peminjam,
         pc.nama AS dicatat_oleh_nama,
         ${STATUS_EFEKTIF} AS status_efektif,
         CASE
           WHEN b.status = '${STATUS_DIPINJAM}' AND b.tanggal_rencana_kembali IS NOT NULL
             THEN GREATEST(0, CURRENT_DATE - b.tanggal_rencana_kembali)
           ELSE 0
         END::int AS hari_terlambat
  FROM borrowings b
  JOIN inventory i ON b.inventory_id = i.id
  LEFT JOIN users u ON b.user_id = u.id
  LEFT JOIN users pc ON b.dicatat_oleh = pc.id
`;

function filterPinjam(req) {
  const { status, inventory_id, search, dari, sampai } = req.query;
  const kondisi = [];
  const params = [];
  const p = () => `$${params.length}`;

  // Warga hanya boleh melihat peminjamannya sendiri — pola yang sama dengan
  // getLetters dan buildFilter pada tagihan.
  if (req.user.role === 'warga') {
    params.push(req.user.id);
    kondisi.push(`b.user_id = ${p()}`);
  }

  if (status) {
    // "Terlambat" bukan nilai tersimpan, jadi disaring lewat kondisi turunan.
    if (status === 'Terlambat') {
      kondisi.push(`(b.status = '${STATUS_DIPINJAM}' AND b.tanggal_rencana_kembali IS NOT NULL AND b.tanggal_rencana_kembali < CURRENT_DATE)`);
    } else {
      params.push(status);
      kondisi.push(`b.status = ${p()}`);
    }
  }
  if (inventory_id) { params.push(inventory_id); kondisi.push(`b.inventory_id = ${p()}`); }
  if (dari) { params.push(dari); kondisi.push(`b.tanggal_pinjam >= ${p()}`); }
  if (sampai) { params.push(sampai); kondisi.push(`b.tanggal_pinjam <= ${p()}`); }
  if (search) {
    params.push(`%${search}%`);
    kondisi.push(`(i.nama_barang ILIKE ${p()} OR COALESCE(b.nama_peminjam, u.nama) ILIKE ${p()})`);
  }

  return { where: kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '', params };
}

async function getBorrowings(req, res) {
  try {
    const { where, params } = filterPinjam(req);
    const result = await pool.query(
      `${SELECT_PINJAM} ${where} ORDER BY b.tanggal_pinjam DESC, b.id DESC`,
      params
    );
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetBorrowings Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getBorrowingStats(req, res) {
  try {
    // Ikut disaring seperti daftarnya, atau kartu statistik warga akan
    // bercerita tentang peminjaman tetangga yang tidak boleh ia lihat.
    const milikSendiri = req.user.role === 'warga';
    const result = await pool.query(`
      SELECT
        COUNT(*)::int AS total,
        COUNT(*) FILTER (WHERE b.status = '${STATUS_DIPINJAM}')::int AS dipinjam,
        COUNT(*) FILTER (WHERE b.status = '${STATUS_KEMBALI}')::int AS dikembalikan,
        COUNT(*) FILTER (
          WHERE b.status = '${STATUS_DIPINJAM}'
            AND b.tanggal_rencana_kembali IS NOT NULL
            AND b.tanggal_rencana_kembali < CURRENT_DATE
        )::int AS terlambat
      FROM borrowings b
      ${milikSendiri ? 'WHERE b.user_id = $1' : ''}
    `, milikSendiri ? [req.user.id] : []);
    return res.status(200).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('GetBorrowingStats Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Sisa stok yang benar-benar bisa dipinjam, dari angka turunan. */
async function hitungTersedia(client, inventoryId, kecualikanBorrowingId = null) {
  const r = await client.query(`
    SELECT i.jumlah - COALESCE((
      SELECT SUM(b.jumlah) FROM borrowings b
      WHERE b.inventory_id = i.id AND b.status = $2
        AND ($3::int IS NULL OR b.id <> $3::int)
    ), 0) AS tersedia, i.nama_barang
    FROM inventory i WHERE i.id = $1
  `, [inventoryId, STATUS_DIPINJAM, kecualikanBorrowingId]);
  return r.rows[0] || null;
}

/**
 * Daftar ringkas barang yang masih tersedia, khusus untuk mengisi pilihan pada
 * form ajukan pinjam.
 *
 * Ada endpoint tersendiri karena warga punya izin `inventaris.peminjaman`
 * tetapi TIDAK punya `inventaris.barang` — ia meminjam barang, bukan mengelola
 * daftarnya. Karena itu yang dikembalikan hanya yang perlu untuk memilih:
 * tanpa nilai barang, tanggal perolehan, maupun pencatatnya.
 */
async function getBarangTersedia(req, res) {
  try {
    const result = await pool.query(`
      SELECT i.id, i.nama_barang, i.kategori, i.kondisi, i.lokasi,
             i.jumlah AS jumlah_total,
             ${DIPINJAM_SUBQUERY} AS sedang_dipinjam,
             (i.jumlah - ${DIPINJAM_SUBQUERY}) AS tersedia
      FROM inventory i
      WHERE (i.jumlah - ${DIPINJAM_SUBQUERY}) > 0
      ORDER BY i.nama_barang ASC
    `);
    return res.status(200).json({ success: true, count: result.rowCount, data: result.rows });
  } catch (err) {
    console.error('GetBarangTersedia Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createBorrowing(req, res) {
  const client = await pool.connect();
  try {
    const { inventory_id, user_id, jumlah, keterangan,
      tanggal_pinjam, tanggal_rencana_kembali } = req.body;

    if (!inventory_id) {
      return res.status(400).json({ success: false, message: 'Barang wajib dipilih.' });
    }
    const qty = Number(jumlah) || 1;
    if (qty <= 0) {
      return res.status(400).json({ success: false, message: 'Jumlah pinjam harus lebih dari 0.' });
    }

    // Pengurus mencatatkan peminjaman atas nama warga, jadi boleh menentukan
    // peminjamnya. Warga TIDAK: kalau `user_id` dari body dihormati, seorang
    // warga bisa mencatat pinjaman atas nama tetangganya.
    const peminjamId = req.user.role === 'warga' ? req.user.id : (user_id || req.user.id);
    const peminjam = await client.query('SELECT id, nama FROM users WHERE id = $1', [peminjamId]);
    if (peminjam.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Peminjam tidak ditemukan.' });
    }

    await client.query('BEGIN');

    const stok = await hitungTersedia(client, inventory_id);
    if (!stok) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Barang tidak ditemukan.' });
    }
    if (stok.tersedia < qty) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: `Stok ${stok.nama_barang} tidak mencukupi. Tersedia ${stok.tersedia}, diminta ${qty}.`,
      });
    }

    // Jika diajukan oleh Warga, status awal 'Menunggu Persetujuan'.
    // Jika dicatat langsung oleh Admin, status langsung 'Dipinjam'.
    const initialStatus = req.user.role === 'warga' ? 'Menunggu Persetujuan' : STATUS_DIPINJAM;

    // inventory.jumlah SENGAJA tidak disentuh: itu total milik, bukan stok sisa.
    const result = await client.query(
      `INSERT INTO borrowings (inventory_id, user_id, nama_peminjam, jumlah, keterangan,
                               tanggal_pinjam, tanggal_rencana_kembali, status, dicatat_oleh)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [
        inventory_id, peminjamId, peminjam.rows[0].nama, qty, keterangan || null,
        tanggal_pinjam || new Date().toISOString().split('T')[0],
        tanggal_rencana_kembali || null, initialStatus, req.user.id,
      ]
    );

    await client.query('COMMIT');
    const msg = initialStatus === 'Menunggu Persetujuan'
      ? 'Permohonan peminjaman berhasil dikirim. Menunggu persetujuan Admin RT.'
      : 'Peminjaman berhasil dicatat.';

    // Nama peminjam ikut dicatat karena pengurus boleh mencatat atas nama warga
    // lain — tanpa itu tidak terlihat siapa yang sebenarnya memegang barang.
    await logActivity(
      req,
      TIPE.CREATE,
      `Mencatat peminjaman ${qty} ${ringkas(stok.nama_barang)} atas nama ` +
        `${ringkas(peminjam.rows[0].nama)} (status awal: ${initialStatus})`
    );

    return res.status(201).json({ success: true, message: msg, data: result.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('CreateBorrowing Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

async function updateBorrowing(req, res) {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const { jumlah, keterangan, tanggal_pinjam, tanggal_rencana_kembali, user_id } = req.body;

    const lama = await client.query('SELECT * FROM borrowings WHERE id = $1', [id]);
    if (lama.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Peminjaman tidak ditemukan.' });
    }
    const pinjam = lama.rows[0];

    if (jumlah !== undefined && Number(jumlah) <= 0) {
      return res.status(400).json({ success: false, message: 'Jumlah pinjam harus lebih dari 0.' });
    }

    await client.query('BEGIN');

    // Saat jumlah dinaikkan, ketersediaan dihitung tanpa menghitung baris ini
    // sendiri agar tidak menghalangi dirinya.
    if (jumlah !== undefined && pinjam.status === STATUS_DIPINJAM) {
      const stok = await hitungTersedia(client, pinjam.inventory_id, Number(id));
      if (stok && stok.tersedia < Number(jumlah)) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message: `Stok ${stok.nama_barang} tidak mencukupi. Tersedia ${stok.tersedia} bila peminjaman ini disetel ulang.`,
        });
      }
    }

    let namaPeminjam = null;
    if (user_id) {
      const p = await client.query('SELECT nama FROM users WHERE id = $1', [user_id]);
      if (p.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ success: false, message: 'Peminjam tidak ditemukan.' });
      }
      namaPeminjam = p.rows[0].nama;
    }

    const result = await client.query(
      `UPDATE borrowings SET
         jumlah                  = COALESCE($1, jumlah),
         keterangan              = COALESCE($2, keterangan),
         tanggal_pinjam          = COALESCE($3, tanggal_pinjam),
         tanggal_rencana_kembali = COALESCE($4, tanggal_rencana_kembali),
         user_id                 = COALESCE($5, user_id),
         nama_peminjam           = COALESCE($6, nama_peminjam),
         updated_at              = NOW()
       WHERE id = $7 RETURNING *`,
      [
        jumlah ?? null, keterangan ?? null, tanggal_pinjam || null,
        tanggal_rencana_kembali || null, user_id || null, namaPeminjam, id,
      ]
    );

    await client.query('COMMIT');
    const p = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mengubah catatan peminjaman #${p.id} — ${p.jumlah} unit, status ${p.status}`);

    return res.status(200).json({ success: true, message: 'Peminjaman berhasil diperbarui.', data: result.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('UpdateBorrowing Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

async function returnBorrowing(req, res) {
  try {
    const { id } = req.params;
    const { tanggal_kembali } = req.body || {};

    const pinjam = await pool.query('SELECT * FROM borrowings WHERE id = $1', [id]);
    if (pinjam.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Peminjaman tidak ditemukan.' });
    }
    if (pinjam.rows[0].status === STATUS_KEMBALI) {
      return res.status(400).json({ success: false, message: 'Peminjaman ini sudah dikembalikan.' });
    }

    // inventory.jumlah SENGAJA tidak disentuh: ketersediaan pulih dengan
    // sendirinya karena baris ini tidak lagi berstatus Dipinjam.
    const result = await pool.query(
      `UPDATE borrowings SET status = $1, tanggal_kembali = $2, updated_at = NOW()
       WHERE id = $3 RETURNING *`,
      [STATUS_KEMBALI, tanggal_kembali || new Date().toISOString().split('T')[0], id]
    );

    const p = result.rows[0];
    await logActivity(req, TIPE.UPDATE, `Mencatat pengembalian barang — peminjaman #${p.id}, ${p.jumlah} unit`);

    return res.status(200).json({ success: true, message: 'Barang berhasil dikembalikan.', data: result.rows[0] });
  } catch (err) {
    console.error('ReturnBorrowing Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteBorrowing(req, res) {
  try {
    const { id } = req.params;
    const pinjam = await pool.query('SELECT status FROM borrowings WHERE id = $1', [id]);
    if (pinjam.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Peminjaman tidak ditemukan.' });
    }
    // Riwayat pengembalian adalah jejak yang perlu dijaga; yang boleh dibatalkan
    // hanya peminjaman yang belum selesai (salah catat).
    if (pinjam.rows[0].status === STATUS_KEMBALI) {
      return res.status(409).json({
        success: false,
        message: 'Peminjaman yang sudah dikembalikan tidak bisa dihapus karena merupakan riwayat.',
      });
    }
    await pool.query('DELETE FROM borrowings WHERE id = $1', [id]);
    await logActivity(req, TIPE.DELETE, `Membatalkan/menghapus catatan peminjaman #${id}`);

    return res.status(200).json({ success: true, message: 'Catatan peminjaman berhasil dibatalkan.' });
  } catch (err) {
    console.error('DeleteBorrowing Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== EXPORT ========================

async function kirimExport(res, { format, kolom, rows, judul, namaFile }) {
  if (format === 'pdf') {
    const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=${namaFile}.pdf`);
    doc.pipe(res);

    doc.fontSize(18).text(judul, { align: 'center' });
    doc.moveDown();

    await doc.table({
      title: judul,
      headers: kolom.map((k) => k.header),
      rows: rows.map((r) => kolom.map((k) => String(r[k.key] ?? '-'))),
    }, {
      prepareHeader: () => doc.font('Helvetica-Bold').fontSize(8),
      prepareRow: () => doc.font('Helvetica').fontSize(7),
    });

    doc.end();
    return;
  }

  const workbook = new ExcelJS.Workbook();
  const worksheet = workbook.addWorksheet(judul);
  worksheet.columns = kolom;
  worksheet.getRow(1).font = { bold: true };
  rows.forEach((r) => worksheet.addRow(r));

  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename=${namaFile}.xlsx`);
  await workbook.xlsx.write(res);
  res.end();
}

async function exportInventory(req, res) {
  try {
    const { where, params } = filterBarang(req);
    const result = await pool.query(`${SELECT_BARANG} ${where} ORDER BY i.nama_barang ASC`, params);

    const rows = result.rows.map((i, idx) => ({
      no: idx + 1,
      nama_barang: i.nama_barang || '-',
      kategori: i.kategori || '-',
      jumlah_total: i.jumlah_total,
      sedang_dipinjam: i.sedang_dipinjam,
      tersedia: i.tersedia,
      kondisi: i.kondisi || '-',
      lokasi: i.lokasi || '-',
      nilai_barang: Number(i.nilai_barang) || 0,
      nilai_total: Number(i.nilai_total) || 0,
      keterangan: i.keterangan || '-',
    }));

    await kirimExport(res, {
      format: (req.query.format || 'excel').toLowerCase(),
      kolom: KOLOM_BARANG, rows,
      judul: 'Inventaris RT', namaFile: 'Inventaris_RT',
    });
  } catch (err) {
    console.error('ExportInventory Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export.' });
    }
  }
}

async function exportBorrowings(req, res) {
  try {
    const { where, params } = filterPinjam(req);
    const result = await pool.query(
      `${SELECT_PINJAM} ${where} ORDER BY b.tanggal_pinjam DESC, b.id DESC`,
      params
    );

    const rows = result.rows.map((b, idx) => ({
      no: idx + 1,
      nama_barang: b.nama_barang || '-',
      nama_peminjam: b.nama_peminjam || '-',
      jumlah: b.jumlah,
      tanggal_pinjam: formatTanggal(b.tanggal_pinjam) || '-',
      tanggal_rencana_kembali: formatTanggal(b.tanggal_rencana_kembali) || '-',
      tanggal_kembali: formatTanggal(b.tanggal_kembali) || '-',
      status_efektif: b.status_efektif,
      hari_terlambat: b.hari_terlambat > 0 ? b.hari_terlambat : '-',
      keterangan: b.keterangan || '-',
    }));

    await kirimExport(res, {
      format: (req.query.format || 'excel').toLowerCase(),
      kolom: KOLOM_PINJAM, rows,
      judul: 'Riwayat Peminjaman Barang', namaFile: 'Peminjaman_Barang',
    });
  } catch (err) {
    console.error('ExportBorrowings Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export.' });
    }
  }
}

async function approveBorrowing(req, res) {
  try {
    const { id } = req.params;
    const pinjam = await pool.query('SELECT * FROM borrowings WHERE id = $1', [id]);
    if (pinjam.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Peminjaman tidak ditemukan.' });
    }
    const result = await pool.query(
      `UPDATE borrowings SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *`,
      [STATUS_DIPINJAM, id]
    );
    const b = result.rows[0];
    await logActivity(
      req,
      TIPE.UPDATE,
      `Menyetujui peminjaman #${id}: ${b.jumlah} unit oleh ${ringkas(b.nama_peminjam)}`
    );

    return res.status(200).json({ success: true, message: 'Peminjaman barang telah disetujui.', data: result.rows[0] });
  } catch (err) {
    console.error('ApproveBorrowing Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function rejectBorrowing(req, res) {
  try {
    const { id } = req.params;
    const pinjam = await pool.query('SELECT * FROM borrowings WHERE id = $1', [id]);
    if (pinjam.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Peminjaman tidak ditemukan.' });
    }
    const result = await pool.query(
      `UPDATE borrowings SET status = 'Ditolak', updated_at = NOW() WHERE id = $1 RETURNING *`,
      [id]
    );
    const b = result.rows[0];
    await logActivity(
      req,
      TIPE.UPDATE,
      `Menolak permohonan peminjaman #${id}: ${b.jumlah} unit oleh ${ringkas(b.nama_peminjam)}`
    );

    return res.status(200).json({ success: true, message: 'Permohonan peminjaman ditolak.', data: result.rows[0] });
  } catch (err) {
    console.error('RejectBorrowing Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getInventory,
  getInventoryStats,
  getInventoryDetail,
  createInventory,
  updateInventory,
  deleteInventory,
  exportInventory,
  getBorrowings,
  getBorrowingStats,
  getBarangTersedia,
  createBorrowing,
  updateBorrowing,
  approveBorrowing,
  rejectBorrowing,
  returnBorrowing,
  deleteBorrowing,
  exportBorrowings,
};
