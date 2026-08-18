require('dotenv').config();
const { assertCanRunDestructive } = require('../../src/config/db-guard');
assertCanRunDestructive('seed-demo');

const bcrypt = require('bcryptjs');
const { pool } = require('../../src/config/database');

/**
 * Data contoh untuk mencoba alur aplikasi, terutama pembayaran iuran.
 *
 * TERPISAH dari `seed-master.js` dengan sengaja. `seed-master` mengisi hal yang
 * memang dibutuhkan setiap pemasangan — menu, hak akses, master, akun admin.
 * Berkas ini mengisi data KARANGAN, dan tidak boleh ikut terpasang diam-diam
 * di lingkungan sungguhan.
 *
 * Yang dibuat:
 *   - satu kartu keluarga beserta tiga anggotanya
 *   - akun login warga yang TERHUBUNG ke kartu keluarga itu lewat no_kk
 *   - tagihan iuran tiga bulan terakhir, semuanya belum lunas
 *
 * Hubungan lewat `no_kk` itu yang menentukan: `bills` disaring dengan
 * `keluarga.no_kk = users.no_kk`, jadi tanpa itu daftar tagihan warga kosong
 * walau tagihannya ada.
 *
 * Aman dijalankan berulang: kartu keluarga dikenali dari no_kk, dan tagihan
 * dijaga indeks `bills_kk_jenis_bulan_uniq`.
 *
 * Menghapusnya: jalankan Reset Sistem, atau `node kosongkan-data.js`.
 */

const NO_KK = '3318000000009001';
const KEPALA = 'Budi Santoso';

/** Akun yang sudah dikenal dari seed-master, tinggal dihubungkan ke KK ini. */
const EMAIL_WARGA = 'warga@example.com';
const PASSWORD_WARGA = 'warga123';

// `jenis_kelamin` bertipe varchar(1) dan layar Statistik menghitungnya dengan
// `= 'L'` / `= 'P'` — menulis "Laki-laki" akan ditolak database sekaligus
// membuat grafik demografi tidak menghitung orang ini.
const ANGGOTA = [
  {
    nik: '3318000000009001', nama: KEPALA, jenis_kelamin: 'L',
    status_keluarga: 'Kepala Keluarga', tanggal_lahir: '1985-04-12',
    agama: 'Islam', pendidikan: 'S1', pekerjaan: 'Wiraswasta',
    status_pernikahan: 'Kawin', no_hp: '081234567890',
  },
  {
    nik: '3318000000009002', nama: 'Siti Rahayu', jenis_kelamin: 'P',
    status_keluarga: 'Istri', tanggal_lahir: '1988-09-03',
    agama: 'Islam', pendidikan: 'SMA', pekerjaan: 'Ibu Rumah Tangga',
    status_pernikahan: 'Kawin', no_hp: '081234567891',
  },
  {
    nik: '3318000000009003', nama: 'Andi Santoso', jenis_kelamin: 'L',
    status_keluarga: 'Anak', tanggal_lahir: '2014-01-20',
    agama: 'Islam', pendidikan: 'SD', pekerjaan: 'Pelajar',
    status_pernikahan: 'Belum Kawin', no_hp: null,
  },
];

/** Tiga bulan terakhir termasuk bulan berjalan, format YYYY-MM. */
function bulanTerakhir(n) {
  const hasil = [];
  const now = new Date();
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    hasil.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
  }
  return hasil;
}

