/**
 * Definisi tunggal "RT mana yang sedang dilihat".
 *
 * ===================================================================
 * Kenapa ini harus satu berkas, bukan satu klausa per pengendali
 * ===================================================================
 *
 * Ada 527 kueri SQL tersebar di 28 pengendali. Menyalin klausa `AND rt_id = $n`
 * ke masing-masing berarti 527 kesempatan untuk lupa — dan yang membuat lupa
 * berbahaya di sini adalah **gejalanya tidak ada**. Kueri yang lupa disaring
 * tidak melempar galat, tidak menuliskan apa pun ke log, dan mengembalikan
 * daftar yang terlihat wajar. Yang terjadi hanyalah pengurus RT 001 melihat
 * nama, NIK, dan alamat warga RT 002.
 *
 * Pola yang sama sudah dipakai `lingkup-warga.js` untuk pertanyaan "siapa yang
 * dihitung sebagai warga", justru karena dua layar pernah menjawabnya berbeda.
 *
 * ===================================================================
 * Kenapa `?rt=` DIABAIKAN, bukan DITOLAK
 * ===================================================================
 *
 * Peran selain administrator dan ketua RW selalu terkunci pada RT-nya sendiri.
 * Ketika mereka mengirim `?rt=` milik RT lain, nilainya dibuang diam-diam.
 *
 * Menolaknya dengan 403 terasa lebih tegas, tetapi justru memberi tahu penyerang
 * bahwa parameter itu berarti sesuatu, dan membuat klien lama yang kebetulan
 * meneruskan query string ikut gagal. Mengabaikan lebih aman dan tidak pernah
 * salah. Pola ini sudah dipakai `createBorrowing`, yang membuang `user_id` dari
 * badan permintaan milik warga dan memakai `req.user.id`.
 *
 * ===================================================================
 * Kenapa nilainya diperiksa bentuknya
 * ===================================================================
 *
 * `rt_id` bertipe UUID. Mengirim `?rt=abc` membuat PostgreSQL menolak dengan
 * "invalid input syntax for type uuid", yaitu galat 500 — sebuah kegagalan
 * server untuk masukan yang jelas salah dari klien. Bentuknya diperiksa lebih
 * dulu, dan yang tidak berbentuk UUID diperlakukan seperti tidak dikirim.
 */

/** Peran yang boleh melihat lebih dari satu RT. */
const PERAN_LINTAS_RT = Object.freeze(['admin', 'ketua_rw']);

const POLA_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Apakah peran pemanggil boleh menembus batas RT-nya sendiri. */
function bolehLintasRt(req) {
  return PERAN_LINTAS_RT.includes(req?.user?.role);
}

/**
 * RT yang sedang dilihat pemanggil.
 *
 * - Peran lintas RT: mengikuti `?rt=` bila ada dan berbentuk UUID; bila tidak,
 *   `null` yang berarti SELURUH RW.
 * - Peran lain: selalu `rt_id` miliknya, apa pun yang dikirim klien.
 *
 * @returns {string|null} id RT, atau null bila tidak dibatasi.
 */
function rtAktif(req) {
  if (!bolehLintasRt(req)) return req?.user?.rt_id ?? null;
  const diminta = String(req?.query?.rt ?? '').trim();
  return POLA_UUID.test(diminta) ? diminta : null;
}

/**
 * Potongan klausa WHERE untuk sebuah tabel, siap disambung ke kueri.
 *
 * Nilainya didorong ke `params` yang sudah ada, sehingga nomor parameternya
 * selalu benar berapa pun panjang kueri sebelumnya.
 *
 *   const params = [status];
 *   const sql = `SELECT * FROM complaints c
 *                 WHERE c.status = $1 ${klausaRt(req, 'c', params)}`;
 *
 * @param {object} req    permintaan Express, sudah lewat authMiddleware
 * @param {string} alias  alias tabel di kueri; kosong bila tanpa alias
 * @param {Array}  params array parameter kueri — DIUBAH di tempat
 * @returns {string} ' AND alias.rt_id = $n', atau '' bila tidak dibatasi
 */
function klausaRt(req, alias, params) {
  const id = rtAktif(req);
  if (!id) return '';
  params.push(id);
  const kolom = alias ? `${alias}.rt_id` : 'rt_id';
  return ` AND ${kolom} = $${params.length}`;
}

/**
 * Bentuk telanjang tanpa `AND`, untuk pengendali yang mengumpulkan syaratnya
 * dalam sebuah array lalu menyambungnya sendiri:
 *
 *   const k = kondisiRt(req, 'f', params);
 *   if (k) kondisi.push(k);
 *
 * @returns {string|null} 'alias.rt_id = $n', atau null bila tidak dibatasi
 */
