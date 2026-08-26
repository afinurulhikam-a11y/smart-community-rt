/**
 * Data demo untuk RT KEDUA — pembuktian isolasi antar-RT.
 *
 * ===================================================================
 * Kenapa berkas terpisah, bukan menyunting seed-demo-lengkap.js
 * ===================================================================
 *
 * Berkas itu 794 baris dan menanam '001' di setiap INSERT-nya. Mengubahnya
 * menjadi dua RT berarti membongkar hampir seluruh isinya, dan yang dipertaruhkan
 * adalah satu-satunya jalur data demo yang selama ini bekerja.
 *
 * Berkas ini menambah RT kedua DI ATAS data yang sudah ada, tanpa menyentuh
 * satu baris pun milik RT pertama. Aman dijalankan berulang, dan bisa dihapus
 * kembali dengan `--hapus`.
 *
 * ===================================================================
 * Kenapa ketua RW tetap punya rt_id
 * ===================================================================
 *
 * Secara jabatan ia milik RW, bukan salah satu RT. Tetapi `users.rt_id` punya
 * kunci asing dan dipakai sebagai cadangan oleh pemicu `isi_rt_id`, jadi
 * mengosongkannya akan membuat setiap baris yang ia buat lahir tanpa RT.
 *
 * Nilainya diisi RT pertama dan TIDAK membatasi apa pun: `rtAktif()` di
 * `lingkup-rt.js` mengabaikan `rt_id` untuk peran lintas RT dan mengikuti
 * `?rt=` sebagai gantinya. Jadi kolom itu di sini hanya berarti "asal", bukan
 * "batas".
 *
 *   node database/seeds/seed-demo-rt2.js
 *   node database/seeds/seed-demo-rt2.js --hapus
 */
require('dotenv').config();
const { assertCanRunTest } = require('../../src/config/db-guard');
assertCanRunTest('seed-demo-rt2');

const bcrypt = require('bcryptjs');
const { pool } = require('../../src/config/database');
const { siapkanMasterRt } = require('../../src/services/master-rt.service');

const KODE_RT2 = '002';
const SANDI = 'demo123';

/** Ditandai supaya `--hapus` tahu persis mana yang boleh dibuang. */
const TANDA = 'DEMO-RT2';

const KELUARGA_RT2 = [
  { no_kk: '3201990002000001', kepala: 'Hendra Wijaya', alamat: 'Jl. Kenanga No. 4',
    anggota: ['Hendra Wijaya', 'Sri Handayani', 'Bagas Wijaya'] },
  { no_kk: '3201990002000002', kepala: 'Rina Marlina', alamat: 'Jl. Kenanga No. 9',
    anggota: ['Rina Marlina', 'Doni Saputra'] },
];

async function hapus(client) {
  // Urutannya anak lebih dulu, sama seperti reset-groups.js: `keluarga`
  // meng-cascade ke `bills`, dan cascade itu ditolak `bill_payments`.
  const rt = await client.query('SELECT id FROM rt WHERE kode = $1', [KODE_RT2]);
  if (!rt.rows.length) return 'RT 002 tidak ada, tidak ada yang dihapus';
  const id = rt.rows[0].id;

  await client.query(`DELETE FROM complaints WHERE rt_id = $1 AND judul LIKE '%${TANDA}%'`, [id]);
  await client.query(`DELETE FROM announcements WHERE rt_id = $1 AND judul LIKE '%${TANDA}%'`, [id]);
  await client.query(`DELETE FROM finances WHERE rt_id = $1 AND deskripsi LIKE '%${TANDA}%'`, [id]);
  await client.query(
    'DELETE FROM anggota_keluarga WHERE keluarga_id IN (SELECT id FROM keluarga WHERE rt_id = $1)', [id]);
  await client.query('DELETE FROM keluarga WHERE rt_id = $1', [id]);
  await client.query("DELETE FROM users WHERE rt_id = $1 AND username LIKE 'demo_%'", [id]);
  await client.query("UPDATE users SET rt_id = NULL WHERE username = 'ketuarw'");
  await client.query("DELETE FROM users WHERE username = 'ketuarw'");
  await client.query('DELETE FROM rt WHERE id = $1', [id]);
  return 'RT 002 beserta seluruh data demonya dihapus';
}

