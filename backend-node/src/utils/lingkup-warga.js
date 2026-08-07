/**
 * Definisi tunggal "siapa yang dihitung sebagai warga".
 *
 * Data Warga dan kartu TOTAL WARGA di dashboard membaca tabel yang sama, tetapi
 * dulu masing-masing menulis kueri sendiri — dan keduanya berbeda satu klausa:
 * demografi menambahkan `ak.is_aktif = true`. Akibatnya dua layar melaporkan
 * jumlah warga yang berbeda tanpa satu pun dari keduanya salah menurut kodenya
 * sendiri, dan tidak ada pesan error di mana pun.
 *
 * `= true` juga membuang baris ber-`NULL`, bukan hanya yang bernilai `false`.
 * Jadi selisihnya bisa muncul walaupun tidak seorang pun pernah menandai warga
 * sebagai tidak aktif — cukup satu baris yang masuk sebelum kolomnya punya
 * DEFAULT, atau lewat jalur impor yang tidak mengisinya.
 *
 * Dihitung sekarang: setiap anggota keluarga yang kartu keluarganya belum
 * dihapus. Persis yang ditampilkan layar Data Warga, tidak lebih dan tidak
 * kurang. Status aktif tetap disimpan dan tetap ditampilkan sebagai lencana per
 * baris di Data Warga — yang berubah hanya bahwa ia tidak lagi diam-diam
 * mengurangi angka total di layar lain.
 *
 * Menyaring anggota lewat `keluarga` sudah cukup: `anggota_keluarga` tidak punya
 * kolom `deleted_at` sama sekali, dan tidak ada satu baris pun di seluruh kode
 * yang menulisnya. Menambahkan `ak.deleted_at IS NULL` pernah dicoba dan
 * membuat SELURUH endpoint demografi 500 — kartu dashboard menampilkan 0 karena
 * `?? 0` di sisi Flutter menelan kegagalannya.
 *
 * **Kalau menambah kueri yang menghitung warga, pakai konstanta ini.** Menyalin
 * teksnya adalah cara persis bagaimana kedua angka itu berpisah sebelumnya.
 */
const SUMBER_WARGA = `
  FROM anggota_keluarga ak
  JOIN keluarga k ON ak.keluarga_id = k.id
  WHERE k.deleted_at IS NULL
`;

/** Kartu keluarga yang belum dihapus — pasangan tingkat-KK dari [SUMBER_WARGA]. */
const SUMBER_KELUARGA = `
  FROM keluarga
  WHERE deleted_at IS NULL
`;

module.exports = { SUMBER_WARGA, SUMBER_KELUARGA };