function kondisiRt(req, alias, params) {
  const potongan = klausaRt(req, alias, params);
  return potongan ? potongan.replace(' AND ', '') : null;
}

/**
 * Bentuk `WHERE` mandiri, untuk kueri yang belum punya klausa lain.
 *
 * @returns {string} ' WHERE alias.rt_id = $n', atau '' bila tidak dibatasi
 */
function whereRt(req, alias, params) {
  const potongan = klausaRt(req, alias, params);
  return potongan ? potongan.replace(' AND ', ' WHERE ') : '';
}

/**
 * RT yang harus dituliskan pada baris baru.
 *
 * Administrator dan ketua RW boleh membuat data atas nama RT tertentu, tetapi
 * harus menyebutkannya — lewat `?rt=` atau `rt_id` di badan permintaan. Bila
 * tidak disebutkan, RT miliknya sendiri yang dipakai, sehingga tidak pernah ada
 * baris yang lahir tanpa RT.
 */
function rtUntukSimpan(req) {
  if (bolehLintasRt(req)) {
    const dariBadan = String(req?.body?.rt_id ?? '').trim();
    if (POLA_UUID.test(dariBadan)) return dariBadan;
    const dariQuery = rtAktif(req);
    if (dariQuery) return dariQuery;
  }
  return req?.user?.rt_id ?? null;
}

/**
 * ===================================================================
 * Penjagaan SATU BARIS: `pastikanDalamRt`
 * ===================================================================
 *
 * `klausaRt` menjaga kueri DAFTAR, dan itu hanya separuh pekerjaan. Setiap
 * modul juga punya jalur `:id` — buka detail, ubah, hapus, setujui — dan di
 * sana idnya datang dari URL, bukan dari daftar yang sudah tersaring. Selama
 * penjagaannya hanya ada di daftar, siapa pun yang MENGETAHUI sebuah id bisa
 * membuka, mengubah, dan menghapus baris milik RT lain.
 *
 * Itu bukan dugaan. Diukur sebelum berkas ini ada: pengurus RT 001 memanggil
 * `GET /api/families/:id` dengan id kartu keluarga milik RT 002 dan menerima
 * HTTP 200 lengkap dengan seluruh anggotanya.
 *
 * ===================================================================
 * Kenapa satu penjaga, bukan `AND rt_id = $n` di tiap kueri
 * ===================================================================
 *
 * Ada sekitar tiga puluh jalur `:id`. Menambahkan klausa satu per satu berarti
 * tiga puluh kesempatan untuk lupa, dan kelalaiannya tidak berbunyi — persis
 * alasan `klausaRt` sendiri ditulis di satu tempat. Lebih buruk lagi, banyak
 * pengendali membaca barisnya lebih dulu untuk jejak audit lalu menulis lewat
 * kueri KEDUA; menyaring salah satunya saja menghasilkan penjagaan yang
 * terlihat ada tetapi bisa dilewati.
 *
 * Satu panggilan di awal pengendali menutup seluruh badan fungsinya sekaligus,
 * berapa pun jumlah kueri di dalamnya.
 *
 * ===================================================================
 * Kenapa 404, bukan 403
 * ===================================================================
 *
 * 403 berarti "ada, tapi bukan milikmu" — ia MENGONFIRMASI keberadaan baris
 * itu, sehingga id yang ditebak satu per satu tetap memberi tahu penebaknya
 * mana yang nyata. 404 adalah jawaban yang jujur dari sudut pandang pemanggil:
 * di dalam lingkupnya, baris itu memang tidak ada. Ini alasan yang sama dengan
 * `?rt=` yang diabaikan alih-alih ditolak di bagian atas berkas ini.
 *
 * ===================================================================
 * Kenapa nama tabel diambil dari daftar tertutup
 * ===================================================================
 *
 * Nama tabel tidak bisa diparameterkan di SQL, jadi ia selalu disambung
 * sebagai teks. Selama nilainya harus cocok dengan kunci di `SUMBER_RT`,
 * tidak ada masukan pemanggil yang bisa sampai ke kueri — disiplin yang sama
 * dipakai `reset-groups.js` untuk daftar tabel yang boleh dihapus.
 *
 * Dua tabel tidak punya `rt_id` sendiri dan dilingkupi lewat induknya, persis
 * seperti yang diputuskan migrasi v43: `bills` dan `anggota_keluarga` ikut
 * `keluarga`. Menyalin `rt_id` ke sana akan menduakan sumber kebenarannya —
 * sebuah kartu keluarga yang pindah RT lalu punya tagihan yang tidak ikut
 * pindah.
 */
