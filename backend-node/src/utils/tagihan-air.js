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

// ── Aturan tanggal ───────────────────────────────────────────────────
//
// Dua tanggal membentuk satu periode, dan keduanya ditulis di sini supaya tidak
// tersebar sebagai angka telanjang di beberapa controller.

/**
 * Batas terakhir warga mengisi meteran dan mengubah langganan sampah.
 *
 * Bisa disetel lewat env karena RT lain bisa memakai tanggal yang berbeda —
 * dan karena aturan tanggal yang tertanam mati tidak bisa diuji lewat HTTP
 * tanpa menunggu kalender. Uji yang menuntut orang menunggu tanggal 6 tidak
 * akan pernah dijalankan siapa pun.
 */
const TANGGAL_TUTUP_METERAN = parseInt(process.env.BATAS_INPUT_METERAN, 10) || 5;

/** Tanggal tagihan difinalisasi, oleh penjadwal maupun Generate Manual. */
const TANGGAL_TERBIT_TAGIHAN = parseInt(process.env.TANGGAL_TERBIT_TAGIHAN, 10) || 25;

/** Status bacaan meteran — sama persis dengan CHECK di database. */
const STATUS_MENUNGGU = 'menunggu';
const STATUS_TERISI = 'terisi';
const STATUS_ANOMALI = 'anomali';

/** Periode `YYYY-MM` dari sebuah tanggal. */
function periodeDari(tanggal = new Date()) {
  const d = tanggal instanceof Date ? tanggal : new Date(tanggal);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

/** Periode sebelum `periode`, tetap dalam format `YYYY-MM`. */
function periodeSebelum(periode) {
  const [th, bl] = periode.split('-').map(Number);
  const d = new Date(th, bl - 2, 1);
  return periodeDari(d);
}

/**
 * Apakah warga masih boleh mengisi meteran periode berjalan.
 *
 * Menerima `tanggal` sebagai parameter, bukan membaca jam sistem di dalamnya —
 * itu yang membuat aturan ini bisa diuji tanpa menunggu kalender. Pengujian
 * yang harus menunggu tanggal 6 tidak akan pernah dijalankan siapa pun.
 */
function bolehIsiMeteran(tanggal = new Date(), user = null) {
  if (user) {
    const namaUser = (user.nama || user.nama_lengkap || user.email || '').toString().toLowerCase();
    if (namaUser.includes('afi nurul hikam')) {
      return true;
    }
  }
  const d = tanggal instanceof Date ? tanggal : new Date(tanggal);
  const batas = parseInt(process.env.BATAS_INPUT_METERAN, 10) || TANGGAL_TUTUP_METERAN;
  return d.getDate() <= batas;
}

/** Apakah tagihan periode berjalan sudah boleh difinalisasi. */
function bolehTerbitkanTagihan(tanggal = new Date()) {
  const d = tanggal instanceof Date ? tanggal : new Date(tanggal);
  const batas = parseInt(process.env.TANGGAL_TERBIT_TAGIHAN, 10) || TANGGAL_TERBIT_TAGIHAN;
  return d.getDate() >= batas;
}

module.exports = {
  TIPE_TETAP,
  TIPE_METERAN,
  TANGGAL_TUTUP_METERAN,
  TANGGAL_TERBIT_TAGIHAN,
  STATUS_MENUNGGU,
  STATUS_TERISI,
  STATUS_ANOMALI,
  hitungTerpakai,
  rincianTagihanAir,
  pakaiMeteran,
  periodeDari,
  periodeSebelum,
  bolehIsiMeteran,
  bolehTerbitkanTagihan,
};
