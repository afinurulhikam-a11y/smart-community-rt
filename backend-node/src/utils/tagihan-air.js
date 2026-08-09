/**
 * Perhitungan tagihan berbasis meteran — satu-satunya tempat rumusnya ditulis.
 *
 * Dipakai oleh `createBill`, `generateBills`, dan `updateBill`. Ketiganya bisa
 * menghasilkan atau mengubah nominal tagihan air, dan menulis rumusnya di tiap
 * tempat berarti tiga kesempatan untuk berbeda — persis pola yang sudah pernah
 * terjadi di proyek ini dengan format rupiah dan warna snackbar.
 *
 *     total = (terpakai × tarif_per_m3) + abondement + biaya_sampah
 *
 * Angkanya mengikuti tagihan yang berjalan di RT: pemakaian 4 m³ dengan tarif
 * Rp 3.000, abondement Rp 25.000, dan sampah Rp 30.000 menghasilkan Rp 67.000.
 *
 * **Biaya sampah memang ada di dalam tagihan air.** Karena itu iuran kebersihan
 * terpisah tidak lagi diperlukan — warga membayarnya sekali, lewat tagihan ini.
 */

/** Jenis iuran bernominal pasti, seperti iuran bulanan biasa. */
const TIPE_TETAP = 'tetap';

/** Jenis iuran yang nominalnya dihitung dari selisih meteran. */
const TIPE_METERAN = 'meteran';

/** Ubah menjadi bilangan bulat yang aman; nilai tak terbaca menjadi 0. */
function angka(nilai) {
  const n = Number(nilai);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

/**
 * Pemakaian air dalam m³.
 *
 * SENGAJA tidak disimpan di database. Ia selalu bisa dihitung ulang dari kedua
 * angka meterannya, dan menyimpan turunan berarti membuka kemungkinan ia
 * berbeda dari bahan penyusunnya — tanpa cara mengetahui mana yang benar.
 *
 * Mengembalikan null bila meteran sekarang belum diisi, yaitu tagihan yang
 * sudah diterbitkan tetapi petugas belum mencatat angkanya.
 */
function hitungTerpakai(meteranLalu, meteranSekarang) {
  if (meteranSekarang === null || meteranSekarang === undefined || meteranSekarang === '') {
    return null;
  }
  const lalu = angka(meteranLalu);
  const kini = angka(meteranSekarang);
  // Meteran mundur ditolak `bills_meteran_maju` di database. Batas bawah 0 di
  // sini hanya supaya perhitungan tidak pernah menghasilkan tagihan negatif
  // seandainya baris lama sempat masuk sebelum penjaga itu dipasang.
  return Math.max(0, kini - lalu);
}

/**
 * Rincian tagihan air, siap ditampilkan maupun disimpan.
 *
 * `meteranSekarang` boleh kosong: tagihan yang baru diterbitkan sudah berutang
 * abondement dan biaya sampah walau airnya belum dibaca. Nominalnya baru
 * bertambah setelah petugas memasukkan angka meteran, dan itu memang bagaimana
 * penagihan air bekerja — tagihannya terbit lebih dulu, pembacaannya menyusul.
 */
function rincianTagihanAir({
  meteranLalu,
  meteranSekarang,
  tarifPerM3,
  abondement,
  biayaSampah,
}) {
  const terpakai = hitungTerpakai(meteranLalu, meteranSekarang);
  const tarif = angka(tarifPerM3);
  const abon = angka(abondement);
  const sampah = angka(biayaSampah);
  const biayaAir = terpakai === null ? 0 : terpakai * tarif;

  return {
    meteran_lalu: meteranLalu === null || meteranLalu === undefined || meteranLalu === ''
      ? null
      : angka(meteranLalu),
    meteran_sekarang: meteranSekarang === null || meteranSekarang === undefined || meteranSekarang === ''
      ? null
      : angka(meteranSekarang),
    terpakai,
    tarif_per_m3: tarif,
    biaya_air: biayaAir,
    abondement: abon,
    biaya_sampah: sampah,
    total: biayaAir + abon + sampah,
    sudah_dibaca: terpakai !== null,
  };
}

/** Apakah jenis iuran ini ditagih berdasarkan meteran. */
function pakaiMeteran(jenis) {
  return jenis?.tipe_hitung === TIPE_METERAN;
}

module.exports = {
  TIPE_TETAP,
  TIPE_METERAN,
  hitungTerpakai,
  rincianTagihanAir,
  pakaiMeteran,
};
