const { pool } = require('../config/database');
const { logActivity } = require('../services/log.service');
const bcrypt = require('bcryptjs');
const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const { jenisKelamin: normalJk, labelJenisKelamin } = require('../utils/normalisasi');
const { sandiAcak } = require('../utils/sandi');

/**
 * Tata letak kolom Excel/PDF. Export menulis dengan urutan ini dan import
 * membaca dengan urutan ini, sehingga siklus export → edit → import selalu
 * konsisten. Kolom A–H sengaja tidak diubah agar file lama tetap bisa diimpor.
 */
const KOLOM = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'NIK', key: 'nik', width: 20 },
  { header: 'NAMA LENGKAP', key: 'nama', width: 30 },
  { header: 'NO KK', key: 'no_kk', width: 20 },
  { header: 'STATUS HUBUNGAN', key: 'status_hubungan', width: 22 },
  { header: 'DOMISILI', key: 'domisili', width: 12 },
  { header: 'STATUS', key: 'status', width: 12 },
  { header: 'KTP', key: 'ktp', width: 8 },
  { header: 'JENIS KELAMIN', key: 'jenis_kelamin', width: 14 },
  { header: 'TANGGAL LAHIR', key: 'tanggal_lahir', width: 15 },
  { header: 'STATUS PERKAWINAN', key: 'status_pernikahan', width: 20 },
  { header: 'AGAMA', key: 'agama', width: 14 },
  { header: 'PENDIDIKAN', key: 'pendidikan', width: 18 },
  { header: 'PEKERJAAN', key: 'pekerjaan', width: 22 },
  { header: 'STATUS RUMAH', key: 'status_rumah', width: 16 },
  // Ditambahkan di urutan terakhir agar kolom A-O tidak bergeser dan file
  // Excel hasil export lama tetap bisa diimpor.
  { header: 'NO HP', key: 'no_hp', width: 16 },
];

const BASE_QUERY = `
  SELECT
    ak.*,
    k.no_kk, k.alamat, k.rt, k.rw, k.kelurahan, k.kecamatan, k.status_rumah
  FROM anggota_keluarga ak
  JOIN keluarga k ON ak.keluarga_id = k.id
  WHERE k.deleted_at IS NULL
`;

/**
 * Bangun query daftar warga beserta parameter pencariannya.
 *
 * Menerima `req`, bukan hanya `search`, supaya penyempitan baris untuk warga
 * ikut terbawa ke SEMUA pemakainya sekaligus — daftar, export Excel, dan export
 * PDF. Ketiganya memanggil fungsi ini; kalau penyaringannya ditulis di layar
 * daftar saja, kedua export akan tetap membocorkan seluruh tabel, dan itu justru
 * kebocoran yang paling merugikan karena berbentuk berkas yang bisa disimpan.
 *
 * Sama seperti di family.controller: hari ini warga memang tidak punya izin ke
 * modul ini, jadi klausanya belum pernah terpakai. Ia lapisan kedua, untuk saat
 * seseorang memberi warga hak View dari layar Menu & Akses.
 */
function buildWargaQuery(req) {
  const search = req?.query?.search;
  let query = BASE_QUERY;
  const params = [];

  if (req?.user?.role === 'warga') {
    params.push(req.user.id);
    query += ` AND k.no_kk = (SELECT no_kk FROM users WHERE id = $${params.length})`;
  }

  if (search) {
    params.push(`%${search}%`);
    query += ` AND (
      ak.nama ILIKE $${params.length} OR
      ak.nik ILIKE $${params.length} OR
      k.no_kk ILIKE $${params.length} OR
      ak.status_keluarga ILIKE $${params.length} OR
      k.alamat ILIKE $${params.length} OR
      ak.domisili ILIKE $${params.length} OR
      ak.agama ILIKE $${params.length} OR
      ak.pendidikan ILIKE $${params.length} OR
      ak.pekerjaan ILIKE $${params.length} OR
      ak.status_pernikahan ILIKE $${params.length} OR
      (ak.is_aktif = true AND 'aktif' ILIKE $${params.length}) OR
      (ak.is_aktif = false AND 'tidak aktif' ILIKE $${params.length}) OR
      (ak.has_ktp = true AND 'sudah' ILIKE $${params.length}) OR
      (ak.has_ktp = false AND 'belum' ILIKE $${params.length})
    )`;
  }
  return { query, params };
}

