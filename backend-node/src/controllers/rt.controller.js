/**
 * Daftar RT dalam satu RW.
 *
 * ===================================================================
 * Kenapa modul ini tidak punya entri di matriks izin
 * ===================================================================
 *
 * Membuat dan menghapus RT adalah wewenang sistem, bukan wewenang modul —
 * alasannya sama persis dengan Menu & Akses dan Reset Sistem: kewenangan yang
 * menentukan BATAS seluruh data tidak boleh bergantung pada tabel yang batas
 * itu sendiri ikut menjaganya. Karena itu penjagaannya `roleGuard('admin')`,
 * dan matriks izin tetap 18 modul.
 *
 * ===================================================================
 * Kenapa daftarnya boleh dibaca semua peran
 * ===================================================================
 *
 * Setiap layar menampilkan RT mana yang sedang dilihat, dan warga pun perlu
 * tahu ia terdaftar di RT berapa. Yang membedakan bukan boleh atau tidaknya
 * membaca, melainkan BERAPA BANYAK yang terbaca: peran lintas RT menerima
 * seluruh RT dalam RW-nya, peran lain hanya menerima RT-nya sendiri.
 *
 * Penyaringannya memakai `bolehLintasRt` yang sama dengan seluruh pengendali
 * lain, bukan daftar peran yang ditulis ulang di sini.
 */
const { pool } = require('../config/database');
const { logActivity, TIPE } = require('../services/log.service');
const { bolehLintasRt } = require('../utils/lingkup-rt');
const { siapkanMasterRt } = require('../services/master-rt.service');
const ExcelJS = require('exceljs');

const KOLOM = `
  r.id, r.kode, r.nama, r.rw_kode, r.ketua_id, r.alamat_sekretariat,
  r.created_at, r.updated_at,
  k.nama AS ketua_nama,
  (SELECT COUNT(*)::int FROM keluarga kk
    WHERE kk.rt_id = r.id AND kk.deleted_at IS NULL) AS jumlah_kk,
  (SELECT COUNT(*)::int FROM users u
    WHERE u.rt_id = r.id AND u.deleted_at IS NULL) AS jumlah_akun
`;