async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const laporan = [];

    // --- Kartu keluarga ----------------------------------------------------
    let kk = await client.query('SELECT id FROM keluarga WHERE no_kk = $1', [NO_KK]);
    if (kk.rowCount === 0) {
      kk = await client.query(
        `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, status_rumah)
         VALUES ($1, $2, 'Jl. Melati No. 12', '001', '005', 'Sukamaju', 'Cilodong', 'Milik Sendiri')
         RETURNING id`,
        [NO_KK, KEPALA]
      );
      laporan.push(`kartu keluarga ${NO_KK} dibuat`);
    } else {
      laporan.push(`kartu keluarga ${NO_KK} sudah ada`);
    }
    const keluargaId = kk.rows[0].id;

    // --- Anggota keluarga --------------------------------------------------
    let anggotaBaru = 0;
    for (const a of ANGGOTA) {
      const ada = await client.query('SELECT 1 FROM anggota_keluarga WHERE nik = $1', [a.nik]);
      if (ada.rowCount > 0) continue;
      await client.query(
        `INSERT INTO anggota_keluarga
           (keluarga_id, nik, nama, jenis_kelamin, tanggal_lahir, agama, status_keluarga,
            pekerjaan, pendidikan, status_pernikahan, no_hp, domisili, is_aktif, has_ktp)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'Dalam RT',true,$12)`,
        [keluargaId, a.nik, a.nama, a.jenis_kelamin, a.tanggal_lahir, a.agama,
          a.status_keluarga, a.pekerjaan, a.pendidikan, a.status_pernikahan, a.no_hp,
          // Anak di bawah 17 tahun belum punya KTP — dipakai layar Statistik.
          a.status_keluarga !== 'Anak']
      );
      anggotaBaru++;
    }
    laporan.push(`${anggotaBaru} anggota keluarga ditambahkan (dari ${ANGGOTA.length})`);

    // --- Hubungkan akun warga ke kartu keluarga ----------------------------
    // Inilah yang membuat Tagihan Saya berisi: tagihan disaring lewat no_kk.
    const akun = await client.query(
      'SELECT id, no_kk, username FROM users WHERE email = $1',
      [EMAIL_WARGA]
    );
    if (akun.rowCount === 0) {
      const hash = await bcrypt.hash(PASSWORD_WARGA, 10);
      await client.query(
        `INSERT INTO users (nama, email, username, password_hash, role, is_active, no_kk, nik)
         VALUES ($1, $2, $2, $3, 'warga', true, $4, $5)`,
        ['Warga Demo', EMAIL_WARGA, hash, NO_KK, ANGGOTA[0].nik]
      );
      laporan.push(`akun ${EMAIL_WARGA} dibuat dan dihubungkan ke KK`);
    } else {
      // Selalu perbaiki, bukan hanya saat no_kk berbeda.
      //
      // Versi sebelumnya melewatkan UPDATE begitu no_kk sudah cocok, sehingga
      // akun warisan seed lama yang `username`-nya NULL tidak pernah terisi —
      // padahal desainnya menyimpan NIK di kolom itu, dan `login` mencocokkan
      // `email = $1 OR username = $1`. COALESCE menjaga nilai yang sudah ada
      // supaya jalannya tetap aman diulang.
      const r = await client.query(
        `UPDATE users
            SET no_kk    = $1,
                nik      = COALESCE(nik, $2),
                username = COALESCE(username, $3)
          WHERE id = $4
            AND (no_kk IS DISTINCT FROM $1 OR username IS NULL OR nik IS NULL)`,
        [NO_KK, ANGGOTA[0].nik, EMAIL_WARGA, akun.rows[0].id]
      );
      laporan.push(
        r.rowCount > 0
          ? `akun ${EMAIL_WARGA} dirapikan (KK ${NO_KK}, username terisi)`
          : `akun ${EMAIL_WARGA} sudah terhubung ke KK`
      );
    }

    // --- Tagihan -----------------------------------------------------------
    const jenis = await client.query(
      'SELECT id, nama_iuran, nominal_default FROM jenis_iuran WHERE is_aktif ORDER BY id LIMIT 1'
    );
    if (jenis.rowCount === 0) {
      throw new Error('Belum ada jenis iuran. Jalankan `node seed-master.js` lebih dulu.');
    }
    const ji = jenis.rows[0];

    let tagihanBaru = 0;
    for (const bulan of bulanTerakhir(3)) {
      // Jatuh tempo dihitung di sini, bukan dirangkai di SQL: memakai
      // parameter yang sama dua kali membuat Postgres gagal menyimpulkan
      // tipenya ("inconsistent types deduced for parameter").
      const jatuhTempo = `${bulan}-20`;
      const r = await client.query(
        `INSERT INTO bills (jenis_tagihan, bulan, nominal, status, keluarga_id, jenis_iuran_id, jatuh_tempo)
         VALUES ($1, $2, $3, 'unpaid', $4, $5, $6)
         ON CONFLICT (keluarga_id, jenis_iuran_id, bulan) WHERE keluarga_id IS NOT NULL
         DO NOTHING RETURNING id`,
        [ji.nama_iuran, bulan, ji.nominal_default, keluargaId, ji.id, jatuhTempo]
      );
      tagihanBaru += r.rowCount;
    }
    laporan.push(`${tagihanBaru} tagihan dibuat (${bulanTerakhir(3).join(', ')})`);

    await client.query('COMMIT');

    // --- Ringkasan ---------------------------------------------------------
    const belum = await pool.query(
      `SELECT b.bulan, b.nominal FROM bills b
       WHERE b.keluarga_id = $1 AND b.status = 'unpaid' ORDER BY b.bulan`,
      [keluargaId]
    );
    const total = belum.rows.reduce((s, r) => s + Number(r.nominal), 0);

    console.log('Data demo siap:\n');
    for (const l of laporan) console.log(`  - ${l}`);
    console.log('\n  Login warga:');
    console.log(`    ${EMAIL_WARGA} / ${PASSWORD_WARGA}`);
    console.log(`\n  Tagihan belum lunas: ${belum.rowCount} (total Rp ${total.toLocaleString('id-ID')})`);
    for (const r of belum.rows) {
      console.log(`    ${r.bulan}  Rp ${Number(r.nominal).toLocaleString('id-ID')}`);
    }
    console.log('\n  Buka menu "Tagihan Saya", centang tagihan, lalu tekan Bayar Online.');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed demo gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
