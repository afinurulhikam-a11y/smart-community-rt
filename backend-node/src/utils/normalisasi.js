/**
 * Normalisasi nilai masukan sebelum disimpan.
 *
 * Dipakai bersama oleh SELURUH jalur tulis, supaya tidak ada satu pun jalur
 * yang menyimpan nilai dengan aturan berbeda.
 */

/** Nilai yang berarti laki-laki, dicocokkan sebagai kata utuh. */
const LAKI = new Set([
  'L', 'LK', 'LAKI', 'LAKI-LAKI', 'LAKI LAKI', 'LAKILAKI',
  'PRIA', 'M', 'MALE',
]);

/** Nilai yang berarti perempuan. */
const PEREMPUAN = new Set([
  'P', 'PR', 'PEREMPUAN', 'WANITA', 'F', 'FEMALE',
]);

/**
 * Ubah tulisan jenis kelamin apa pun menjadi 'L' atau 'P'.
 *
 * Kolom `anggota_keluarga.jenis_kelamin` bertipe varchar(1) dan layar
 * Statistik menghitungnya dengan `= 'L'` / `= 'P'`. Nilai selain itu ditolak
 * database, dan nilai yang salah petakan membuat grafik demografi keliru
 * TANPA error apa pun.
 *
 * Aturan lama `nilai.startsWith('P') ? 'P' : 'L'` terlihat masuk akal tetapi
 * membalik dua kata paling umum dalam bahasa Indonesia:
 *
 *     'PRIA'   -> P   (padahal laki-laki)
 *     'WANITA' -> L   (padahal perempuan)
 *
 * Karena itu kata utuh dicocokkan LEBIH DULU, dan tebakan huruf awal hanya
 * dipakai sebagai jaring terakhir.
 *
 * @param {*} nilai  tulisan apa adanya dari Excel, form, atau API
 * @param {string|null} bawaan  dipakai bila nilainya kosong atau tak dikenali
 * @returns {'L'|'P'|null}
 */
function jenisKelamin(nilai, bawaan = null) {
  const t = String(nilai ?? '').trim().toUpperCase().replace(/\s+/g, ' ');
  if (!t) return bawaan;

  if (LAKI.has(t)) return 'L';
  if (PEREMPUAN.has(t)) return 'P';

  // Jaring terakhir untuk tulisan berimbuhan, mis. "Perempuan (Dewasa)".
  // Urutannya penting: PRIA dan WANITA diperiksa sebelum huruf awal, karena
  // keduanya justru berlawanan dengan tebakan huruf pertamanya.
  if (t.startsWith('PRIA')) return 'L';
  if (t.startsWith('WANITA')) return 'P';
  if (t.startsWith('LAKI')) return 'L';
  if (t.startsWith('PEREMPUAN')) return 'P';

  // Benar-benar tidak dikenali: jangan menebak-nebak dan mengarang data.
  return bawaan;
}

/** Kebalikannya, untuk ditampilkan atau diekspor ke Excel. */
function labelJenisKelamin(kode) {
  if (kode === 'L') return 'Laki-laki';
  if (kode === 'P') return 'Perempuan';
  return '-';
}

module.exports = { jenisKelamin, labelJenisKelamin };