async function getRt(req, res) {
  try {
    const params = [];
    let saring = '';
    if (!bolehLintasRt(req)) {
      // Peran biasa hanya melihat RT-nya sendiri. Bukan penyembunyian demi
      // kerapian: daftar RT lain memuat nama ketua dan alamat sekretariat.
      params.push(req.user?.rt_id ?? null);
      saring = ' AND r.id = $1';
    }
    const hasil = await pool.query(
      `SELECT ${KOLOM}
         FROM rt r
         LEFT JOIN users k ON k.id = r.ketua_id
        WHERE r.deleted_at IS NULL${saring}
        ORDER BY r.rw_kode, r.kode`,
      params
    );
    return res.status(200).json({
      success: true,
      count: hasil.rows.length,
      data: hasil.rows,
    });
  } catch (err) {
    console.error('GetRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Menormalkan nomor RT: "3" dan " 3 " sama-sama menjadi "003". */
function normalKode(nilai) {
  const bersih = String(nilai ?? '').trim();
  if (!bersih) return '';
  return /^\d+$/.test(bersih) ? bersih.padStart(3, '0') : bersih;
}

async function createRt(req, res) {
  try {
    const kode = normalKode(req.body?.kode);
    const rwKode = normalKode(req.body?.rw_kode) || req.user?.rw_kode || '001';
    const { nama, alamat_sekretariat, ketua_id } = req.body || {};

    if (!kode) {
      return res.status(400).json({ success: false, message: 'Nomor RT wajib diisi.' });
    }

    // RT dan tabel masternya lahir dalam SATU transaksi.
    //
    // Sebuah RT tanpa jenis iuran dan tanpa kategori kas bukan RT yang setengah
    // jadi — ia RT yang tidak bisa dipakai sama sekali: dropdown Generate
    // Tagihan kosong, dan Kas RT tidak punya satu pun pos untuk mencatat uang.
    // Tidak ada layar yang memberi tahu penyebabnya, karena tidak ada yang
    // salah menurut kode mana pun; daftarnya memang kosong.
    //
    // Membuatnya di luar transaksi berarti sebuah RT bisa berdiri tanpa master
    // ketika penyisipannya gagal di tengah, dan tidak ada jalan dari layar
    // untuk memperbaikinya.
    const client = await pool.connect();
    let baris;
    let master;
    try {
      await client.query('BEGIN');
      const hasil = await client.query(
        `INSERT INTO rt (kode, nama, rw_kode, alamat_sekretariat, ketua_id)
         VALUES ($1, $2, $3, $4, $5) RETURNING id, kode, nama, rw_kode`,
        [kode, (nama || '').trim() || `RT ${kode}`, rwKode,
          alamat_sekretariat || null, ketua_id || null]
      );
      baris = hasil.rows[0];
      master = await siapkanMasterRt(client, baris.id);
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }

    await logActivity(
      req, TIPE.CREATE,
      `Menambah RT ${kode} pada RW ${rwKode} — beserta ${master.jenis_iuran} jenis iuran, `
      + `${master.kategori_kas} kategori kas, dan ${master.kategori_bop} kategori BOP bawaan`
    );
    return res.status(201).json({
      success: true, message: 'RT berhasil ditambahkan.', data: { ...baris, master },
    });
  } catch (err) {
    // Ditangkap dari indeks unik, bukan diperiksa lebih dulu dengan SELECT:
    // dua permintaan bersamaan bisa lolos pemeriksaan dan tetap bentrok.
    if (err.code === '23505') {
      return res.status(409).json({
        success: false, message: 'Nomor RT tersebut sudah terdaftar pada RW ini.',
      });
    }
    console.error('CreateRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateRt(req, res) {
  try {
    const { id } = req.params;
    const { nama, alamat_sekretariat, ketua_id } = req.body || {};

    const lama = await pool.query('SELECT * FROM rt WHERE id = $1 AND deleted_at IS NULL', [id]);
    if (!lama.rows.length) {
      return res.status(404).json({ success: false, message: 'RT tidak ditemukan.' });
    }

    // Ketua RW hanya boleh menyunting RT DALAM RW-NYA SENDIRI.
    //
    // `roleGuard` di berkas rute menjawab "peran apa", bukan "RT yang mana".
    // Selama hanya ada satu RW dalam pemasangan ini pemeriksaannya memang
    // tidak pernah menolak apa pun — dan justru itu alasannya harus ada
    // sekarang: begitu RW kedua muncul, ketiadaannya berarti setiap Ketua RW
    // bisa menyunting RT tetangganya, dan tidak ada yang akan mengingat
    // menambahkannya di kemudian hari.
    //
    // 403, bukan 404: barisnya memang ada dan ia memang boleh melihatnya
    // lewat daftar RT — menyamarkannya justru membingungkan.
    if (req.user?.role === 'ketua_rw' && lama.rows[0].rw_kode !== req.user?.rw_kode) {
      return res.status(403).json({
        success: false,
        message: `RT ini berada di RW ${lama.rows[0].rw_kode}, di luar RW Anda.`,
      });
    }

    // Nomor RT sengaja TIDAK boleh diubah. Ia sudah tertanam pada topik MQTT
    // di setiap perangkat alarm yang terpasang; menggantinya dari layar akan
    // membuat sirene berhenti berbunyi tanpa satu pun pesan galat.
    const hasil = await pool.query(
      `UPDATE rt SET
         nama = COALESCE($2, nama),
         alamat_sekretariat = COALESCE($3, alamat_sekretariat),
         ketua_id = $4,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING id, kode, nama, rw_kode, ketua_id`,
      [id, (nama || '').trim() || null, alamat_sekretariat ?? null,
        ketua_id ?? lama.rows[0].ketua_id]
    );

    await logActivity(req, TIPE.UPDATE, `Mengubah data RT ${lama.rows[0].kode}`);
    return res.status(200).json({
      success: true, message: 'Data RT berhasil diperbarui.', data: hasil.rows[0],
    });
  } catch (err) {
    console.error('UpdateRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteRt(req, res) {
  try {
    const { id } = req.params;
    const rt = await pool.query('SELECT * FROM rt WHERE id = $1 AND deleted_at IS NULL', [id]);
    if (!rt.rows.length) {
      return res.status(404).json({ success: false, message: 'RT tidak ditemukan.' });
    }

    // Kunci asing `rt_id` memakai ON DELETE RESTRICT, jadi basis data akan
    // menolak sendiri. Diperiksa lebih dulu supaya pesannya menyebut berapa
    // banyak yang menghalangi, bukan sekadar galat kendala yang tidak terbaca.
    const isi = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM keluarga WHERE rt_id = $1 AND deleted_at IS NULL) AS kk,
         (SELECT COUNT(*)::int FROM users WHERE rt_id = $1 AND deleted_at IS NULL) AS akun`,
      [id]
    );
    const { kk, akun } = isi.rows[0];
    if (kk > 0 || akun > 0) {
      return res.status(409).json({
        success: false,
        message: `RT ${rt.rows[0].kode} masih memiliki ${kk} kartu keluarga dan ${akun} akun. `
          + 'Pindahkan atau hapus datanya lebih dulu.',
      });
    }

    await pool.query('UPDATE rt SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1', [id]);
    await logActivity(req, TIPE.DELETE, `Menghapus RT ${rt.rows[0].kode}`);
    return res.status(200).json({ success: true, message: 'RT berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}


/**
 * Rekap satu baris per RT — bahan layar Perbandingan RT dan ekspornya.
 *
 * ===================================================================
 * Kenapa ini perlu ada sendiri
 * ===================================================================
 *
 * Ketua RW yang memilih "Semua RT" sudah mendapat angka se-RW, tetapi
 * angka itu AGREGAT: satu saldo, satu jumlah warga. Untuk mengetahui RT mana
 * yang perlu perhatian — dan itulah seluruh isi pekerjaannya — ia harus
 * menekan pemilih RT satu per satu dan mengingat angkanya sendiri.
 *
 * Terukur pada dua RT: kas gabungan Rp 1.410.000 tidak memberi tahu apa pun,
 * sementara RT 001 Rp 1.250.000 dan RT 002 Rp 160.000 langsung menunjukkan
 * mana yang baru mulai. Dengan lima RT, membandingkannya dengan cara menekan
 * satu per satu sudah tidak masuk akal.
 *
 * ===================================================================
 * Kenapa satu kueri, bukan melooping endpoint yang sudah ada
 * ===================================================================
 *
 * Memanggil enam endpoint ringkasan kali jumlah RT berarti 30 perjalanan
 * jaringan untuk satu layar, dan tiap RT baru menambah enam. Semua angkanya
 * ada di basis data yang sama; menjumlahkannya di sana adalah satu perjalanan.
 *
 * Subkuerinya SENGAJA mengulang definisi yang dipakai kartu masing-masing
 * modul, dan itu risikonya nyata: bila definisi "tunggakan" berubah di
 * `bill.controller.js`, angka di sini akan diam-diam berbeda. Ditulis begitu
 * karena alternatifnya — memanggil enam pengendali dengan `req` buatan —
 * menukar risiko itu dengan ketergantungan yang jauh lebih rapuh. Yang
 * menjaganya adalah `test-isolasi-rt.js`, yang menuntut jumlah per RT sama
 * dengan jumlah tanpa pelingkupan.
 */
const KOLOM_BANDING = `
  r.id, r.kode, r.nama, r.rw_kode,
  k.nama AS ketua_nama,

  (SELECT COUNT(*)::int FROM keluarga kk
    WHERE kk.rt_id = r.id AND kk.deleted_at IS NULL) AS jumlah_kk,

  (SELECT COUNT(*)::int FROM anggota_keluarga ak
     JOIN keluarga kk2 ON kk2.id = ak.keluarga_id
    WHERE kk2.rt_id = r.id AND kk2.deleted_at IS NULL) AS jumlah_warga,

  COALESCE((SELECT SUM(CASE WHEN f.tipe = 'pemasukan' THEN f.jumlah ELSE -f.jumlah END)
              FROM finances f
             WHERE f.rt_id = r.id AND f.deleted_at IS NULL), 0)::float8 AS saldo_kas,

  COALESCE((SELECT SUM(b.nominal) FROM bills b
              JOIN keluarga kk3 ON kk3.id = b.keluarga_id
             WHERE kk3.rt_id = r.id AND b.status <> 'paid'), 0)::float8 AS tunggakan_nominal,

  (SELECT COUNT(*)::int FROM bills b2
     JOIN keluarga kk4 ON kk4.id = b2.keluarga_id
    WHERE kk4.rt_id = r.id AND b2.status <> 'paid') AS tunggakan_jumlah,

  (SELECT COUNT(*)::int FROM complaints c
    WHERE c.rt_id = r.id AND c.deleted_at IS NULL
      AND c.status NOT IN ('Selesai', 'Ditolak', 'selesai', 'disetujui')) AS pengaduan_terbuka,

  (SELECT COUNT(*)::int FROM letters l
    WHERE l.rt_id = r.id AND l.deleted_at IS NULL
      AND l.status IN ('pending', 'diproses', 'menunggu_rw')) AS surat_tertunda,

  (SELECT COUNT(*)::int FROM emergency_alerts ea
    WHERE ea.rt_id = r.id AND ea.status = 'active') AS darurat_aktif
`;

/**
 * Baris rekap untuk RT yang boleh dilihat pemanggil.
 *
 * Penyaringnya sama dengan `getRt`: peran lintas RT menerima seluruh RT dalam
 * RW-nya, peran lain hanya RT-nya sendiri. Layarnya memang ditujukan untuk
 * Ketua RW, tetapi endpoint yang membocorkan hanya karena layarnya tidak
 * dipasang di menu bukan endpoint yang dijaga.
 */
async function ambilBanding(req) {
  const params = [];
  let saring = '';
  if (!bolehLintasRt(req)) {
    params.push(req.user?.rt_id ?? null);
    saring = ' AND r.id = $1';
  }
  const hasil = await pool.query(
    `SELECT ${KOLOM_BANDING}
       FROM rt r
       LEFT JOIN users k ON k.id = r.ketua_id
      WHERE r.deleted_at IS NULL${saring}
      ORDER BY r.rw_kode, r.kode`,
    params
  );
  return hasil.rows;
}

async function getPerbandinganRt(req, res) {
  try {
    const baris = await ambilBanding(req);

    // Total se-RW dihitung dari baris yang sama, bukan lewat kueri kedua —
    // dua sumber untuk satu angka adalah dua sumber yang bisa berbeda, dan
    // layar ini justru dipakai untuk membandingkan.
    const total = baris.reduce((a, r) => ({
      jumlah_kk: a.jumlah_kk + r.jumlah_kk,
      jumlah_warga: a.jumlah_warga + r.jumlah_warga,
      saldo_kas: a.saldo_kas + r.saldo_kas,
      tunggakan_nominal: a.tunggakan_nominal + r.tunggakan_nominal,
      tunggakan_jumlah: a.tunggakan_jumlah + r.tunggakan_jumlah,
      pengaduan_terbuka: a.pengaduan_terbuka + r.pengaduan_terbuka,
      surat_tertunda: a.surat_tertunda + r.surat_tertunda,
      darurat_aktif: a.darurat_aktif + r.darurat_aktif,
    }), {
      jumlah_kk: 0, jumlah_warga: 0, saldo_kas: 0, tunggakan_nominal: 0,
      tunggakan_jumlah: 0, pengaduan_terbuka: 0, surat_tertunda: 0, darurat_aktif: 0,
    });

    return res.status(200).json({
      success: true, count: baris.length, data: baris, total,
    });
  } catch (err) {
    console.error('GetPerbandinganRt Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

const KOLOM_EKSPOR = [
  { header: 'NO', key: 'no', width: 5 },
  { header: 'RT', key: 'rt', width: 10 },
  { header: 'NAMA RT', key: 'nama', width: 26 },
  { header: 'KETUA RT', key: 'ketua', width: 24 },
  { header: 'JUMLAH KK', key: 'jumlah_kk', width: 12 },
  { header: 'JUMLAH WARGA', key: 'jumlah_warga', width: 14 },
  { header: 'SALDO KAS', key: 'saldo_kas', width: 18 },
  { header: 'TUNGGAKAN (LEMBAR)', key: 'tunggakan_jumlah', width: 20 },
  { header: 'TUNGGAKAN (RP)', key: 'tunggakan_nominal', width: 18 },
  { header: 'PENGADUAN TERBUKA', key: 'pengaduan_terbuka', width: 20 },
  { header: 'SURAT TERTUNDA', key: 'surat_tertunda', width: 18 },
  { header: 'DARURAT AKTIF', key: 'darurat_aktif', width: 16 },
];

/**
 * Rekap se-RW dalam satu berkas Excel — bahan laporan pertanggungjawaban.
 *
 * Baris TOTAL ikut ditulis, dan itu bukan kemudahan belaka: laporan RW selalu
 * dibaca sebagai "berapa seluruhnya, dan dari mana saja", jadi angka yang
 * harus dijumlahkan sendiri oleh pembacanya adalah angka yang cepat atau
 * lambat dijumlahkan keliru.
 */
async function exportPerbandinganRt(req, res) {
  try {
    const baris = await ambilBanding(req);

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Rekap RW');
    sheet.columns = KOLOM_EKSPOR;
    sheet.getRow(1).font = { bold: true };

    baris.forEach((r, i) => sheet.addRow({
      no: i + 1,
      rt: `RT ${r.kode}`,
      nama: r.nama || '-',
      ketua: r.ketua_nama || '-',
      jumlah_kk: r.jumlah_kk,
      jumlah_warga: r.jumlah_warga,
      saldo_kas: r.saldo_kas,
      tunggakan_jumlah: r.tunggakan_jumlah,
      tunggakan_nominal: r.tunggakan_nominal,
      pengaduan_terbuka: r.pengaduan_terbuka,
      surat_tertunda: r.surat_tertunda,
      darurat_aktif: r.darurat_aktif,
    }));

    const jml = (k) => baris.reduce((a, r) => a + r[k], 0);
    const totalRow = sheet.addRow({
      no: '', rt: 'TOTAL', nama: `${baris.length} RT`, ketua: '',
      jumlah_kk: jml('jumlah_kk'),
      jumlah_warga: jml('jumlah_warga'),
      saldo_kas: jml('saldo_kas'),
      tunggakan_jumlah: jml('tunggakan_jumlah'),
      tunggakan_nominal: jml('tunggakan_nominal'),
      pengaduan_terbuka: jml('pengaduan_terbuka'),
      surat_tertunda: jml('surat_tertunda'),
      darurat_aktif: jml('darurat_aktif'),
    });
    totalRow.font = { bold: true };

    const stempel = new Date().toISOString().slice(0, 10);
    res.setHeader('Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition',
      `attachment; filename=Rekap_RW_${stempel}.xlsx`);
    await workbook.xlsx.write(res);
    res.end();

    // Berkas ini memuat rekap keuangan seluruh RT. Mengunduhnya adalah
    // kejadian yang layak terlihat, sama seperti cadangan reset.
    await logActivity(req, TIPE.AKSES,
      `Mengunduh rekap perbandingan ${baris.length} RT se-RW`);
  } catch (err) {
    console.error('ExportPerbandinganRt Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Gagal membuat berkas rekap.' });
    }
  }
}

module.exports = {
  getRt, createRt, updateRt, deleteRt,
  getPerbandinganRt, exportPerbandinganRt,
};
