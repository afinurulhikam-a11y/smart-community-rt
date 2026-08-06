/**
 * Data uji lengkap untuk seluruh modul Smart Community RT.
 *
 * ===================================================================
 * Bedanya dengan seed-demo.js
 * ===================================================================
 *
 * `seed-demo.js` hanya membuat satu kartu keluarga dan tiga tagihan — cukup
 * untuk mencoba alur pembayaran, tidak cukup untuk menguji aplikasinya. Layar
 * Statistik butuh sebaran umur dan pendidikan; Kas RT butuh transaksi lintas
 * bulan supaya saldo berjalannya berarti; Peminjaman butuh pinjaman yang
 * TERLAMBAT, bukan sekadar yang sedang berjalan.
 *
 * Berkas ini mengisi setiap modul dengan data yang bentuknya menyerupai
 * keadaan sungguhan, termasuk keadaan tepi yang paling sering luput diuji:
 * tagihan menunggak beberapa bulan, peminjaman lewat tenggat, surat yang
 * ditolak, pengaduan yang belum dijawab, dan polling yang sudah ditutup.
 *
 * ===================================================================
 * Bisa dijalankan berulang
 * ===================================================================
 *
 * Setiap baris yang dibuat berkas ini ditandai `[DEMO]` pada kolom keterangan/
 * deskripsi-nya, dan NIK/no_kk-nya memakai awalan tetap. Menjalankan ulang akan
 * MENGHAPUS data demo lama lebih dulu, lalu membuatnya kembali — sehingga
 * pengujian selalu berangkat dari keadaan yang sama.
 *
 * Data yang Anda masukkan sendiri lewat aplikasi TIDAK tersentuh, karena tidak
 * membawa penanda itu.
 *
 * Pemakaian:
 *   node seed-demo-lengkap.js            # isi data demo
 *   node seed-demo-lengkap.js --hapus    # hapus data demo saja, tanpa mengisi
 *
 * Menyasar database yang sama dengan aplikasi (DATABASE_URL atau DB_* di .env).
 */
require('dotenv').config();
const bcrypt = require('bcryptjs');
const { pool } = require('./src/config/database');

// ===================================================================
// Penanda & tetapan
// ===================================================================

/** Muncul di kolom keterangan/deskripsi setiap baris buatan berkas ini. */
const TANDA = '[DEMO]';

/**
 * Awalan no_kk & NIK demo. Dipakai untuk mengenali dan menghapus ulang.
 *
 * Panjangnya dijaga tepat 16 digit seperti NIK dan nomor KK sungguhan — kolomnya
 * `varchar(16)`, dan angka yang lebih pendek akan langsung terlihat palsu di
 * layar Data Warga maupun pada berkas export.
 *
 * `3201` = kode wilayah Kabupaten Bogor, `99` menandai data uji.
 */
const AWALAN_KK = '3201990000000';   // + 3 digit urut = 16
const AWALAN_NIK = '3201991';        // + 9 digit urut = 16

/** Sandi untuk SEMUA akun demo. Sengaja seragam supaya mudah diuji. */
const SANDI_DEMO = 'Demo1234';

const TAHUN = new Date().getFullYear();
const BULAN_INI = new Date().getMonth() + 1;

const pad = (n) => String(n).padStart(2, '0');