const SUMBER_RT = Object.freeze({
  users: 'SELECT 1 FROM users WHERE id = $1 AND rt_id = $2',
  keluarga: 'SELECT 1 FROM keluarga WHERE id = $1 AND rt_id = $2',
  // Master per RT sejak v45 — nominal iuran, tarif air, dan pos belanja
  // adalah keputusan masing-masing RT, bukan registri kode.
  jenis_iuran: 'SELECT 1 FROM jenis_iuran WHERE id = $1 AND rt_id = $2',
  kategori_kas: 'SELECT 1 FROM kategori_kas WHERE id = $1 AND rt_id = $2',
  kategori_bop: 'SELECT 1 FROM kategori_bop WHERE id = $1 AND rt_id = $2',
  inventory: 'SELECT 1 FROM inventory WHERE id = $1 AND rt_id = $2',
  borrowings: 'SELECT 1 FROM borrowings WHERE id = $1 AND rt_id = $2',
  finances: 'SELECT 1 FROM finances WHERE id = $1 AND rt_id = $2',
  bop_finances: 'SELECT 1 FROM bop_finances WHERE id = $1 AND rt_id = $2',
  alokasi_bop: 'SELECT 1 FROM alokasi_bop WHERE id = $1 AND rt_id = $2',
  complaints: 'SELECT 1 FROM complaints WHERE id = $1 AND rt_id = $2',
  letters: 'SELECT 1 FROM letters WHERE id = $1 AND rt_id = $2',
  polling: 'SELECT 1 FROM polling WHERE id = $1 AND rt_id = $2',
  agenda: 'SELECT 1 FROM agenda WHERE id = $1 AND rt_id = $2',
  announcements: 'SELECT 1 FROM announcements WHERE id = $1 AND rt_id = $2',
  visitors: 'SELECT 1 FROM visitors WHERE id = $1 AND rt_id = $2',
  bantuan_sosial: 'SELECT 1 FROM bantuan_sosial WHERE id = $1 AND rt_id = $2',
  emergency_alerts: 'SELECT 1 FROM emergency_alerts WHERE id = $1 AND rt_id = $2',
  // Dilingkupi lewat induknya — lihat catatan di atas.
  bills: `SELECT 1 FROM bills b JOIN keluarga k ON k.id = b.keluarga_id
           WHERE b.id = $1 AND k.rt_id = $2`,
  anggota_keluarga: `SELECT 1 FROM anggota_keluarga ak JOIN keluarga k ON k.id = ak.keluarga_id
           WHERE ak.id = $1 AND k.rt_id = $2`,
});

/**
 * Apakah sebuah baris berada dalam lingkup RT pemanggil.
 *
 * Mengembalikan `true` ketika pemanggil tidak dibatasi (administrator atau
 * ketua RW yang belum memilih RT) — bukan karena longgar, melainkan karena
 * `rtAktif()` sudah memutuskan hal itu satu kali untuk seluruh aplikasi.
 *
 * @param {object} db      pool atau client transaksi
 * @param {object} req     permintaan Express, sudah lewat authMiddleware
 * @param {string} tabel   kunci pada SUMBER_RT
 * @param {string|number} id
 */
async function pastikanDalamRt(db, req, tabel, id) {
  const rt = rtAktif(req);
  if (!rt) return true;

  const sql = SUMBER_RT[tabel];
  // Kunci yang tidak dikenal adalah salah tulis programmer, bukan masukan
  // pengguna. Melempar lebih baik daripada mengembalikan `true` diam-diam:
  // yang terakhir mengubah salah ketik menjadi lubang izin.
  if (!sql) throw new Error(`pastikanDalamRt: tabel '${tabel}' tidak terdaftar.`);

  if (id === undefined || id === null || id === '') return false;

  const hasil = await db.query(sql, [id, rt]);
  return hasil.rowCount > 0;
}

/**
 * Bentuk siap pakai untuk awal pengendali:
 *
 *   if (await tolakLuarRt(pool, req, res, 'keluarga', id)) return;
 *
 * @returns {Promise<boolean>} true bila sudah menjawab 404 dan pemanggil harus berhenti
 */
async function tolakLuarRt(db, req, res, tabel, id) {
  if (await pastikanDalamRt(db, req, tabel, id)) return false;
  res.status(404).json({ success: false, message: 'Data tidak ditemukan.' });
  return true;
}

module.exports = {
  PERAN_LINTAS_RT,
  bolehLintasRt,
  rtAktif,
  klausaRt,
  kondisiRt,
  whereRt,
  rtUntukSimpan,
  SUMBER_RT,
  pastikanDalamRt,
  tolakLuarRt,
};
