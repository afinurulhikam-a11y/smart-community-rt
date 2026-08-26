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

module.exports = {
  PERAN_LINTAS_RT,
  bolehLintasRt,
  rtAktif,
  klausaRt,
  kondisiRt,
  whereRt,
  rtUntukSimpan,
};