const pad = (n) => n.toString().padStart(2, '0');

/**
 * Format DATE dari Postgres menjadi YYYY-MM-DD.
 *
 * Memakai komponen waktu LOKAL, bukan toISOString(): node-postgres mengembalikan
 * kolom DATE sebagai tengah malam waktu lokal, sehingga konversi ke UTC akan
 * memundurkan tanggal satu hari di zona waktu Indonesia.
 */
function formatTanggal(nilai) {
  if (!nilai) return '';
  const d = nilai instanceof Date ? nilai : new Date(nilai);
  if (isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/**
 * Baca tanggal dari sel Excel. ExcelJS mengembalikan Date untuk sel bertipe
 * tanggal, tetapi string bila kolomnya diformat sebagai teks — keduanya
 * ditangani. Mengembalikan null bila kosong atau tidak bisa diurai, sehingga
 * baris tetap tersimpan dan warga masuk kategori "Tidak Diisi".
 */
function parseTanggalExcel(nilai) {
  if (nilai === null || nilai === undefined || nilai === '') return null;
  // ExcelJS memberi Date berbasis UTC untuk sel bertipe tanggal, jadi di sini
  // justru komponen UTC yang benar (kebalikan dari formatTanggal di atas).
  if (nilai instanceof Date) {
    return `${nilai.getUTCFullYear()}-${pad(nilai.getUTCMonth() + 1)}-${pad(nilai.getUTCDate())}`;
  }

  const teks = nilai.toString().trim();
  if (!teks) return null;

  // Format lokal DD/MM/YYYY atau DD-MM-YYYY.
  const lokal = teks.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/);
  if (lokal) {
    const [, dd, mm, yyyy] = lokal;
    return `${yyyy}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`;
  }

  const d = new Date(teks);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

/** Ubah satu baris database menjadi baris Excel/PDF sesuai urutan KOLOM. */
function toRow(warga, index) {
  return {
    no: index + 1,
    nik: warga.nik || '-',
    nama: warga.nama || '-',
    no_kk: warga.no_kk || '-',
    status_hubungan: warga.status_hubungan_dalam_keluarga || warga.status_keluarga || '-',
    domisili: warga.domisili || 'Tetap',
    status: warga.is_aktif ? 'Aktif' : 'Tidak Aktif',
    ktp: warga.has_ktp ? 'Sudah' : 'Belum',
    // Ditulis sebagai kata utuh, bukan 'L'/'P'. Berkas ini disunting manusia,
    // dan huruf tunggal mengundang pengisian bebas seperti "Pria" yang dulu
    // salah dipetakan saat diimpor kembali.
    jenis_kelamin: labelJenisKelamin(warga.jenis_kelamin),
    tanggal_lahir: formatTanggal(warga.tanggal_lahir),
    status_pernikahan: warga.status_pernikahan || '',
    agama: warga.agama || '',
    pendidikan: warga.pendidikan || '',
    pekerjaan: warga.pekerjaan || '',
    status_rumah: warga.status_rumah || '',
    no_hp: warga.no_hp || '',
  };
}

/** Kosongkan string kosong menjadi null agar tersimpan sebagai NULL di database. */
function atauNull(nilai) {
  if (nilai === undefined || nilai === null) return null;
  const teks = nilai.toString().trim();
  return teks === '' ? null : teks;
}

async function getWarga(req, res) {
  try {
    const { query, params } = buildWargaQuery(req);
    const countQuery = `SELECT COUNT(*) FROM (${query}) AS total`;
    const countResult = await pool.query(countQuery, params);
    const totalData = parseInt(countResult.rows[0].count);

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 25;
    const offset = (page - 1) * limit;
    const totalPages = Math.ceil(totalData / limit);

    const finalQuery = `${query} ORDER BY k.no_kk, ak.id ASC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    const finalParams = [...params, limit, offset];

    const result = await pool.query(finalQuery, finalParams);
    const sanitizedData = result.rows.map(warga => ({
      ...warga,
      nik: warga.nik || '-',
      nama: warga.nama || '-',
      no_kk: warga.no_kk || '-',
      jenis_kelamin: labelJenisKelamin(warga.jenis_kelamin),
      status_keluarga: warga.status_keluarga || '-',
      alamat: warga.alamat || '-',
      domisili: warga.domisili || 'Tetap',
      tanggal_lahir: formatTanggal(warga.tanggal_lahir),
      status_pernikahan: warga.status_pernikahan || '-',
      agama: warga.agama || '-',
      pendidikan: warga.pendidikan || '-',
      pekerjaan: warga.pekerjaan || '-',
      status_rumah: warga.status_rumah || '-',
      is_aktif: warga.is_aktif !== false,
      has_ktp: warga.has_ktp === true,
    }));
    return res.status(200).json({
      success: true,
      count: sanitizedData.length,
      pagination: {
        total_data: totalData,
        total_pages: totalPages,
        current_page: page,
        per_page: limit
      },
      data: sanitizedData
    });
  } catch (err) {
    console.error('GetWarga Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function exportWargaExcel(req, res) {
  try {
    const { query, params } = buildWargaQuery(req);
    const finalQuery = `${query} ORDER BY k.no_kk, ak.id ASC`;
    const result = await pool.query(finalQuery, params);

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Data Warga');
    worksheet.columns = KOLOM;

    // Buat kolom NO menjadi rata kiri
    worksheet.getColumn('no').alignment = { horizontal: 'left' };

    result.rows.forEach((warga, index) => worksheet.addRow(toRow(warga, index)));

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename=Data_Warga.xlsx');

    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error('Export Warga Excel Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export excel.' });
  }
}

async function exportWargaPdf(req, res) {
  try {
    const { query, params } = buildWargaQuery(req);
    const finalQuery = `${query} ORDER BY k.no_kk, ak.id ASC`;
    const result = await pool.query(finalQuery, params);

    const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'landscape' });

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename=Data_Warga.pdf');
    doc.pipe(res);

    doc.fontSize(18).text('Data Warga RT', { align: 'center' });
    doc.moveDown();

    const table = {
      title: 'Rekapitulasi Penduduk',
      headers: KOLOM.map(k => k.header),
      rows: result.rows.map((warga, index) => {
        const row = toRow(warga, index);
        return KOLOM.map(k => (row[k.key] === '' ? '-' : row[k.key].toString()));
      }),
    };

    await doc.table(table, {
      prepareHeader: () => doc.font('Helvetica-Bold').fontSize(8),
      prepareRow: () => doc.font('Helvetica').fontSize(7),
    });

    doc.end();
  } catch (err) {
    console.error('Export Warga PDF Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Terjadi kesalahan saat export pdf.' });
    }
  }
}

async function tambahWargaLengkap(req, res) {
  const client = await pool.connect();
  try {
    const {
      nik, nama, no_kk, no_hp, jenis_kelamin, alamat, status_keluarga, has_ktp,
      tanggal_lahir, status_pernikahan, agama, pendidikan, pekerjaan, status_rumah,
    } = req.body;

    if (!nik || !nama || !no_kk || !no_hp) {
      return res.status(400).json({ success: false, message: 'NIK, Nama, No KK, dan Nomor HP wajib diisi.' });
    }

    if (!tanggal_lahir || !status_pernikahan || !agama || !pendidikan || !pekerjaan) {
      return res.status(400).json({
        success: false,
        message: 'Data demografi (Tanggal Lahir, Status Perkawinan, Agama, Pendidikan, Pekerjaan) wajib diisi.',
      });
    }

    if (status_keluarga === 'Kepala Keluarga' && !status_rumah) {
      return res.status(400).json({
        success: false,
        message: 'Status Rumah wajib diisi untuk Kepala Keluarga.',
      });
    }

    await client.query('BEGIN');

    const statusRumah = atauNull(status_rumah);

    // 1. Cek atau Buat Keluarga (KK)
    let keluargaId;
    const resKeluarga = await client.query('SELECT id FROM keluarga WHERE no_kk = $1', [no_kk]);
    if (resKeluarga.rows.length > 0) {
      keluargaId = resKeluarga.rows[0].id;
      // If family exists and this new person is Kepala Keluarga, update the KK head
      if (status_keluarga === 'Kepala Keluarga') {
        await client.query('UPDATE keluarga SET kepala_keluarga = $1 WHERE id = $2', [nama, keluargaId]);
      }
      // Status rumah adalah properti KK — perbarui hanya bila dikirim.
      if (statusRumah) {
        await client.query('UPDATE keluarga SET status_rumah = $1 WHERE id = $2', [statusRumah, keluargaId]);
      }
    } else {
      // Bila anggota pertama bukan Kepala Keluarga, namanya dipakai sementara
      // agar kolom kepala keluarga tidak pernah kosong. Nilai ini otomatis
      // tertimpa begitu anggota berstatus Kepala Keluarga ditambahkan.
      // Untuk membedakan mana yang sementara, pembaca memakai kolom turunan
      // kepala_terkonfirmasi — bukan menebak dari isi nama.
      const newKk = await client.query(
        'INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, status_rumah) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id',
        [no_kk, nama, alamat || '-', '001', '001', '-', '-', statusRumah || 'Milik Sendiri']
      );
      keluargaId = newKk.rows[0].id;
    }

    // 2. Insert ke anggota_keluarga
    const resWarga = await client.query('SELECT id FROM anggota_keluarga WHERE nik = $1', [nik]);
    if (resWarga.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, message: 'Warga dengan NIK tersebut sudah ada di data kependudukan.' });
    }

    const ktpStatus = has_ktp !== undefined ? has_ktp : true;
    await client.query(
      `INSERT INTO anggota_keluarga
        (keluarga_id, nik, nama, jenis_kelamin, status_keluarga, has_ktp, no_hp,
         tanggal_lahir, status_pernikahan, agama, pendidikan, pekerjaan)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
      [
        // Dinormalisasi: kolomnya varchar(1), dan form mana pun bisa saja
        // mengirim "Laki-laki" yang akan ditolak database.
        keluargaId, nik, nama, normalJk(jenis_kelamin, 'L'), status_keluarga || 'Anggota Keluarga',
        ktpStatus, atauNull(no_hp), atauNull(tanggal_lahir), atauNull(status_pernikahan),
        atauNull(agama), atauNull(pendidikan), atauNull(pekerjaan),
      ]
    );

    // 3. Insert ke users (Akun Login Otomatis)
    const resUser = await client.query('SELECT id FROM users WHERE username = $1 OR email = $1', [nik]);
    let sandiAwal = null;
    if (resUser.rows.length === 0) {
      // Acak, bukan '123456'. Lihat src/utils/sandi.js untuk alasannya.
      sandiAwal = sandiAcak();
      const salt = await bcrypt.genSalt(10);
      const passwordHash = await bcrypt.hash(sandiAwal, salt);

      // Note: we insert NIK into username. We also use NIK for email since email is unique but maybe required by old queries
      await client.query(
        'INSERT INTO users (username, email, password_hash, nama, no_hp, no_kk, alamat, role, is_active, nik) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)',
        [nik, nik, passwordHash, nama, no_hp, no_kk, alamat, 'warga', true, nik]
      );
    }

    await client.query('COMMIT');

    // Sandinya TIDAK ikut dicatat ke jejak audit. Log dibaca administrator dan
    // bersifat permanen; menuliskan sandi warga di sana berarti setiap
    // administrator berikutnya bisa masuk sebagai warga mana pun, selamanya.
    await logActivity(req, 'CREATE', `Menambah data warga ${nama} (NIK ${nik}) dan membuat akun loginnya`);
    return res.status(201).json({
      success: true,
      message: sandiAwal
        ? 'Data warga berhasil ditambahkan. Catat sandi awalnya — hanya ditampilkan sekali ini.'
        : 'Data warga berhasil ditambahkan. Akun loginnya sudah ada sebelumnya.',
      data: { username: nik, password: sandiAwal }
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Tambah Warga Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal menambah data warga.' });
  } finally {
    client.release();
  }
}

/**
 * Ubah data satu warga (anggota_keluarga) berdasarkan NIK.
 *
 * Mengikuti struktur `tambahWargaLengkap`: data kependudukan di
 * `anggota_keluarga`, properti KK (kepala keluarga, status rumah, alamat) di
 * `keluarga`, dan akun login disinkronkan lewat `users.nik`.
 *
 * NIK sengaja TIDAK bisa diubah — ia kunci utama anggota dan sekaligus
 * username akun loginnya. Mengubahnya berarti membuat orang baru, bukan
 * mengoreksi data.
 */
async function updateWargaLengkap(req, res) {
  const client = await pool.connect();
  try {
    const { nik } = req.params;
    const {
      nama, no_kk, no_hp, jenis_kelamin, alamat, status_keluarga, has_ktp,
      tanggal_lahir, status_pernikahan, agama, pendidikan, pekerjaan, status_rumah, is_aktif,
    } = req.body;

    // 1. Warga harus ada lebih dulu — NIK adalah kuncinya.
    const lama = await client.query(
      `SELECT ak.*, k.no_kk AS kk_lama FROM anggota_keluarga ak
       JOIN keluarga k ON ak.keluarga_id = k.id
       WHERE ak.nik = $1`,
      [nik]
    );
    if (lama.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Warga dengan NIK tersebut tidak ditemukan.' });
    }
    const sebelum = lama.rows[0];

    if (!nama || !nama.trim()) {
      return res.status(400).json({ success: false, message: 'Nama wajib diisi.' });
    }

    await client.query('BEGIN');

    // 2. Pindahkan ke KK yang benar bila no_kk berubah.
    //    Kutip logika "cari atau buat keluarga" dari tambahWargaLengkap supaya
    //    kedua jalur tidak menyimpang satu sama lain.
    const noKkBaru = no_kk && no_kk.trim() ? no_kk.trim() : sebelum.kk_lama;
    const statusRumah = atauNull(status_rumah);
    const namaFinal = nama.trim();

    let keluargaId = sebelum.keluarga_id;
    if (noKkBaru !== sebelum.kk_lama) {
      const resKeluarga = await client.query('SELECT id FROM keluarga WHERE no_kk = $1', [noKkBaru]);
      if (resKeluarga.rows.length > 0) {
        keluargaId = resKeluarga.rows[0].id;
      } else {
        const newKk = await client.query(
          'INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, status_rumah) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id',
          [noKkBaru, namaFinal, alamat || '-', '001', '001', '-', '-', statusRumah || 'Milik Sendiri']
        );
        keluargaId = newKk.rows[0].id;
      }
    }

    // 3. Perbarui data kependudukan. `jenis_kelamin` dinormalisasi lagi di sini
    //    walau berasal dari database — kolomnya varchar(1) dan nilai dari form
    //    bisa berupa tulisan utuh ("Laki-laki").
    await client.query(
      `UPDATE anggota_keluarga SET
         keluarga_id = $1,
         nama = $2,
         jenis_kelamin = $3,
         status_keluarga = $4,
         has_ktp = $5,
         no_hp = $6,
         tanggal_lahir = $7,
         status_pernikahan = $8,
         agama = $9,
         pendidikan = $10,
         pekerjaan = $11,
         is_aktif = $12
       WHERE nik = $13`,
      [
        keluargaId,
        namaFinal,
        jenis_kelamin ? normalJk(jenis_kelamin, sebelum.jenis_kelamin) : sebelum.jenis_kelamin,
        status_keluarga || sebelum.status_keluarga,
        has_ktp !== undefined ? has_ktp : sebelum.has_ktp,
        atauNull(no_hp),
        atauNull(tanggal_lahir),
        atauNull(status_pernikahan),
        atauNull(agama),
        atauNull(pendidikan),
        atauNull(pekerjaan),
        is_aktif !== undefined ? is_aktif : sebelum.is_aktif,
        nik,
      ]
    );

    // 4. Properti KK: kepala keluarga & status rumah hanya bermakna pada KK.
    if (status_keluarga === 'Kepala Keluarga') {
      await client.query('UPDATE keluarga SET kepala_keluarga = $1 WHERE id = $2', [namaFinal, keluargaId]);
    }
    if (statusRumah) {
      await client.query('UPDATE keluarga SET status_rumah = $1 WHERE id = $2', [statusRumah, keluargaId]);
    }
    if (alamat && alamat.trim()) {
      await client.query('UPDATE keluarga SET alamat = $1 WHERE id = $2', [alamat.trim(), keluargaId]);
    }

    // 5. Sinkronkan akun login (users) bila ada — nama, HP, dan no_kk-nya.
    await client.query(
      `UPDATE users SET nama = $1, no_hp = $2, no_kk = $3 WHERE nik = $4`,
      [namaFinal, atauNull(no_hp) || '-', noKkBaru, nik]
    );

    await client.query('COMMIT');

    await logActivity(req, 'UPDATE', `Mengubah data warga ${namaFinal} (NIK ${nik})`);
    return res.status(200).json({ success: true, message: 'Data warga berhasil diperbarui.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Update Warga Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal memperbarui data warga.' });
  } finally {
    client.release();
  }
}

async function importWargaExcel(req, res) {
  const client = await pool.connect();
  try {
    const { fileBase64 } = req.body;
    if (!fileBase64) {
      return res.status(400).json({ success: false, message: 'File tidak ditemukan.' });
    }

    const buffer = Buffer.from(fileBase64, 'base64');
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(buffer);

    const worksheet = workbook.worksheets[0];
    if (!worksheet) {
      return res.status(400).json({ success: false, message: 'Format Excel tidak valid.' });
    }

    await client.query('BEGIN');

    let successCount = 0;
    let failedCount = 0;
    const errors = [];
    const akunBaru = [];

    // Urutan kolom mengikuti konstanta KOLOM di atas (baris 1 = header).
    const rowCount = worksheet.rowCount;
    for (let rowNumber = 2; rowNumber <= rowCount; rowNumber++) {
      const row = worksheet.getRow(rowNumber);
      try {
        const teks = (kolom) => row.getCell(kolom).value?.toString().trim() || null;

        const nik = teks(2);
        const nama = teks(3);
        const no_kk = teks(4);
        const statusHubungan = teks(5) || 'Anggota Keluarga';
        const domisili = teks(6) || 'Tetap';
        const isAktif = (teks(7) || 'Aktif').toLowerCase() !== 'tidak aktif';
        const has_ktp = (teks(8) || '').toLowerCase() === 'sudah';
        // Dulu `jkRaw.startsWith('P') ? 'P' : 'L'`, yang MEMBALIK dua kata
        // paling umum: "PRIA" menjadi P dan "WANITA" menjadi L — tanpa error,
        // sehingga Statistik melaporkan angka gender yang salah diam-diam.
        // Bawaan 'L' dipertahankan agar baris berkolom kosong tetap terimpor
        // seperti sebelumnya.
        const jenis_kelamin = normalJk(teks(9), 'L');
        const tanggal_lahir = parseTanggalExcel(row.getCell(10).value);
        const status_pernikahan = teks(11);
        const agama = teks(12);
        const pendidikan = teks(13);
        const pekerjaan = teks(14);
        const status_rumah = teks(15);
        // Excel sering menghapus angka nol di depan nomor HP, jadi nilainya
        // dikembalikan ke bentuk 08xx bila terbaca sebagai 8xx.
        let no_hp = teks(16);
        if (no_hp) {
          no_hp = no_hp.replace(/[^0-9+]/g, '');
          if (no_hp.startsWith('8')) no_hp = `0${no_hp}`;
        }

        // Baris tanpa NIK / Nama / No. KK DILAPORKAN, bukan dilewati diam-diam.
        //
        // Sebelumnya baris ini hanya `continue`, tanpa menambah failedCount
        // dan tanpa menulis apa pun ke `errors`. Akibatnya mengimpor 100 baris
        // yang 20 di antaranya kurang lengkap menghasilkan laporan
        // "80 berhasil, 0 gagal" — dua puluh warga hilang tanpa jejak, dan
        // tidak ada apa pun di layar yang memberi tahu bahwa mereka ada.
        //
        // Ketiga kolom ini memang wajib: NIK adalah kunci unik anggota, No. KK
        // menentukan keluarganya, dan nama tidak bisa dikarang. Sisanya boleh
        // kosong dan akan tampil sebagai "Tidak Diisi" di Statistik.
        const kurang = [];
        if (!nik) kurang.push('NIK');
        if (!nama) kurang.push('Nama');
        if (!no_kk) kurang.push('No. KK');
        if (kurang.length > 0) {
          failedCount++;
          errors.push(`Baris ${rowNumber}: ${kurang.join(', ')} kosong — baris dilewati.`);
          continue;
        }

        // Check if exist
        const resWarga = await client.query('SELECT id FROM anggota_keluarga WHERE nik = $1', [nik]);
        if (resWarga.rows.length > 0) {
          failedCount++;
          errors.push(`Baris ${rowNumber}: NIK ${nik} sudah terdaftar.`);
          continue;
        }

        let keluargaId;
        const resKeluarga = await client.query('SELECT id FROM keluarga WHERE no_kk = $1', [no_kk]);
        if (resKeluarga.rows.length > 0) {
          keluargaId = resKeluarga.rows[0].id;
          if (statusHubungan.toLowerCase() === 'kepala keluarga') {
            await client.query('UPDATE keluarga SET kepala_keluarga = $1 WHERE id = $2', [nama, keluargaId]);
          }
          if (status_rumah) {
            await client.query('UPDATE keluarga SET status_rumah = $1 WHERE id = $2', [status_rumah, keluargaId]);
          }
        } else {
          const newKk = await client.query(
            'INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, status_rumah) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id',
            [no_kk, nama, '-', '001', '001', '-', '-', status_rumah || 'Milik Sendiri']
          );
          keluargaId = newKk.rows[0].id;
        }

        await client.query(
          `INSERT INTO anggota_keluarga
            (keluarga_id, nik, nama, jenis_kelamin, status_keluarga, has_ktp, domisili, is_aktif,
             tanggal_lahir, status_pernikahan, agama, pendidikan, pekerjaan, no_hp)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
          [
            keluargaId, nik, nama, jenis_kelamin, statusHubungan, has_ktp, domisili, isAktif,
            tanggal_lahir, status_pernikahan, agama, pendidikan, pekerjaan, no_hp,
          ]
        );

        const resUser = await client.query('SELECT id FROM users WHERE username = $1', [nik]);
        if (resUser.rows.length === 0) {
          const sandiAwal = sandiAcak();
          const salt = await bcrypt.genSalt(10);
          const passwordHash = await bcrypt.hash(sandiAwal, salt);
          await client.query(
            'INSERT INTO users (username, email, password_hash, nama, no_hp, no_kk, alamat, role, is_active, nik) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)',
            [nik, nik, passwordHash, nama, no_hp || '-', no_kk, '-', 'warga', true, nik]
          );
          // Dikumpulkan untuk dikembalikan sekali di akhir impor. Inilah
          // satu-satunya kesempatan sandi ini terbaca — setelah respons ini
          // yang tersisa hanya hash-nya.
          akunBaru.push({ nama, nik, sandi: sandiAwal });
        }

        successCount++;
      } catch (err) {
        failedCount++;
        errors.push(`Baris ${rowNumber}: ${err.message}`);
      }
    }

    await client.query('COMMIT');

    await logActivity(req, 'IMPORT', `Mengimpor data warga dari Excel: ${successCount} berhasil, ${failedCount} gagal`);
    return res.status(200).json({
      success: true,
      message: `Berhasil mengimpor ${successCount} data warga. Gagal: ${failedCount}.`
        + (akunBaru.length > 0
          ? ` ${akunBaru.length} akun login dibuat — catat sandinya sekarang, tidak bisa dilihat lagi.`
          : ''),
      // Dinaikkan dari 5 ke 50. Lima terlalu sedikit untuk berkas Excel
      // sungguhan: bila 30 baris gagal karena kolom yang sama kosong,
      // menampilkan lima pertama membuat operator memperbaiki lima itu,
      // mengimpor ulang, lalu menemui lima berikutnya — berulang enam kali.
      // Jumlah seluruhnya tetap terbaca dari `failedCount`.
      errors: errors.slice(0, 50),
      total_gagal: failedCount,
      // Setiap akun mendapat sandi acaknya sendiri, bukan satu sandi yang sama
      // untuk semua orang. Daftarnya dikembalikan UTUH — dipotong seperti
      // `errors` justru berbahaya di sini, karena warga yang sandinya terpotong
      // akan punya akun yang tidak bisa dimasuki siapa pun.
      akun_baru: akunBaru,
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Import Warga Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal mengimpor data. Periksa format berkas Excel-nya.' });
  } finally {
    client.release();
  }
}

module.exports = { getWarga, exportWargaExcel, exportWargaPdf, tambahWargaLengkap, updateWargaLengkap, importWargaExcel };
