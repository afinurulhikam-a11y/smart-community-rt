/**
 * Bukti bahwa Data Warga dan kartu TOTAL WARGA menghitung baris yang sama.
 *
 * Sengaja menandai sebagian warga TIDAK AKTIF dan sebagian NULL lebih dulu:
 * tanpa itu kedua angka sama karena tidak ada yang bisa berbeda, dan
 * pemeriksaannya tidak membuktikan apa-apa.
 *
 * Perubahannya TIDAK dibungkus transaksi karena controller memakai `pool.query`
 * yang mengambil koneksi lain — perubahan di dalam transaksi tidak akan terlihat
 * olehnya. Sebagai gantinya nilai asli setiap baris disimpan dulu dan
 * dikembalikan satu per satu di blok `finally`.
 *
 * Jalankan: node bukti-total-warga.js
 */
require('dotenv').config();
const { pool } = require('./src/config/database');
const { getWarga } = require('./src/controllers/warga.controller');
const { getDemographicsSummary } = require('./src/controllers/demographics.controller');

function tangkap() {
  const h = {};
  return {
    h,
    res: {
      status(c) { h.status = c; return this; },
      json(b) { h.body = b; return this; },
    },
  };
}

async function angka() {
  const a = tangkap();
  await getWarga({ user: { id: 'x', role: 'admin' }, query: { page: 1, limit: 1 } }, a.res);
  const b = tangkap();
  await getDemographicsSummary({ user: { id: 'x', role: 'admin' }, query: {} }, b.res);

  const s = b.h.body?.data?.summary ?? {};
  return {
    dataWarga: a.h.body?.pagination?.total_data ?? null,
    httpWarga: a.h.status,
    kartu: s.total_warga ?? null,
    httpKartu: b.h.status,
    lk: s.laki_laki ?? 0,
    pr: s.perempuan ?? 0,
  };
}

function lapor(judul, n) {
  console.log(judul);
  console.log('  Data Warga        :', n.dataWarga, `(HTTP ${n.httpWarga})`);
  console.log('  Kartu TOTAL WARGA :', n.kartu, `(HTTP ${n.httpKartu})`);
}

(async () => {
  let asli = [];
  let kode = 0;
  try {
    lapor('SEBELUM — belum ada warga tidak aktif', await angka());

    // Simpan nilai asli sebelum diubah; ini satu-satunya salinannya.
    asli = (await pool.query(
      'SELECT id, is_aktif FROM anggota_keluarga ORDER BY id LIMIT 7'
    )).rows;

    const idMati = asli.slice(0, 5).map((r) => r.id);
    const idNull = asli.slice(5, 7).map((r) => r.id);

    await pool.query('UPDATE anggota_keluarga SET is_aktif = false WHERE id = ANY($1)', [idMati]);
    // NULL penting: `is_aktif = true` membuangnya juga, jadi selisihnya bisa
    // muncul tanpa seorang pun pernah menandai warga tidak aktif.
    await pool.query('UPDATE anggota_keluarga SET is_aktif = NULL WHERE id = ANY($1)', [idNull]);
    console.log(`\n  -> ${idMati.length} ditandai TIDAK AKTIF, ${idNull.length} dibiarkan NULL\n`);

    const n = await angka();
    lapor('SESUDAH', n);
    console.log('  L + P             :', `${n.lk} + ${n.pr} = ${n.lk + n.pr}`);

    const samaLayar = n.dataWarga === n.kartu;
    const samaGender = n.lk + n.pr === n.kartu;
    console.log('\n  kedua layar sepakat          :', samaLayar ? 'YA' : `TIDAK — beda ${n.dataWarga - n.kartu}`);
    console.log('  L+P = total (tidak ada sisa) :', samaGender ? 'YA' : 'TIDAK');
    if (!samaLayar || !samaGender) kode = 1;
  } catch (e) {
    console.error('GAGAL:', e.message);
    kode = 1;
  } finally {
    for (const r of asli) {
      await pool.query('UPDATE anggota_keluarga SET is_aktif = $1 WHERE id = $2', [r.is_aktif, r.id]);
    }
    console.log(`\n${asli.length} baris dikembalikan ke nilai semula.`);
    await pool.end();
    process.exit(kode);
  }
})();
