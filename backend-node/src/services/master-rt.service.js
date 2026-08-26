const {
  JENIS_IURAN, KATEGORI_KAS, KATEGORI_BOP,
} = require('../config/master-data');

/**
 * Menyiapkan tabel master milik sebuah RT.
 *
 * ===================================================================
 * Kenapa tiap RT punya salinannya sendiri
 * ===================================================================
 *
 * `jenis_iuran`, `kategori_kas`, dan `kategori_bop` adalah tabel yang DIEDIT
 * pengurus dari layar — bukan registri kode seperti `menu_items`. Nominal
 * iuran, tarif air, dan daftar pos belanja adalah keputusan masing-masing RT,
 * dan satu RT tidak boleh bisa mengubah angka yang dipakai RT lain menagih
 * warganya.
 *
 * Migrasi v43 sudah memberi ketiganya kolom `rt_id`, tetapi seluruh barisnya
 * jatuh ke RT bawaan dan pengendalinya tidak pernah menyaring. Yang menghalangi
 * pemisahannya bukan pengendali itu melainkan sebuah indeks:
 * `jenis_iuran_nama_iuran_key` unik atas NAMA saja, se-basis-data. Selama ia
 * ada, RT 002 tidak bisa punya "Iuran Keamanan" karena RT 001 sudah punya.
 * v45 menggantinya dengan `UNIQUE (rt_id, nama)`.
 *
 * ===================================================================
 * Kenapa RT baru diisi dari master-data.js, bukan disalin dari RT lain
 * ===================================================================
 *
 * Menyalin dari RT yang sudah jalan terasa lebih membantu, tetapi berarti RT
 * baru mewarisi keputusan tetangganya — termasuk pos belanja yang hanya masuk
 * akal di sana ("Iuran Gang Mawar"), dan tarif air yang bisa saja berbeda.
 * Daftar bawaan dapat ditambah sendiri dari layar master; yang tidak bisa
 * dibatalkan adalah pengurus yang tidak sadar sedang memakai angka RT lain.
 *
 * Migrasi v45 memang menyalin dari RT bawaan, dan itu keadaan yang berbeda:
 * di sana sudah ADA baris operasional yang menunjuk master milik RT bawaan,
 * dan penunjukan itu hanya bisa dialihkan bila nama yang sama tersedia di RT
 * tujuan. Menyalin adalah satu-satunya cara memastikannya.
 *
 * Idempoten lewat `ON CONFLICT DO NOTHING` di atas indeks unik yang baru, jadi
 * aman dipanggil ulang untuk RT yang sudah punya isinya.
 *
 * @param {object} db      pool atau client transaksi
 * @param {string} rtId    RT yang akan diisi
 * @returns {Promise<{jenis_iuran:number, kategori_kas:number, kategori_bop:number}>}
 */
async function siapkanMasterRt(db, rtId) {
  const hasil = { jenis_iuran: 0, kategori_kas: 0, kategori_bop: 0 };
  if (!rtId) return hasil;

  for (const j of JENIS_IURAN) {
    const r = await db.query(
      `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, is_aktif,
                                tipe_hitung, tarif_per_m3, abondement, biaya_sampah, rt_id)
       VALUES ($1, $2, $3, true, $4, $5, $6, $7, $8)
       ON CONFLICT DO NOTHING`,
      [
        j.nama, j.nominal, j.periode,
        j.tipe_hitung || 'tetap', j.tarif_per_m3 || null,
        j.abondement || 0, j.biaya_sampah || 0, rtId,
      ]
    );
    hasil.jenis_iuran += r.rowCount;
  }

  for (const k of KATEGORI_KAS) {
    const r = await db.query(
      `INSERT INTO kategori_kas (nama_kategori, tipe, is_aktif, rt_id)
       VALUES ($1, $2, true, $3) ON CONFLICT DO NOTHING`,
      [k.nama, k.tipe, rtId]
    );
    hasil.kategori_kas += r.rowCount;
  }

  for (const k of KATEGORI_BOP) {
    const r = await db.query(
      `INSERT INTO kategori_bop (nama_kategori, tipe, is_aktif, rt_id)
       VALUES ($1, $2, true, $3) ON CONFLICT DO NOTHING`,
      [k.nama, k.tipe, rtId]
    );
    hasil.kategori_bop += r.rowCount;
  }

  return hasil;
}

module.exports = { siapkanMasterRt };