/** "2026-08" untuk n=0, "2026-07" untuk n=1, dan seterusnya ke belakang. */
function periode(mundur) {
  const d = new Date(TAHUN, BULAN_INI - 1 - mundur, 1);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

/** Tanggal ISO n hari dari sekarang. Negatif berarti masa lalu. */
function tanggal(geser) {
  const d = new Date();
  d.setDate(d.getDate() + geser);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// ===================================================================
// Data sumber
// ===================================================================

/**
 * Enam kartu keluarga dengan komposisi berbeda-beda.
 *
 * Sebarannya disengaja: ada keluarga besar dan lajang, ada yang mengontrak,
 * dan umurnya merentang dari balita sampai lansia — supaya grafik Statistik
 * Kependudukan menampilkan sesuatu yang bisa dibaca, bukan satu batang tunggal.
 */
const KELUARGA = [
  {
    no_kk: `${AWALAN_KK}001`, kepala: 'Budi Santoso', alamat: 'Jl. Melati No. 12',
    status_rumah: 'Milik Sendiri',
    anggota: [
      { nama: 'Budi Santoso', jk: 'L', lahir: '1980-04-12', status: 'Kepala Keluarga', kerja: 'Wiraswasta', didik: 'S1', kawin: 'Kawin', hp: '081234567001' },
      { nama: 'Siti Aminah', jk: 'P', lahir: '1983-09-02', status: 'Istri', kerja: 'Ibu Rumah Tangga', didik: 'SMA', kawin: 'Kawin', hp: '081234567002' },
      { nama: 'Rizky Santoso', jk: 'L', lahir: '2010-01-20', status: 'Anak', kerja: 'Pelajar', didik: 'SD', kawin: 'Belum Kawin', hp: null },
      { nama: 'Aulia Santoso', jk: 'P', lahir: '2019-06-08', status: 'Anak', kerja: 'Belum Bekerja', didik: 'Tidak/Belum Sekolah', kawin: 'Belum Kawin', hp: null, ktp: false },
    ],
  },
  {
    no_kk: `${AWALAN_KK}002`, kepala: 'Agus Wijaya', alamat: 'Jl. Melati No. 14',
    status_rumah: 'Kontrak',
    anggota: [
      { nama: 'Agus Wijaya', jk: 'L', lahir: '1975-11-30', status: 'Kepala Keluarga', kerja: 'Karyawan Swasta', didik: 'D3', kawin: 'Kawin', hp: '081234567003' },
      { nama: 'Dewi Lestari', jk: 'P', lahir: '1978-03-17', status: 'Istri', kerja: 'Guru', didik: 'S1', kawin: 'Kawin', hp: '081234567004' },
      { nama: 'Fajar Wijaya', jk: 'L', lahir: '2003-07-25', status: 'Anak', kerja: 'Mahasiswa', didik: 'SMA', kawin: 'Belum Kawin', hp: '081234567005' },
    ],
  },
  {
    no_kk: `${AWALAN_KK}003`, kepala: 'Hendra Gunawan', alamat: 'Jl. Kenanga No. 3',
    status_rumah: 'Milik Sendiri',
    anggota: [
      { nama: 'Hendra Gunawan', jk: 'L', lahir: '1968-02-14', status: 'Kepala Keluarga', kerja: 'Pensiunan', didik: 'SMA', kawin: 'Kawin', hp: '081234567006' },
      { nama: 'Sri Rahayu', jk: 'P', lahir: '1970-08-09', status: 'Istri', kerja: 'Pedagang', didik: 'SMP', kawin: 'Kawin', hp: '081234567007' },
      { nama: 'Nurul Gunawan', jk: 'P', lahir: '1998-12-01', status: 'Anak', kerja: 'Karyawan Swasta', didik: 'S1', kawin: 'Belum Kawin', hp: '081234567008' },
      { nama: 'Bagas Gunawan', jk: 'L', lahir: '2001-05-19', status: 'Anak', kerja: 'Belum Bekerja', didik: 'SMA', kawin: 'Belum Kawin', hp: '081234567009' },
    ],
  },
  {
    no_kk: `${AWALAN_KK}004`, kepala: 'Rina Marlina', alamat: 'Jl. Kenanga No. 7',
    status_rumah: 'Milik Sendiri',
    anggota: [
      // Kepala keluarga perempuan — memastikan layar tidak mengasumsikan laki-laki.
      { nama: 'Rina Marlina', jk: 'P', lahir: '1985-10-05', status: 'Kepala Keluarga', kerja: 'Wiraswasta', didik: 'S1', kawin: 'Cerai Hidup', hp: '081234567010' },
      { nama: 'Alif Pratama', jk: 'L', lahir: '2012-03-22', status: 'Anak', kerja: 'Pelajar', didik: 'SD', kawin: 'Belum Kawin', hp: null },
    ],
  },
  {
    no_kk: `${AWALAN_KK}005`, kepala: 'Slamet Riyadi', alamat: 'Jl. Anggrek No. 21',
    status_rumah: 'Kontrak',
    anggota: [
      // Satu orang saja — kasus tepi untuk perhitungan rata-rata anggota per KK.
      { nama: 'Slamet Riyadi', jk: 'L', lahir: '1995-01-08', status: 'Kepala Keluarga', kerja: 'Buruh', didik: 'SMK', kawin: 'Belum Kawin', hp: '081234567011' },
    ],
  },
  {
    no_kk: `${AWALAN_KK}006`, kepala: 'Tuti Handayani', alamat: 'Jl. Anggrek No. 25',
    status_rumah: 'Milik Sendiri',
    anggota: [
      { nama: 'Tuti Handayani', jk: 'P', lahir: '1955-07-11', status: 'Kepala Keluarga', kerja: 'Pensiunan', didik: 'SMA', kawin: 'Cerai Mati', hp: '081234567012' },
      { nama: 'Joko Handayani', jk: 'L', lahir: '1990-09-27', status: 'Anak', kerja: 'Karyawan Swasta', didik: 'D3', kawin: 'Kawin', hp: '081234567013' },
      { nama: 'Maya Sari', jk: 'P', lahir: '1992-04-03', status: 'Menantu', kerja: 'Ibu Rumah Tangga', didik: 'SMA', kawin: 'Kawin', hp: '081234567014' },
      { nama: 'Kayla Handayani', jk: 'P', lahir: '2022-11-15', status: 'Cucu', kerja: 'Belum Bekerja', didik: 'Tidak/Belum Sekolah', kawin: 'Belum Kawin', hp: null, ktp: false },
    ],
  },
];

/**
 * Akun pengurus demo.
 *
 * Administrator yang sudah ada TIDAK disentuh. Ketiga akun ini ada supaya
 * perbedaan hak antar peran benar-benar bisa dilihat — kalau semuanya diuji
 * dengan admin, seluruh gerbang izin tidak pernah terbukti bekerja.
 */
const PENGURUS = [
  { nama: 'Ketua RT (Demo)', username: 'ketua_demo', email: 'ketua.demo@rt.local', role: 'ketua_rt', hp: '081200000001' },
  { nama: 'Sekretaris (Demo)', username: 'sekretaris_demo', email: 'sekretaris.demo@rt.local', role: 'sekretaris', hp: '081200000002' },
  { nama: 'Bendahara (Demo)', username: 'bendahara_demo', email: 'bendahara.demo@rt.local', role: 'bendahara', hp: '081200000003' },
];

const BARANG = [
  { nama: 'Tenda Terpal 4x6', kategori: 'Perlengkapan Acara', jumlah: 4, kondisi: 'Baik', lokasi: 'Gudang RT', nilai: 1500000 },
  { nama: 'Kursi Plastik', kategori: 'Perlengkapan Acara', jumlah: 120, kondisi: 'Baik', lokasi: 'Gudang RT', nilai: 45000 },
  { nama: 'Meja Lipat', kategori: 'Perlengkapan Acara', jumlah: 15, kondisi: 'Baik', lokasi: 'Gudang RT', nilai: 250000 },
  { nama: 'Sound System Portable', kategori: 'Elektronik', jumlah: 2, kondisi: 'Baik', lokasi: 'Balai RT', nilai: 3500000 },
  { nama: 'Genset 2000 Watt', kategori: 'Elektronik', jumlah: 1, kondisi: 'Perlu Perbaikan', lokasi: 'Gudang RT', nilai: 4200000 },
  { nama: 'Pompa Air Portable', kategori: 'Peralatan', jumlah: 2, kondisi: 'Baik', lokasi: 'Pos Ronda', nilai: 850000 },
  { nama: 'Tandu Lipat', kategori: 'Kesehatan', jumlah: 2, kondisi: 'Baik', lokasi: 'Balai RT', nilai: 1200000 },
  { nama: 'Alat Pemadam Api Ringan', kategori: 'Kesehatan', jumlah: 6, kondisi: 'Baik', lokasi: 'Pos Ronda', nilai: 350000 },
];

// ===================================================================
// Penghapusan data demo
// ===================================================================

/**
 * Hapus seluruh baris bertanda [DEMO].
 *
 * Urutannya anak → induk, alasannya sama dengan `reset-groups.js`: skema ini
 * punya rantai CASCADE yang berujung ke RESTRICT, jadi Postgres tidak bisa
 * diandalkan untuk mengurutkannya sendiri.
 *
 * `activity_logs` TIDAK ikut dihapus — tabel itu hanya-tambah dan database
 * akan menolaknya. Jejak audit dari sesi pengujian sebelumnya memang seharusnya
 * tetap ada.
 */
async function hapusDemo(client) {
  const langkah = [
    // --- keuangan: pembayaran dulu, baru tagihannya ---
    [`DELETE FROM finances WHERE deskripsi LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM bill_payments WHERE bill_id IN (SELECT id FROM bills WHERE keterangan LIKE $1)`, [`%${TANDA}%`]],
    [`DELETE FROM payment_transaction_bills WHERE bill_id IN (SELECT id FROM bills WHERE keterangan LIKE $1)`, [`%${TANDA}%`]],
    [`DELETE FROM bills WHERE keterangan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM bop_finances WHERE deskripsi LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM alokasi_bop WHERE keterangan LIKE $1`, [`%${TANDA}%`]],

    // --- modul lain ---
    [`DELETE FROM borrowings WHERE keterangan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM inventory WHERE keterangan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM letters WHERE keperluan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM complaints WHERE deskripsi LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM visitors WHERE detail_keperluan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM agenda WHERE deskripsi LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM announcements WHERE isi LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM bantuan_sosial WHERE keterangan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM sensor_logs WHERE unit LIKE $1`, [`%DEMO%`]],

    // polling: suara → opsi → polling
    [`DELETE FROM polling_votes WHERE polling_id IN (SELECT id FROM polling WHERE deskripsi LIKE $1)`, [`%${TANDA}%`]],
    [`DELETE FROM polling_options WHERE polling_id IN (SELECT id FROM polling WHERE deskripsi LIKE $1)`, [`%${TANDA}%`]],
    [`DELETE FROM polling WHERE deskripsi LIKE $1`, [`%${TANDA}%`]],

    // siskamling: absensi → jadwal
    [`DELETE FROM patrol_attendances WHERE catatan LIKE $1`, [`%${TANDA}%`]],
    [`DELETE FROM patrol_schedules WHERE keterangan LIKE $1`, [`%${TANDA}%`]],

    // darurat
    [`DELETE FROM emergency_alerts WHERE message LIKE $1`, [`%${TANDA}%`]],

    // --- kependudukan & akun, paling akhir karena banyak yang menunjuk ke sini ---
    [`DELETE FROM anggota_keluarga WHERE nik LIKE $1`, [`${AWALAN_NIK}%`]],
    [`DELETE FROM keluarga WHERE no_kk LIKE $1`, [`${AWALAN_KK}%`]],
    [`DELETE FROM users WHERE nik LIKE $1 OR username = ANY($2)`,
      [`${AWALAN_NIK}%`, PENGURUS.map((p) => p.username)]],
  ];

  let total = 0;
  for (const [sql, params] of langkah) {
    const r = await client.query(sql, params);
    total += r.rowCount;
  }
  return total;
}

// ===================================================================
// Pengisian
// ===================================================================

async function isiDemo(client) {
  const ringkas = {};
  const hash = await bcrypt.hash(SANDI_DEMO, 10);

  // --- Akun pengurus -----------------------------------------------
  for (const p of PENGURUS) {
    await client.query(
      `INSERT INTO users (nama, username, email, password_hash, role, no_hp, no_rt, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, '001', true)
       ON CONFLICT (username) DO NOTHING`,
      [p.nama, p.username, p.email, hash, p.role, p.hp]
    );
  }
  ringkas.pengurus = PENGURUS.length;

  // Admin yang dipakai sebagai `created_by` di seluruh data di bawah.
  const adminRes = await client.query(
    `SELECT id, nama FROM users WHERE role = 'admin' AND deleted_at IS NULL ORDER BY created_at LIMIT 1`
  );
  if (adminRes.rows.length === 0) {
    throw new Error(
      'Tidak ada akun admin di database. Jalankan `node seed-master.js` lebih dulu, '
      + 'atau nyalakan server sekali agar akun admin pertama dibuat otomatis.'
    );
  }
  const adminId = adminRes.rows[0].id;

  // --- Keluarga, anggota, dan akun warganya -------------------------
  const wargaIds = [];   // uuid akun warga, sejajar urutan KELUARGA
  const keluargaIds = [];
  let nikUrut = 1;

  for (const kk of KELUARGA) {
    const k = await client.query(
      `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, status_rumah)
       VALUES ($1, $2, $3, '001', '005', 'Sukamaju', 'Cibinong', $4) RETURNING id`,
      [kk.no_kk, kk.kepala, kk.alamat, kk.status_rumah]
    );
    const keluargaId = k.rows[0].id;
    keluargaIds.push(keluargaId);

    let nikKepala = null;
    for (const a of kk.anggota) {
      const nik = `${AWALAN_NIK}${String(nikUrut++).padStart(9, '0')}`;
      if (a.status === 'Kepala Keluarga') nikKepala = nik;

      await client.query(
        `INSERT INTO anggota_keluarga
          (keluarga_id, nik, nama, jenis_kelamin, tempat_lahir, tanggal_lahir, agama,
           status_keluarga, pekerjaan, pendidikan, status_pernikahan, no_hp, has_ktp, domisili, is_aktif)
         VALUES ($1,$2,$3,$4,'Bogor',$5,'Islam',$6,$7,$8,$9,$10,$11,'Tetap',true)`,
        [keluargaId, nik, a.nama, a.jk, a.lahir, a.status, a.kerja, a.didik, a.kawin, a.hp, a.ktp !== false]
      );
    }

    // Akun login untuk kepala keluarga. `no_kk` WAJIB terisi — tagihan disaring
    // lewat kartu keluarga, jadi akun tanpa no_kk melihat Tagihan Saya kosong.
    const u = await client.query(
      `INSERT INTO users (nama, username, email, password_hash, role, no_hp, no_kk, alamat, no_rt, nik, is_active)
       VALUES ($1, $2, $2, $3, 'warga', $4, $5, $6, '001', $2, true) RETURNING id`,
      [kk.kepala, nikKepala, hash, kk.anggota[0].hp, kk.no_kk, kk.alamat]
    );
    wargaIds.push(u.rows[0].id);
  }
  ringkas.keluarga = KELUARGA.length;
  ringkas.anggota = nikUrut - 1;
  ringkas.akun_warga = wargaIds.length;
  // NIK kepala keluarga pertama — dipakai contoh login di rangkuman akhir,
  // diambil dari yang BENAR-BENAR tersimpan, bukan disusun ulang di sana.
  ringkas._nikContoh = `${AWALAN_NIK}${String(1).padStart(9, '0')}`;

  // --- Jenis iuran --------------------------------------------------
  const jenis = await client.query(
    `SELECT id, nama_iuran, nominal_default FROM jenis_iuran WHERE is_aktif = true ORDER BY id LIMIT 1`
  );
  if (jenis.rows.length === 0) {
    throw new Error('Tabel jenis_iuran kosong. Jalankan `node seed-master.js` lebih dulu.');
  }
  const jenisIuran = jenis.rows[0];
  const nominal = Number(jenisIuran.nominal_default) || 50000;

  // --- Tagihan tiga bulan terakhir ----------------------------------
  //
  // Sebarannya disengaja: bulan terlama lunas semua, bulan tengah sebagian,
  // bulan berjalan hampir semua belum. Dengan begitu kartu "Tunggakan" dan
  // grafik ketercapaian menampilkan angka yang masuk akal, bukan 0% atau 100%.
  const polaLunas = [
    [true, true, true, true, true, true],       // 2 bulan lalu — lunas semua
    [true, true, true, false, false, true],     // 1 bulan lalu — sebagian
    [true, false, false, false, false, false],  // bulan ini — baru satu
  ];

  let jumlahTagihan = 0;
  let jumlahLunas = 0;

  for (let m = 0; m < 3; m++) {
    const bulan = periode(2 - m);
    for (let i = 0; i < keluargaIds.length; i++) {
      const b = await client.query(
        `INSERT INTO bills (keluarga_id, jenis_iuran_id, jenis_tagihan, bulan, nominal,
                            keterangan, status, created_by, jatuh_tempo)
         VALUES ($1,$2,$3,$4,$5,$6,'unpaid',$7,$8) RETURNING id`,
        [
          keluargaIds[i], jenisIuran.id, jenisIuran.nama_iuran, bulan, nominal,
          `${TANDA} Tagihan uji coba`, adminId, `${bulan}-10`,
        ]
      );
      jumlahTagihan++;

      if (!polaLunas[m][i]) continue;

      // Lunas → catat pembayaran DAN barisnya di Kas RT, persis seperti
      // catatKeKasRt() melakukannya. Kalau finances-nya dilewati, layar
      // Kas RT dan Laporan Keuangan akan berbeda dari Iuran Warga.
      const billId = b.rows[0].id;
      const invoice = `INV-DEMO-${bulan.replace('-', '')}-${i + 1}`;
      const bayar = await client.query(
        `INSERT INTO bill_payments (bill_id, user_id, jumlah_bayar, metode_bayar, invoice_number, paid_at)
         VALUES ($1,$2,$3,'tunai',$4,$5) RETURNING id`,
        [billId, wargaIds[i], nominal, invoice, `${bulan}-0${(i % 8) + 1} 09:${pad(i * 7 % 60)}:00`]
      );
      await client.query(`UPDATE bills SET status = 'lunas', user_id = $1 WHERE id = $2`, [wargaIds[i], billId]);

      await client.query(
        `INSERT INTO finances (tipe, kategori, jumlah, deskripsi, tanggal, created_by, sumber, ref_id)
         VALUES ('pemasukan', $1, $2, $3, $4, $5, 'iuran', $6)`,
        [
          jenisIuran.nama_iuran, nominal,
          `${TANDA} ${jenisIuran.nama_iuran} ${bulan} — ${KELUARGA[i].kepala}`,
          `${bulan}-0${(i % 8) + 1}`, adminId, bayar.rows[0].id,
        ]
      );
      jumlahLunas++;
    }
  }
  ringkas.tagihan = `${jumlahTagihan} (${jumlahLunas} lunas, ${jumlahTagihan - jumlahLunas} menunggak)`;

  // --- Kas RT: pemasukan & pengeluaran manual -----------------------
  const kategoriKas = await client.query(`SELECT id, nama_kategori, tipe FROM kategori_kas WHERE is_aktif = true`);
  const katIn = kategoriKas.rows.find((k) => k.tipe === 'IN');
  const katOut = kategoriKas.rows.find((k) => k.tipe === 'OUT');

  const kasManual = [
    ['pemasukan', katIn, 2500000, 'Sumbangan warga untuk perbaikan jalan gang', -75],
    ['pemasukan', katIn, 1000000, 'Donasi dari donatur untuk kegiatan 17 Agustus', -40],
    ['pengeluaran', katOut, 850000, 'Pembelian lampu jalan dan kabel', -70],
    ['pengeluaran', katOut, 1200000, 'Perbaikan saluran air depan Balai RT', -55],
    ['pengeluaran', katOut, 450000, 'Konsumsi rapat pengurus bulanan', -30],
    ['pengeluaran', katOut, 300000, 'Honor petugas kebersihan', -14],
    ['pengeluaran', katOut, 175000, 'Alat tulis dan fotokopi surat', -5],
  ];

  for (const [tipe, kat, jumlah, ket, geser] of kasManual) {
    await client.query(
      `INSERT INTO finances (tipe, kategori, kategori_id, jumlah, deskripsi, tanggal, created_by, sumber)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'manual')`,
      [tipe, kat?.nama_kategori || 'Umum', kat?.id || null, jumlah, `${TANDA} ${ket}`, tanggal(geser), adminId]
    );
  }
  ringkas.kas_manual = kasManual.length;

  // --- Dana BOP -----------------------------------------------------
  await client.query(
    `INSERT INTO alokasi_bop (tahun, termin, nominal, sumber_dana, keterangan, created_by)
     VALUES ($1, 'Tahunan', $2, 'Kelurahan', $3, $4)
     ON CONFLICT (tahun, termin) DO NOTHING`,
    [TAHUN, 12000000, `${TANDA} Alokasi BOP tahun ${TAHUN}`, adminId]
  );

  const kategoriBop = await client.query(`SELECT id, nama_kategori, tipe FROM kategori_bop WHERE is_aktif = true`);
  const bopIn = kategoriBop.rows.find((k) => k.tipe === 'IN');
  const bopOut = kategoriBop.rows.find((k) => k.tipe === 'OUT');

  const bopRows = [
    ['pemasukan', bopIn, 6000000, 'Pencairan BOP termin I', -120],
    ['pemasukan', bopIn, 6000000, 'Pencairan BOP termin II', -45],
    ['pengeluaran', bopOut, 1800000, 'ATK dan operasional sekretariat', -100],
    ['pengeluaran', bopOut, 2400000, 'Honor pengurus RT triwulan I', -85],
    ['pengeluaran', bopOut, 1500000, 'Perlengkapan Posyandu', -60],
    ['pengeluaran', bopOut, 2200000, 'Kegiatan sosial dan santunan', -20],
  ];

  for (const [tipe, kat, jumlah, ket, geser] of bopRows) {
    await client.query(
      `INSERT INTO bop_finances (tipe, kategori, kategori_id, jumlah, deskripsi, tanggal, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [tipe, kat?.nama_kategori || 'Umum', kat?.id || null, jumlah, `${TANDA} ${ket}`, tanggal(geser), adminId]
    );
  }
  ringkas.bop = `alokasi Rp12.000.000, ${bopRows.length} transaksi`;

  // --- Inventaris ---------------------------------------------------
  const barangIds = [];
  for (const b of BARANG) {
    const r = await client.query(
      `INSERT INTO inventory (nama_barang, kategori, jumlah, kondisi, lokasi, nilai_barang,
                              tanggal_perolehan, keterangan, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
      [b.nama, b.kategori, b.jumlah, b.kondisi, b.lokasi, b.nilai, tanggal(-400), `${TANDA} Aset uji coba`, adminId]
    );
    barangIds.push(r.rows[0].id);
  }
  ringkas.barang = BARANG.length;

  // Peminjaman: satu berjalan normal, satu TERLAMBAT, satu sudah kembali,
  // satu masih menunggu persetujuan. Yang terlambat penting — statusnya
  // diturunkan dari tanggal, bukan disimpan, jadi harus benar-benar lewat.
  const pinjam = [
    { barang: 1, warga: 0, jumlah: 20, pinjam: -5, rencana: 5, kembali: null, status: 'Dipinjam', ket: 'Hajatan keluarga' },
    { barang: 0, warga: 2, jumlah: 1, pinjam: -20, rencana: -6, kembali: null, status: 'Dipinjam', ket: 'Kegiatan karang taruna (TERLAMBAT)' },
    { barang: 3, warga: 1, jumlah: 1, pinjam: -30, rencana: -25, kembali: -26, status: 'Dikembalikan', ket: 'Pengajian rutin' },
    { barang: 2, warga: 5, jumlah: 4, pinjam: 0, rencana: 7, kembali: null, status: 'Menunggu Persetujuan', ket: 'Rencana arisan RT' },
  ];

  for (const p of pinjam) {
    await client.query(
      `INSERT INTO borrowings (inventory_id, user_id, nama_peminjam, jumlah, tanggal_pinjam,
                               tanggal_rencana_kembali, tanggal_kembali, status, keterangan, dicatat_oleh)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [
        barangIds[p.barang], wargaIds[p.warga], KELUARGA[p.warga].kepala, p.jumlah,
        tanggal(p.pinjam), tanggal(p.rencana), p.kembali === null ? null : tanggal(p.kembali),
        p.status, `${TANDA} ${p.ket}`, adminId,
      ]
    );
  }
  ringkas.peminjaman = `${pinjam.length} (1 terlambat, 1 menunggu persetujuan)`;

  // --- Surat menyurat -----------------------------------------------
  const surat = [
    { warga: 0, jenis: 'Surat Pengantar KTP', status: 'pending', catatan: null, geser: -2 },
    { warga: 1, jenis: 'Surat Keterangan Domisili', status: 'pending', catatan: null, geser: -1 },
    { warga: 2, jenis: 'Surat Pengantar SKCK', status: 'approved', catatan: 'Disetujui, silakan ambil di Balai RT.', geser: -10 },
    { warga: 3, jenis: 'Surat Keterangan Tidak Mampu', status: 'approved', catatan: 'Disetujui untuk keperluan beasiswa.', geser: -18 },
    { warga: 4, jenis: 'Surat Pengantar Nikah', status: 'rejected', catatan: 'Berkas belum lengkap, mohon lampirkan fotokopi KK terbaru.', geser: -7 },
  ];

  for (const s of surat) {
    await client.query(
      `INSERT INTO letters (user_id, jenis_surat, keperluan, status, approved_by, response_note,
                            tanggal_respon, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [
        wargaIds[s.warga], s.jenis, `${TANDA} Keperluan administrasi ${s.jenis.toLowerCase()}`,
        s.status, s.status === 'pending' ? null : adminId, s.catatan,
        s.status === 'pending' ? null : tanggal(s.geser + 2), tanggal(s.geser),
      ]
    );
  }
  ringkas.surat = `${surat.length} (2 menunggu, 2 disetujui, 1 ditolak)`;

  // --- Pengaduan ----------------------------------------------------
  const aduan = [
    { warga: 0, judul: 'Lampu jalan mati di Gang Melati', kat: 'Infrastruktur', status: 'Menunggu', resp: null, geser: -1 },
    { warga: 3, judul: 'Sampah menumpuk di TPS belakang', kat: 'Kebersihan', status: 'Menunggu', resp: null, geser: -3 },
    { warga: 1, judul: 'Saluran air tersumbat saat hujan', kat: 'Infrastruktur', status: 'Diproses', resp: 'Sudah dijadwalkan kerja bakti Minggu depan.', geser: -8 },
    { warga: 2, judul: 'Kendaraan parkir menghalangi jalan', kat: 'Ketertiban', status: 'Diproses', resp: 'Sudah ditegur, akan dipantau seminggu ke depan.', geser: -12 },
    { warga: 5, judul: 'Suara bising renovasi di malam hari', kat: 'Ketertiban', status: 'Selesai', resp: 'Sudah dimediasi, renovasi dibatasi sampai pukul 17.00.', geser: -25 },
  ];

  for (let i = 0; i < aduan.length; i++) {
    const a = aduan[i];
    await client.query(
      `INSERT INTO complaints (kode_tiket, user_id, judul, deskripsi, kategori, status,
                               response, responded_by, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [
        `TKT-DEMO-${String(i + 1).padStart(3, '0')}`, wargaIds[a.warga], a.judul,
        `${TANDA} ${a.judul} — dilaporkan warga untuk pengujian.`, a.kat, a.status,
        a.resp, a.resp ? adminId : null, tanggal(a.geser),
      ]
    );
  }
  ringkas.pengaduan = `${aduan.length} (2 menunggu, 2 diproses, 1 selesai)`;

  // --- E-Visitor ----------------------------------------------------
  const tamu = [
    { nama: 'Andi Kurniawan', hp: '081300000001', blok: 'Jl. Melati No. 12', tujuanHp: '081234567001', tipe: 'Kunjungan', plat: 'B 1234 XYZ', kendaraan: 'Mobil', masuk: -0.2, keluar: null },
    { nama: 'Kurir JNE', hp: '081300000002', blok: 'Jl. Kenanga No. 3', tujuanHp: '081234567006', tipe: 'Pengiriman', plat: 'B 5566 KL', kendaraan: 'Motor', masuk: -0.5, keluar: null },
    { nama: 'Siti Nurjanah', hp: '081300000003', blok: 'Jl. Anggrek No. 25', tujuanHp: '081234567012', tipe: 'Menginap', plat: 'D 7788 MN', kendaraan: 'Mobil', masuk: -2, keluar: null },
    { nama: 'Teknisi PLN', hp: '081300000004', blok: 'Jl. Melati No. 14', tujuanHp: '081234567003', tipe: 'Kunjungan', plat: 'B 9900 OP', kendaraan: 'Motor', masuk: -1, keluar: -0.9 },
    { nama: 'Rudi Hartono', hp: '081300000005', blok: 'Jl. Kenanga No. 7', tujuanHp: '081234567010', tipe: 'Kunjungan', plat: 'F 2233 QR', kendaraan: 'Motor', masuk: -3, keluar: -2.8 },
    { nama: 'Kurir Shopee', hp: '081300000006', blok: 'Jl. Anggrek No. 21', tujuanHp: '081234567011', tipe: 'Pengiriman', plat: 'B 4455 ST', kendaraan: 'Motor', masuk: -5, keluar: -4.9 },
  ];

  for (const t of tamu) {
    const masuk = new Date();
    masuk.setHours(masuk.getHours() + Math.round(t.masuk * 24));
    const keluar = t.keluar === null ? null : new Date(Date.now() + t.keluar * 24 * 3600 * 1000);

    await client.query(
      `INSERT INTO visitors (nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan,
                             detail_keperluan, plat_nomor, jenis_kendaraan, jam_masuk, jam_keluar,
                             status, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [
        t.nama, t.hp, t.blok, t.tujuanHp, t.tipe, `${TANDA} ${t.tipe} ke ${t.blok}`,
        t.plat, t.kendaraan, masuk.toISOString(), keluar ? keluar.toISOString() : null,
        keluar ? 'Checkout' : 'Di Dalam', adminId,
      ]
    );
  }
  ringkas.tamu = `${tamu.length} (3 masih di dalam)`;

  // --- Agenda & pengumuman ------------------------------------------
  const agenda = [
    { judul: 'Kerja Bakti Bulanan', tipe: 'Kegiatan', geser: 5, mulai: '07:00', selesai: '10:00', lokasi: 'Sepanjang Jl. Melati', status: 'Akan Datang' },
    { judul: 'Rapat Pengurus RT', tipe: 'Rapat', geser: 12, mulai: '19:30', selesai: '21:00', lokasi: 'Balai RT', status: 'Akan Datang' },
    { judul: 'Posyandu Balita', tipe: 'Kegiatan', geser: -8, mulai: '08:00', selesai: '11:00', lokasi: 'Balai RT', status: 'Selesai' },
    { judul: 'Musyawarah Warga Tahunan', tipe: 'Rapat', geser: -30, mulai: '19:00', selesai: '22:00', lokasi: 'Balai RT', status: 'Selesai' },
  ];

  for (const a of agenda) {
    await client.query(
      `INSERT INTO agenda (judul, deskripsi, tipe, tanggal, waktu_mulai, waktu_selesai, lokasi, status, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [a.judul, `${TANDA} ${a.judul} — agenda uji coba.`, a.tipe, tanggal(a.geser), a.mulai, a.selesai, a.lokasi, a.status, adminId]
    );
  }

  const pengumuman = [
    { judul: 'Jadwal Pemadaman Listrik', kat: 'Penting', status: 'published', isi: 'PLN memberitahukan pemadaman terjadwal Sabtu pukul 09.00–15.00 untuk pemeliharaan jaringan.' },
    { judul: 'Iuran Bulan Ini Sudah Dapat Dibayar', kat: 'Keuangan', status: 'published', isi: 'Pembayaran dapat dilakukan tunai kepada Bendahara atau lewat menu Tagihan Saya di aplikasi.' },
    { judul: 'Peringatan Musim Hujan', kat: 'Umum', status: 'published', isi: 'Mohon warga membersihkan saluran air di depan rumah masing-masing untuk mencegah genangan.' },
    { judul: 'Draf Rencana Perbaikan Pos Ronda', kat: 'Umum', status: 'draft', isi: 'Rancangan anggaran perbaikan pos ronda masih disusun dan belum dipublikasikan.' },
  ];

  for (const p of pengumuman) {
    await client.query(
      `INSERT INTO announcements (judul, isi, kategori, status, created_by)
       VALUES ($1,$2,$3,$4,$5)`,
      [p.judul, `${TANDA} ${p.isi}`, p.kat, p.status, adminId]
    );
  }
  ringkas.agenda = `${agenda.length} agenda, ${pengumuman.length} pengumuman (1 draf)`;

  // --- Polling ------------------------------------------------------
  // Satu aktif dengan suara masuk, satu sudah ditutup. Yang aktif memakai
  // suara dari sebagian warga saja, supaya tombol "Beri Suara" masih bisa
  // dicoba dengan akun yang belum memilih.
  const pollAktif = await client.query(
    `INSERT INTO polling (judul, deskripsi, status, tanggal_mulai, tanggal_selesai, created_by)
     VALUES ($1,$2,'Aktif',$3,$4,$5) RETURNING id`,
    [
      'Jadwal Kerja Bakti Berikutnya',
      `${TANDA} Menentukan waktu kerja bakti yang paling banyak bisa dihadiri warga.`,
      tanggal(-3), tanggal(11), adminId,
    ]
  );
  const opsiAktif = [];
  for (const label of ['Minggu pagi (07.00)', 'Sabtu sore (16.00)', 'Minggu sore (16.00)']) {
    const o = await client.query(
      `INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1,$2,0) RETURNING id`,
      [pollAktif.rows[0].id, label]
    );
    opsiAktif.push(o.rows[0].id);
  }
  // Tiga warga pertama sudah memilih; tiga sisanya belum.
  const pilihan = [0, 0, 1];
  for (let i = 0; i < pilihan.length; i++) {
    await client.query(
      `INSERT INTO polling_votes (polling_id, option_id, user_id) VALUES ($1,$2,$3)`,
      [pollAktif.rows[0].id, opsiAktif[pilihan[i]], wargaIds[i]]
    );
    await client.query(`UPDATE polling_options SET vote_count = vote_count + 1 WHERE id = $1`, [opsiAktif[pilihan[i]]]);
  }

  const pollTutup = await client.query(
    `INSERT INTO polling (judul, deskripsi, status, tanggal_mulai, tanggal_selesai, created_by)
     VALUES ($1,$2,'Ditutup',$3,$4,$5) RETURNING id`,
    [
      'Warna Cat Pos Ronda',
      `${TANDA} Pemilihan warna cat untuk pos ronda yang sudah selesai dilaksanakan.`,
      tanggal(-40), tanggal(-25), adminId,
    ]
  );
  for (const [label, suara] of [['Hijau', 4], ['Biru', 2], ['Putih', 1]]) {
    await client.query(
      `INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1,$2,$3)`,
      [pollTutup.rows[0].id, label, suara]
    );
  }
  ringkas.polling = '2 (1 aktif dengan 3 suara, 1 ditutup)';

  // --- Bantuan sosial -----------------------------------------------
  const bansos = [
    { warga: 4, jenis: 'PKH', nominal: 750000, status: 'Aktif' },
    { warga: 5, jenis: 'BLT Dana Desa', nominal: 300000, status: 'Aktif' },
    { warga: 3, jenis: 'Bantuan Pangan Non Tunai', nominal: 200000, status: 'Aktif' },
    { warga: 2, jenis: 'PKH', nominal: 750000, status: 'Selesai' },
  ];

  for (const b of bansos) {
    await client.query(
      `INSERT INTO bantuan_sosial (user_id, jenis_bantuan, tahun, nominal, status, keterangan, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [wargaIds[b.warga], b.jenis, TAHUN, b.nominal, b.status, `${TANDA} Penerima uji coba`, adminId]
    );
  }
  ringkas.bantuan_sosial = bansos.length;

  // --- Siskamling ---------------------------------------------------
  const hariNama = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
  const jadwalIds = [];

  for (let g = -4; g <= 4; g += 2) {
    const tgl = tanggal(g);
    const hari = hariNama[new Date(tgl + 'T00:00:00').getDay()];
    const petugas = [
      KELUARGA[(g + 4) % 6].kepala,
      KELUARGA[(g + 5) % 6].kepala,
    ].join(', ');

    const j = await client.query(
      `INSERT INTO patrol_schedules (hari, tanggal, shift, petugas_warga, keterangan, created_by)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
      [hari, tgl, 'Shift Malam (20:00 - 04:00)', petugas, `${TANDA} Jadwal ronda uji coba`, adminId]
    );
    jadwalIds.push({ id: j.rows[0].id, tgl, geser: g });
  }

  // Absensi hanya untuk jadwal yang sudah lewat. Yang paling lama sudah
  // selesai tugas, yang terakhir masih "Aktif Ronda" — dan indeks parsial
  // patrol_absensi_aktif_uniq hanya mengizinkan SATU absensi terbuka per
  // petugas per hari, jadi tanggalnya harus berbeda-beda.
  let jumlahAbsen = 0;
  for (const j of jadwalIds.filter((x) => x.geser < 0)) {
    const selesai = j.geser <= -3;
    await client.query(
      `INSERT INTO patrol_attendances (schedule_id, user_id, nama_petugas, tanggal, tipe_absen,
                                       waktu_masuk, waktu_pulang, lokasi_pos, status, catatan)
       VALUES ($1,$2,$3,$4,'Masuk',$5,$6,'Pos Ronda Utama',$7,$8)`,
      [
        j.id, wargaIds[jumlahAbsen % wargaIds.length], KELUARGA[jumlahAbsen % 6].kepala, j.tgl,
        `${j.tgl} 20:05:00`, selesai ? `${j.tgl} 23:58:00` : null,
        selesai ? 'Selesai Tugas' : 'Aktif Ronda',
        `${TANDA} Absensi ronda uji coba`,
      ]
    );
    jumlahAbsen++;
  }
  ringkas.siskamling = `${jadwalIds.length} jadwal, ${jumlahAbsen} absensi`;

  // --- Riwayat darurat ----------------------------------------------
  // Keduanya sudah diselesaikan. Alarm AKTIF sengaja tidak dibuat: ia akan
  // memunculkan popup darurat di setiap layar begitu aplikasi dibuka.
  for (const [warga, pesan, geser] of [
    [0, 'Ada orang tidak dikenal berusaha masuk pekarangan', -6],
    [3, 'Kebakaran kecil di dapur, sudah tertangani', -20],
  ]) {
    await client.query(
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude, status,
                                     dismissed_by, dismissed_at, created_at)
       VALUES ($1,$2,-6.4817,106.8340,'dismissed',$3,$4,$5)`,
      [wargaIds[warga], `${TANDA} ${pesan}`, adminId, tanggal(geser), tanggal(geser)]
    );
  }
  ringkas.darurat = '2 (keduanya sudah diselesaikan)';

  // --- Sensor IoT ---------------------------------------------------
  const sensor = [];
  for (let jam = 23; jam >= 0; jam -= 3) {
    const t = new Date();
    t.setHours(t.getHours() - jam);
    sensor.push(['suhu', (27 + Math.sin(jam) * 3).toFixed(1), '°C DEMO', t]);
    sensor.push(['kelembaban', (70 + Math.cos(jam) * 8).toFixed(1), '% DEMO', t]);
  }
  for (const [tipe, nilai, unit, waktu] of sensor) {
    await client.query(
      `INSERT INTO sensor_logs (sensor_type, value, unit, timestamp) VALUES ($1,$2,$3,$4)`,
      [tipe, nilai, unit, waktu.toISOString()]
    );
  }
  ringkas.sensor = `${sensor.length} pembacaan (24 jam terakhir)`;

  return ringkas;
}

// ===================================================================
// Penggerak
// ===================================================================

async function jalankan() {
  const hanyaHapus = process.argv.includes('--hapus');
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const dihapus = await hapusDemo(client);
    if (dihapus > 0) {
      console.log(`  🧹 ${dihapus} baris data demo lama dibersihkan.`);
    }

    if (hanyaHapus) {
      await client.query('COMMIT');
      console.log('\n✅ Data demo dihapus. Data yang Anda masukkan sendiri tidak tersentuh.\n');
      return;
    }

    const ringkas = await isiDemo(client);
    await client.query('COMMIT');

    // Diambil dari hasil pengisian, bukan disusun ulang di sini — kalau pola
    // NIK-nya berubah suatu saat, contoh login di bawah ikut berubah sendiri
    // alih-alih diam-diam menunjukkan nomor yang tidak ada.
    const nikContoh = ringkas._nikContoh;
    delete ringkas._nikContoh;

    console.log('\n✅ Data demo siap dipakai.\n');
    console.log('   ── Isi ─────────────────────────────────────────');
    for (const [k, v] of Object.entries(ringkas)) {
      console.log(`   ${k.padEnd(16)} : ${v}`);
    }

    console.log('\n   ── Akun untuk pengujian ────────────────────────');
    console.log(`   Administrator   : akun admin Anda yang sudah ada (tidak diubah)`);
    for (const p of PENGURUS) {
      console.log(`   ${p.role.padEnd(15)} : ${p.username}  /  ${SANDI_DEMO}`);
    }
    console.log(`   warga           : NIK kepala keluarga  /  ${SANDI_DEMO}`);
    console.log(`   contoh warga    : ${nikContoh}  (${KELUARGA[0].kepala})`);

    console.log('\n   ── Yang sengaja dibuat tidak rapi ──────────────');
    console.log('   • 1 peminjaman LEWAT TENGGAT — menguji status "Terlambat"');
    console.log('   • Tunggakan menumpuk di bulan berjalan — kartu tunggakan terisi');
    console.log('   • 1 surat DITOLAK dan 1 pengumuman masih DRAF');
    console.log('   • 3 tamu masih berstatus "Di Dalam"');
    console.log('   • 1 absensi ronda masih "Aktif Ronda" (belum absen pulang)');
    console.log('   • Belanja BOP di bawah pagu — sisa pagu masih positif\n');
    console.log('   Hapus lagi kapan pun dengan:  node seed-demo-lengkap.js --hapus\n');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Gagal mengisi data demo:', err.message);
    console.error('   Tidak ada perubahan yang tersimpan.\n');
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

jalankan();