async function isi(client) {
  const ringkas = {};
  const hash = await bcrypt.hash(SANDI, 10);

  const rt1 = await client.query(
    'SELECT id, rw_kode FROM rt WHERE deleted_at IS NULL ORDER BY kode LIMIT 1'
  );
  if (!rt1.rows.length) throw new Error('Belum ada RT sama sekali — jalankan seed-master lebih dulu.');
  const RW = rt1.rows[0].rw_kode;

  // --- RT kedua ------------------------------------------------------
  const rt2 = await client.query(
    `INSERT INTO rt (kode, nama, rw_kode, alamat_sekretariat)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT DO NOTHING
     RETURNING id`,
    [KODE_RT2, 'RT 002 Kenanga', RW, 'Balai Warga Jl. Kenanga No. 1']
  );
  const idRt2 = rt2.rows[0]?.id
    ?? (await client.query('SELECT id FROM rt WHERE kode = $1 AND rw_kode = $2', [KODE_RT2, RW])).rows[0].id;
  ringkas['RT'] = `${KODE_RT2} pada RW ${RW}`;

  // Master milik RT kedua. Sejak v45 tiap RT punya salinannya sendiri, dan
  // seed ini membuat RT-nya lewat SQL langsung — bukan lewat `createRt`, yang
  // sudah menyiapkannya. Tanpa baris ini, pemasangan dari nol menghasilkan RT
  // 002 yang dropdown Iuran dan Kas RT-nya kosong: tidak ada galat, hanya
  // Generate Tagihan yang tidak punya jenis untuk dipilih.
  const master = await siapkanMasterRt(client, idRt2);
  ringkas['master RT 002'] = `${master.jenis_iuran} jenis iuran, `
    + `${master.kategori_kas} kategori kas, ${master.kategori_bop} kategori BOP`;

  // --- Ketua RW ------------------------------------------------------
  await client.query(
    `INSERT INTO users (nama, username, email, password_hash, role, no_rt, rt_id, is_active)
     VALUES ($1, 'ketuarw', 'ketuarw@example.com', $2, 'ketua_rw', $3, $4, true)
     ON CONFLICT (username) DO UPDATE SET
       password_hash = EXCLUDED.password_hash,
       role = EXCLUDED.role,
       rt_id = EXCLUDED.rt_id`,
    [`Ketua RW ${RW}`, hash, rt1.rows[0].id ? null : null, rt1.rows[0].id]
  );
  ringkas['Ketua RW'] = `ketuarw / ${SANDI}`;

  // --- Ketua RT 002 --------------------------------------------------
  await client.query(
    `INSERT INTO users (nama, username, email, password_hash, role, no_rt, rt_id, is_active)
     VALUES ($1, 'demo_ketua_rt2', 'ketuart2@example.com', $2, 'ketua_rt', $3, $4, true)
     ON CONFLICT (username) DO UPDATE SET
       password_hash = EXCLUDED.password_hash, rt_id = EXCLUDED.rt_id`,
    ['Ketua RT 002', hash, KODE_RT2, idRt2]
  );
  const ketua2 = await client.query("SELECT id FROM users WHERE username = 'demo_ketua_rt2'");
  const idKetua2 = ketua2.rows[0].id;
  ringkas['Ketua RT 002'] = `demo_ketua_rt2 / ${SANDI}`;

  // --- Kartu keluarga dan anggotanya ---------------------------------
  let jumlahAnggota = 0;
  for (const kk of KELUARGA_RT2) {
    const k = await client.query(
      `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, kelurahan, kecamatan, rt_id)
       VALUES ($1, $2, $3, $4, $5, 'Sukamaju', 'Cibinong', $6)
       ON CONFLICT DO NOTHING RETURNING id`,
      [kk.no_kk, kk.kepala, kk.alamat, KODE_RT2, RW, idRt2]
    );
    const idKk = k.rows[0]?.id
      ?? (await client.query('SELECT id FROM keluarga WHERE no_kk = $1', [kk.no_kk])).rows[0].id;

    for (let i = 0; i < kk.anggota.length; i++) {
      const ada = await client.query(
        'SELECT 1 FROM anggota_keluarga WHERE keluarga_id = $1 AND nama = $2', [idKk, kk.anggota[i]]);
      if (ada.rows.length) continue;
      await client.query(
        `INSERT INTO anggota_keluarga (keluarga_id, nama, jenis_kelamin, status_keluarga, is_aktif)
         VALUES ($1, $2, $3, $4, true)`,
        [idKk, kk.anggota[i], i === 1 ? 'P' : 'L',
          i === 0 ? 'Kepala Keluarga' : (i === 1 ? 'Istri' : 'Anak')]
      );
      jumlahAnggota++;
    }
  }
  ringkas['Kartu keluarga'] = `${KELUARGA_RT2.length} KK, ${jumlahAnggota} anggota baru`;

  // --- Beberapa baris operasional, supaya isolasinya terlihat --------
  const sudahKas = await client.query(
    `SELECT 1 FROM finances WHERE rt_id = $1 AND deskripsi LIKE '%${TANDA}%' LIMIT 1`, [idRt2]);
  if (!sudahKas.rows.length) {
    await client.query(
      `INSERT INTO finances (tipe, kategori, jumlah, deskripsi, tanggal, created_by, rt_id)
       VALUES ('pemasukan', 'Iuran Warga', 250000, $1, CURRENT_DATE, $2, $3),
              ('pengeluaran', 'Kebersihan', 90000, $4, CURRENT_DATE, $2, $3)`,
      [`Iuran bulan berjalan RT 002 (${TANDA})`, idKetua2, idRt2,
        `Honor petugas kebersihan RT 002 (${TANDA})`]
    );
    ringkas['Kas RT 002'] = '2 transaksi';
  }

  const sudahPengaduan = await client.query(
    `SELECT 1 FROM complaints WHERE rt_id = $1 AND judul LIKE '%${TANDA}%' LIMIT 1`, [idRt2]);
  if (!sudahPengaduan.rows.length) {
    await client.query(
      `INSERT INTO complaints (kode_tiket, judul, deskripsi, kategori, status, user_id, rt_id)
       VALUES ($1, $2, $3, 'Lingkungan', 'Baru', $4, $5)`,
      [`RT2-${Date.now().toString().slice(-6)}`,
        `Lampu jalan padam di Jl. Kenanga (${TANDA})`,
        'Dilaporkan warga RT 002 sebagai contoh data terpisah antar-RT.',
        idKetua2, idRt2]
    );
    ringkas['Pengaduan RT 002'] = '1 tiket';
  }

  const sudahPengumuman = await client.query(
    `SELECT 1 FROM announcements WHERE rt_id = $1 AND judul LIKE '%${TANDA}%' LIMIT 1`, [idRt2]);
  if (!sudahPengumuman.rows.length) {
    await client.query(
      `INSERT INTO announcements (judul, isi, kategori, status, created_by, rt_id)
       VALUES ($1, $2, 'Umum', 'Aktif', $3, $4)`,
      [`Kerja bakti RT 002 hari Minggu (${TANDA})`,
        'Pengumuman ini hanya boleh terlihat oleh pengurus RT 002 dan ketua RW.',
        idKetua2, idRt2]
    );
    ringkas['Pengumuman RT 002'] = '1 pengumuman';
  }

  return ringkas;
}

(async () => {
  const client = await pool.connect();
  const buang = process.argv.includes('--hapus');
  try {
    await client.query('BEGIN');
    if (buang) {
      const pesan = await hapus(client);
      await client.query('COMMIT');
      console.log('\n✅ ' + pesan + '\n');
    } else {
      const ringkas = await isi(client);
      await client.query('COMMIT');
      console.log('\n✅ Data demo RT kedua siap:\n');
      for (const [k, v] of Object.entries(ringkas)) {
        console.log(`   ${k.padEnd(18)} ${v}`);
      }
      console.log('\n   Masuk sebagai ketuarw untuk melihat pemilih RT di pojok kanan atas.');
      console.log('   Masuk sebagai demo_ketua_rt2 untuk membuktikan ia HANYA melihat RT 002.\n');
    }
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('\n❌ Gagal:', e.message, '\n');
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
})();
