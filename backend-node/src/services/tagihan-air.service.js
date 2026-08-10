/**
 * Finalisasi tagihan air — SATU-SATUNYA jalur yang menerbitkan tagihan.
 *
 * Dipanggil dua tempat, dan keduanya wajib lewat sini:
 *
 *   1. `POST /bills/generate`   — pengurus, kapan saja, fallback
 *   2. `src/config/scheduler.js` — otomatis, tanggal 25 ke atas
 *
 * Dua implementasi terpisah akan berbeda perilaku cepat atau lambat, dan
 * bedanya baru ketahuan lewat tagihan yang salah di tangan warga. Karena itu
 * `generateBills` di controller kini hanya pembungkus tipis atas fungsi ini.
 *
 * ===================================================================
 * Dari mana angkanya datang
 * ===================================================================
 *
 * Bacaan meteran diambil dari `pembacaan_meteran`, BUKAN dari `bills`. Tagihan
 * bisa dihapus atau belum terbit; rantai bacaan harus tetap utuh supaya periode
 * berikutnya tetap benar.
 *
 * Tarif, abondement, biaya sampah, dan status langganan DISALIN ke tiap tagihan
 * saat terbit. Membacanya balik dari master berarti seluruh riwayat menulis
 * ulang dirinya sendiri setiap kali pengurus menaikkan tarif — warga yang sudah
 * lunas mendadak terlihat kurang bayar.
 *
 * ===================================================================
 * Idempotensi
 * ===================================================================
 *
 * Bersandar pada indeks unik `bills_kk_jenis_bulan_uniq` yang SUDAH ADA —
 * bukan pemeriksaan baru di kode. `ON CONFLICT DO NOTHING` membuat pemanggilan
 * kedua menghasilkan nol baris, sehingga scheduler yang berjalan berulang dan
 * Generate Manual sesudahnya tidak mungkin menggandakan tagihan.
 *
 * Penjagaan di database, bukan di aplikasi: dua permintaan yang tiba bersamaan
 * pun tetap menghasilkan satu baris.
 */
const {
  rincianTagihanAir,
  pakaiMeteran,
  STATUS_TERISI,
} = require('../utils/tagihan-air');

const STATUS_BELUM = 'unpaid';

/**
 * Terbitkan tagihan satu periode untuk seluruh kartu keluarga.
 *
 * @param {object} client  koneksi pg — WAJIB sudah di dalam transaksi
 * @param {object} opsi
 * @param {number} opsi.jenisIuranId
 * @param {string} opsi.bulan        `YYYY-MM`
 * @param {string|null} opsi.createdBy  UUID pengurus, null bila oleh sistem
 * @param {string|null} opsi.keterangan
 * @param {string|null} opsi.jatuhTempo
 * @param {number|null} opsi.nominalManual  hanya dipakai jenis bernominal tetap
 */
