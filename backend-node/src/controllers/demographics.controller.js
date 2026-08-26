const { pool } = require('../config/database');
const { SUMBER_WARGA, SUMBER_KELUARGA } = require('../utils/lingkup-warga');
const { klausaRt } = require('../utils/lingkup-rt');

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
    // ===================================================================
    // Kenapa parameternya berganti nama menjadi `no_rt`
    // ===================================================================
    //
    // Berkas ini sudah lebih dulu punya `?rt=`, dan artinya NOMOR RT — sebuah
    // varchar(3) yang dicocokkan ke `keluarga.rt`. Sejak pelingkupan per RT,
    // `?rt=` dipakai untuk hal yang sama sekali berbeda: id RT berbentuk UUID,
    // disisipkan otomatis oleh ApiService pada SETIAP permintaan.
    //
    // Keduanya bertabrakan di sini, dan cara gagalnya adalah yang terburuk.
    // Bukan galat: `'a614bf90-…' = keluarga.rt` sah secara SQL, hanya tidak
    // pernah cocok. Jadi begitu administrator menekan pemilih RT, seluruh
    // layar Statistik menampilkan 0 warga, 0 KK, semua grafik kosong — dengan
    // HTTP 200 dan tanpa satu pun baris log. Terukur: 41 warga menjadi 0.
    //
    // Nama lama tidak dipertahankan sebagai cadangan justru karena itu: selama
    // `rt` masih dibaca di sini, tabrakannya tetap ada. Tidak ada klien yang
    // pernah mengirimnya — DemographicProvider memanggil endpoint ini tanpa
    // parameter sama sekali — jadi penggantian nama ini tidak merusak apa pun.
    const noRt = (req.query.no_rt ?? '').toString().trim();

    // Pelingkupan RT yang sesungguhnya, dari sumber yang sama dengan seluruh
    // pengendali lain. Tanpa ini kartu "Total Warga" menjumlahkan seluruh RW
    // sementara layar Data Warga di sebelahnya sudah per RT — dua angka
    // berdampingan yang menjawab pertanyaan berbeda dengan label yang sama,
    // persis kesalahan yang lingkup-warga.js dibuat untuk mencegah.
    //
    // Dua array parameter terpisah karena kueri tingkat-jiwa memakai alias `k`
    // sedangkan kueri tingkat-KK memilih langsung dari `keluarga` tanpa alias.
    // Menyatukannya berarti nomor $n harus kebetulan sama di kedua sisi, dan
    // "kebetulan sama" berhenti benar begitu salah satu filternya berubah.
    const paramsWarga = [];
    let filterRt = noRt ? ` AND k.rt = $${paramsWarga.push(noRt)}` : '';
    filterRt += klausaRt(req, 'k', paramsWarga);

    const paramsKk = [];
    let filterRtKk = noRt ? ` AND rt = $${paramsKk.push(noRt)}` : '';
    filterRtKk += klausaRt(req, '', paramsKk);

    // Lingkupnya datang dari src/utils/lingkup-warga.js dan TIDAK ditulis ulang
    // di sini. Dua hal yang dulu berbeda antara berkas ini dan Data Warga, dan
    // dua-duanya gagal tanpa suara:
    //
    // 1. `ak.deleted_at IS NULL` — kolom yang tidak pernah ada di
    //    `anggota_keluarga`. Membuat SELURUH endpoint ini 500, dan kartunya
    //    menampilkan 0 karena `?? 0` di sisi Flutter menelan kegagalannya.
    //
    // 2. `ak.is_aktif = true` — kolom yang memang ada, jadi tidak ada error
    //    sama sekali. Layar Data Warga menghitung semua anggota, berkas ini
    //    menghitung yang aktif saja, dan kedua angka itu tampil berdampingan di
    //    aplikasi yang sama sebagai jumlah warga. Tidak ada yang salah menurut
    //    kodenya masing-masing; yang salah adalah keduanya menjawab pertanyaan
    //    berbeda dengan label yang sama.
    //
    // Sekarang keduanya memakai konstanta yang sama, jadi jumlahnya tidak bisa
    // berbeda tanpa seseorang mengubah satu berkas yang dibaca keduanya.
    // Status aktif tetap tersimpan dan tetap tampil sebagai lencana per baris
    // di Data Warga.

    // Satu helper untuk semua pecahan kategori warga (agama, pendidikan, dst).
    // Nama kolom berasal dari konstanta di file ini, bukan dari input user.
    const kategoriWarga = (kolom) => pool.query(`
      SELECT COALESCE(NULLIF(TRIM(ak.${kolom}), ''), '${LABEL_KOSONG}') AS label,
             COUNT(*)::int AS jumlah
      ${SUMBER_WARGA} ${filterRt}
      GROUP BY 1
      ORDER BY jumlah DESC, label ASC
    `, paramsWarga);

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
          -- Warga yang jenis kelaminnya bukan L maupun P.
          --
          -- Tanpa hitungan ini mereka hilang tanpa suara: total_warga
          -- memasukkannya, sedangkan kartu Laki-laki + Perempuan dan grafik
          -- Komposisi Gender tidak — jadi satu halaman menampilkan 36 jiwa
          -- sementara grafik gendernya hanya menjumlah 35, tanpa satu pun error.
          -- Kategori lain sudah aman karena dibangun lewat kategoriWarga, yang
          -- memunculkan "Tidak Diisi" dengan sendirinya; gender satu-satunya
          -- yang dirakit tangan dari dua FILTER.
          --
          -- Catatan: JANGAN pakai backtick di komentar ini. Seluruh kueri
          -- berada di dalam template literal JavaScript, dan satu backtick
          -- menutupnya di tengah jalan.
          COUNT(*) FILTER (
            WHERE ak.jenis_kelamin IS NULL OR ak.jenis_kelamin NOT IN ('L', 'P')
          )::int AS gender_kosong,

          -- age() bernilai negatif untuk tanggal di masa depan, dan "< 5"
          -- menerimanya — salah ketik tahun akan tercatat sebagai balita.
          -- Usianya memang tidak diketahui, jadi digolongkan bersama yang
          -- kosong, bukan ditebak.
          COUNT(*) FILTER (
            WHERE ak.tanggal_lahir IS NOT NULL
              AND ak.tanggal_lahir <= CURRENT_DATE
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
          COUNT(*) FILTER (
            WHERE ak.tanggal_lahir IS NULL OR ak.tanggal_lahir > CURRENT_DATE
          )::int AS usia_kosong,

          COUNT(*) FILTER (
            WHERE ak.status_pernikahan IN ('Cerai Hidup', 'Cerai Mati')
          )::int AS janda_duda
        ${SUMBER_WARGA} ${filterRt}
      `, paramsWarga),

      // Statistik tingkat keluarga dihitung per KK, bukan per jiwa.
      pool.query(`
        SELECT COUNT(*)::int AS total_kk
        ${SUMBER_KELUARGA} ${filterRtKk}
      `, paramsKk),

      pool.query(`
        SELECT COALESCE(NULLIF(TRIM(status_rumah), ''), '${LABEL_KOSONG}') AS label,
               COUNT(*)::int AS jumlah
        ${SUMBER_KELUARGA} ${filterRtKk}
        GROUP BY 1
        ORDER BY jumlah DESC, label ASC
      `, paramsKk),

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
      },
      // "Tidak Diisi" hanya ikut bila memang ada isinya, persis seperti
      // kategori lain: GROUP BY tidak pernah menghasilkan baris berjumlah nol,
      // jadi basis data yang rapi tidak akan menampilkan potongan kosong.
      // Diletakkan di urutan terakhir dengan alasan yang sama seperti
      // `urutkanKategori`: ia tidak boleh mendahului kategori yang terisi.
      gender: [
        { label: 'Laki-laki', jumlah: w.laki_laki || 0 },
        { label: 'Perempuan', jumlah: w.perempuan || 0 },
        ...(w.gender_kosong > 0 ? [{ label: LABEL_KOSONG, jumlah: w.gender_kosong }] : []),
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
