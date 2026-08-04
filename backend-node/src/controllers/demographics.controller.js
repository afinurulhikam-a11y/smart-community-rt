const { pool } = require('../config/database');

const LABEL_KOSONG = 'Tidak Diisi';

// Bucket usia dipakai di dua tempat: query SQL dan urutan tampil di respons.
const BUCKET_USIA = [
  { key: 'balita', label: 'Balita (0–4)' },
  { key: 'anak', label: 'Anak (5–11)' },
  { key: 'remaja', label: 'Remaja (12–24)' },
  { key: 'dewasa', label: 'Dewasa (25–59)' },
  { key: 'lansia', label: 'Lansia (60+)' },
  { key: 'usia_kosong', label: LABEL_KOSONG },
];

/**
 * Ubah hasil GROUP BY menjadi daftar { label, jumlah }, dengan kategori
 * "Tidak Diisi" selalu di urutan terakhir agar tidak mendominasi legend
 * chart hanya karena jumlahnya kebetulan paling banyak.
 */
function urutkanKategori(rows) {
  const terisi = rows.filter((r) => r.label !== LABEL_KOSONG);
  const kosong = rows.filter((r) => r.label === LABEL_KOSONG);
  return [...terisi, ...kosong];
}

async function getDemographicsSummary(req, res) {
  try {
    // Filter RT opsional. Sebelumnya memakai req.user.no_rt, padahal JWT hanya
    // memuat id/email/role sehingga filternya tidak pernah aktif.
    const { rt } = req.query;
    const filterRt = rt ? 'AND k.rt = $1' : '';
    const filterRtKk = rt ? 'WHERE rt = $1' : '';
    const params = rt ? [rt] : [];

    // Satu helper untuk semua pecahan kategori warga (agama, pendidikan, dst).
    // Nama kolom berasal dari konstanta di file ini, bukan dari input user.
    const kategoriWarga = (kolom) => pool.query(`
      SELECT COALESCE(NULLIF(TRIM(ak.${kolom}), ''), '${LABEL_KOSONG}') AS label,
             COUNT(*)::int AS jumlah
      FROM anggota_keluarga ak
      JOIN keluarga k ON ak.keluarga_id = k.id
      WHERE ak.is_aktif = true ${filterRt}
      GROUP BY 1
      ORDER BY jumlah DESC, label ASC
    `, params);

    const [
      wargaRes,
      kkRes,
      domisiliRes,
      pernikahanRes,
      pendidikanRes,
      pekerjaanRes,
      agamaRes,
    ] = await Promise.all([
      // Ringkasan + gender + bucket usia dalam satu lintasan tabel.
      pool.query(`
        SELECT
          COUNT(*)::int AS total_warga,
          COUNT(*) FILTER (WHERE ak.jenis_kelamin = 'L')::int AS laki_laki,
          COUNT(*) FILTER (WHERE ak.jenis_kelamin = 'P')::int AS perempuan,

          COUNT(*) FILTER (
            WHERE ak.tanggal_lahir IS NOT NULL
              AND date_part('year', age(CURRENT_DATE, ak.tanggal_lahir)) < 5
          )::int AS balita,
          COUNT(*) FILTER (
            WHERE date_part('year', age(CURRENT_DATE, ak.tanggal_lahir)) BETWEEN 5 AND 11
          )::int AS anak,
          COUNT(*) FILTER (
            WHERE date_part('year', age(CURRENT_DATE, ak.tanggal_lahir)) BETWEEN 12 AND 24
          )::int AS remaja,
          COUNT(*) FILTER (
            WHERE date_part('year', age(CURRENT_DATE, ak.tanggal_lahir)) BETWEEN 25 AND 59
          )::int AS dewasa,
          COUNT(*) FILTER (
            WHERE date_part('year', age(CURRENT_DATE, ak.tanggal_lahir)) >= 60
          )::int AS lansia,
          COUNT(*) FILTER (WHERE ak.tanggal_lahir IS NULL)::int AS usia_kosong,

          COUNT(*) FILTER (
            WHERE ak.status_pernikahan IN ('Cerai Hidup', 'Cerai Mati')
          )::int AS janda_duda
        FROM anggota_keluarga ak
        JOIN keluarga k ON ak.keluarga_id = k.id
        WHERE ak.is_aktif = true ${filterRt}
      `, params),

      // Statistik tingkat keluarga dihitung per KK, bukan per jiwa.
      pool.query(`
        SELECT
          COUNT(*)::int AS total_kk,
          COUNT(*) FILTER (
            WHERE status_rumah ILIKE '%Sewa%'
               OR status_rumah ILIKE '%Kontrak%'
               OR status_rumah ILIKE '%Kos%'
          )::int AS rumah_sewa_kos
        FROM keluarga
        ${filterRtKk}
      `, params),

      pool.query(`
        SELECT COALESCE(NULLIF(TRIM(status_rumah), ''), '${LABEL_KOSONG}') AS label,
               COUNT(*)::int AS jumlah
        FROM keluarga
        ${filterRtKk}
        GROUP BY 1
        ORDER BY jumlah DESC, label ASC
      `, params),

      kategoriWarga('status_pernikahan'),
      kategoriWarga('pendidikan'),
      kategoriWarga('pekerjaan'),
      kategoriWarga('agama'),
    ]);

    const w = wargaRes.rows[0] || {};
    const kk = kkRes.rows[0] || {};

    const data = {
      summary: {
        total_warga: w.total_warga || 0,
        total_kk: kk.total_kk || 0,
        laki_laki: w.laki_laki || 0,
        perempuan: w.perempuan || 0,
      },
      rentan: {
        balita: w.balita || 0,
        lansia: w.lansia || 0,
        janda_duda: w.janda_duda || 0,
        rumah_sewa_kos: kk.rumah_sewa_kos || 0,
      },
      gender: [
        { label: 'Laki-laki', jumlah: w.laki_laki || 0 },
        { label: 'Perempuan', jumlah: w.perempuan || 0 },
      ],
      // Urutan bucket usia sengaja tetap (bukan diurutkan jumlah) agar sumbu
      // chart terbaca dari termuda ke tertua.
      usia: BUCKET_USIA.map(({ key, label }) => ({ label, jumlah: w[key] || 0 })),
      pernikahan: urutkanKategori(pernikahanRes.rows),
      domisili: urutkanKategori(domisiliRes.rows),
      pendidikan: urutkanKategori(pendidikanRes.rows),
      pekerjaan: urutkanKategori(pekerjaanRes.rows),
      agama: urutkanKategori(agamaRes.rows),
    };

    return res.status(200).json({ success: true, data });
  } catch (err) {
    console.error('GetDemographics Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server saat mengambil data demografi.' });
  }
}

module.exports = { getDemographicsSummary };