async function terbitkanTagihanPeriode(client, opsi) {
  const {
    jenisIuranId, bulan, createdBy = null,
    keterangan = null, jatuhTempo = null, nominalManual = null,
  } = opsi;

  const jenisRes = await client.query('SELECT * FROM jenis_iuran WHERE id = $1', [jenisIuranId]);
  const jenis = jenisRes.rows[0];
  if (!jenis) {
    return { ok: false, alasan: 'Jenis iuran tidak ditemukan.' };
  }
  if (jenis.is_aktif === false) {
    return { ok: false, alasan: 'Jenis iuran ini sudah dinonaktifkan.' };
  }

  const totalKk = (await client.query('SELECT COUNT(*)::int AS c FROM keluarga WHERE deleted_at IS NULL')).rows[0].c;

  // ── Jenis bernominal tetap: perilaku lama, tidak disentuh ──────────
  if (!pakaiMeteran(jenis)) {
    const nominal = nominalManual !== undefined && nominalManual !== null && nominalManual !== ''
      ? Number(nominalManual)
      : Number(jenis.nominal_default);
    if (!(nominal > 0)) {
      return { ok: false, alasan: 'Nominal harus lebih dari 0. Isi nominal atau set nominal default pada jenis iuran.' };
    }
    const r = await client.query(
      `INSERT INTO bills (keluarga_id, jenis_iuran_id, jenis_tagihan, bulan, nominal,
                          keterangan, jatuh_tempo, status, created_by)
       SELECT k.id, $1, $2, $3, $4, $5, $6, $7, $8
       FROM keluarga k WHERE k.deleted_at IS NULL
       ON CONFLICT (keluarga_id, jenis_iuran_id, bulan) WHERE keluarga_id IS NOT NULL
       DO NOTHING
       RETURNING id`,
      [jenisIuranId, jenis.nama_iuran, bulan, nominal, keterangan, jatuhTempo, STATUS_BELUM, createdBy]
    );
    return {
      ok: true, jenis, dibuat: r.rowCount, dilewati: totalKk - r.rowCount,
      berbasisMeteran: false, rincian: {},
    };
  }

  // ── Jenis bermeteran ──────────────────────────────────────────────
  if (!(Number(jenis.tarif_per_m3) > 0)) {
    return { ok: false, alasan: 'Tarif per m³ pada jenis iuran ini belum diisi. Lengkapi dulu di master Jenis Iuran.' };
  }

  // Satu kueri untuk seluruh rumah: data pelanggan, langganan sampahnya, dan
  // bacaan periode ini bila ada. LEFT JOIN — rumah tanpa bacaan tetap ikut,
  // dan tagihannya terbit sebesar bagian tetap. Scheduler tidak pernah
  // mengarang angka meteran untuk mereka.
  const rumah = await client.query(
    `SELECT k.id AS keluarga_id,
            k.langganan_sampah,
            pm.id       AS pembacaan_id,
            pm.status   AS status_bacaan,
            pm.meteran_lalu,
            pm.meteran_sekarang
     FROM keluarga k
     LEFT JOIN pembacaan_meteran pm
            ON pm.keluarga_id = k.id AND pm.periode = $1
     WHERE k.deleted_at IS NULL
     ORDER BY k.id`,
    [bulan]
  );

  const rincian = { terisi: 0, tanpa_bacaan: 0, anomali: 0 };
  let dibuat = 0;

  for (const r of rumah.rows) {
    // Bacaan dipakai HANYA bila statusnya 'terisi'. Angka anomali tersimpan
    // untuk diperiksa, tetapi tidak pernah dipakai menghitung uang — itulah
    // bedanya "menandai" dengan "mempercayai".
    const dipakai = r.status_bacaan === STATUS_TERISI;
    if (dipakai) rincian.terisi++;
    else if (r.status_bacaan === 'anomali') rincian.anomali++;
    else rincian.tanpa_bacaan++;

    const berlangganan = r.langganan_sampah === true;

    const air = rincianTagihanAir({
      meteranLalu: r.meteran_lalu,
      meteranSekarang: dipakai ? r.meteran_sekarang : null,
      tarifPerM3: jenis.tarif_per_m3,
      abondement: jenis.abondement,
      // Biaya sampah hanya ditambahkan bila rumah ini berlangganan pada saat
      // tagihan terbit. Tidak pernah dikenakan rata.
      biayaSampah: berlangganan ? jenis.biaya_sampah : 0,
    });

    const ins = await client.query(
      `INSERT INTO bills (keluarga_id, jenis_iuran_id, jenis_tagihan, bulan, nominal,
                          keterangan, jatuh_tempo, status, created_by,
                          meteran_lalu, meteran_sekarang, tarif_per_m3, abondement,
                          biaya_sampah, langganan_sampah)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       ON CONFLICT (keluarga_id, jenis_iuran_id, bulan) WHERE keluarga_id IS NOT NULL
       DO NOTHING
       RETURNING id`,
      [
        r.keluarga_id, jenisIuranId, jenis.nama_iuran, bulan, air.total,
        keterangan, jatuhTempo, STATUS_BELUM, createdBy,
        air.meteran_lalu, air.meteran_sekarang, air.tarif_per_m3,
        air.abondement, air.biaya_sampah, berlangganan,
      ]
    );

    if (ins.rowCount === 0) continue; // sudah ada — idempotensi bekerja
    dibuat++;

    // Tautkan bacaan ke tagihannya. Hanya diisi bila masih kosong, supaya
    // penerbitan ulang tidak memindahkan tautan bacaan ke tagihan lain.
    if (r.pembacaan_id) {
      await client.query(
        'UPDATE pembacaan_meteran SET bill_id = $1, updated_at = NOW() WHERE id = $2 AND bill_id IS NULL',
        [ins.rows[0].id, r.pembacaan_id]
      );
    }
  }

  return {
    ok: true, jenis, dibuat, dilewati: rumah.rowCount - dibuat,
    berbasisMeteran: true, rincian,
  };
}

module.exports = { terbitkanTagihanPeriode };
