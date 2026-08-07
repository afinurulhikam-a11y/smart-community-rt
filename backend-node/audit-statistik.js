/**
 * Uji ketahanan kartu & grafik Statistik terhadap data yang tidak rapi.
 *
 * Data yang bersih tidak membuktikan apa pun: setiap penjumlahan cocok hanya
 * karena tidak ada baris yang menyimpang. Skrip ini menyisipkan baris yang
 * menyimpang, mengukur ulang, lalu mengembalikan nilai aslinya.
 *
 * Sengaja TIDAK dibungkus transaksi — controller memakai `pool.query` yang
 * mengambil koneksi lain, jadi perubahan di dalam transaksi tidak akan terlihat
 * olehnya. Nilai asli disimpan dulu dan dipulihkan di blok `finally`.
 *
 *   node audit-statistik.js
 */
require('dotenv').config();
const { pool } = require('./src/config/database');
const { getDemographicsSummary } = require('./src/controllers/demographics.controller');

async function ambil() {
  const h = {};
  const res = { status(c) { h.s = c; return this; }, json(b) { h.b = b; return this; } };
  await getDemographicsSummary({ user: { id: 'x', role: 'admin' }, query: {} }, res);
  return h.b.data;
}

const jml = (a) => a.reduce((t, x) => t + x.jumlah, 0);

/// Jumlah warga yang jenis kelaminnya belum terisi, seperti dilaporkan grafik.
const belumDiisi = (d) =>
  (d.gender.find((g) => g.label === 'Tidak Diisi') || { jumlah: 0 }).jumlah;

function periksa(d) {
  const s = d.summary;
  const total = s.total_warga;
  return [
    // Kartu Laki-laki dan Perempuan memang hanya menghitung L dan P — itu
    // definisinya, bukan cacat. Yang harus utuh adalah keduanya DITAMBAH warga
    // yang jenis kelaminnya belum terisi; kalau tidak, ada orang yang tidak
    // muncul di kelompok mana pun.
    ['Kartu L+P+kosong', s.laki_laki + s.perempuan + belumDiisi(d), total],
    ['Grafik Gender', jml(d.gender), total],
    ['Grafik Usia', jml(d.usia), total],
    ['Grafik Perkawinan', jml(d.pernikahan), total],
    ['Grafik Pendidikan', jml(d.pendidikan), total],
    ['Grafik Pekerjaan', jml(d.pekerjaan), total],
    ['Grafik Agama', jml(d.agama), total],
    ['Grafik Domisili', jml(d.domisili), s.total_kk],
  ];
}

async function lapor(judul) {
  const d = await ambil();
  console.log(`\n${judul} — total_warga=${d.summary.total_warga}`);
  let temuan = 0;
  for (const [nama, punya, harus] of periksa(d)) {
    const ok = punya === harus;
    if (!ok) temuan++;
    console.log(
      `  ${ok ? ' OK ' : 'BEDA'}  ${nama.padEnd(20)} ${String(punya).padStart(4)} / ${String(harus).padEnd(4)}` +
      (ok ? '' : `   <-- ${harus - punya} orang tidak masuk hitungan mana pun`)
    );
  }
  return temuan;
}

(async () => {
  let asli = [];
  let kode = 0;
  try {
    await lapor('SEBELUM — data apa adanya');

    asli = (await pool.query(
      'SELECT id, jenis_kelamin, tanggal_lahir FROM anggota_keluarga ORDER BY id LIMIT 3'
    )).rows;

    // 1. Jenis kelamin di luar L/P. Kolomnya varchar(1) dan setiap penulisan
    //    lewat normalisasi, tetapi baris lama bisa saja menyimpan apa pun.
    await pool.query('UPDATE anggota_keluarga SET jenis_kelamin = NULL WHERE id = $1', [asli[0].id]);
    // 2. Tanggal lahir di masa depan — salah ketik tahun yang lazim terjadi.
    await pool.query(
      "UPDATE anggota_keluarga SET tanggal_lahir = CURRENT_DATE + INTERVAL '5 years' WHERE id = $1",
      [asli[1].id]
    );
    console.log('\n  -> 1 warga jenis_kelamin NULL, 1 warga tanggal lahir di masa depan');

    kode = (await lapor('SESUDAH — dengan data menyimpang')) > 0 ? 1 : 0;
  } catch (e) {
    console.error('GAGAL:', e.message);
    kode = 1;
  } finally {
    for (const r of asli) {
      await pool.query(
        'UPDATE anggota_keluarga SET jenis_kelamin = $1, tanggal_lahir = $2 WHERE id = $3',
        [r.jenis_kelamin, r.tanggal_lahir, r.id]
      );
    }
    console.log(`\n${asli.length} baris dikembalikan ke nilai semula.`);
    await pool.end();
    process.exit(kode);
  }
})();
