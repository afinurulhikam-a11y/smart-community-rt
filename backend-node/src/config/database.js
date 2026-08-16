const { Pool } = require('pg');

/**
 * Batas pool, disetel eksplisit.
 *
 * Tanpa ini `pg` memakai bawaannya (max 10) tanpa ada yang menyadarinya. Itu
 * tidak selalu salah, tetapi menjadi masalah bila digabung dengan dua hal yang
 * memang ada di sistem ini:
 *
 *   - Impor Excel memegang SATU koneksi selama seluruh impor berjalan, dengan
 *     3–5 kueri berurutan per baris di dalam satu transaksi terbuka.
 *   - authMiddleware kini memeriksa akun ke database pada setiap permintaan.
 *
 * `connectionTimeoutMillis` adalah bagian terpentingnya: tanpa batas itu,
 * permintaan yang menunggu koneksi akan menggantung tanpa akhir, dan gejalanya
 * di aplikasi berupa layar yang diam — bukan pesan galat. Lebih baik gagal
 * cepat dengan alasan yang jelas.
 */
/**
* Zona waktu bisnis, dipaksakan pada SETIAP koneksi pool.
 *
 * ===================================================================
 * Masalah yang ditutup
 * ===================================================================
 *
 * Hampir seluruh kolom waktu di skema ini bertipe `timestamp WITHOUT time
 * zone`, dan diisi `CURRENT_TIMESTAMP` / `NOW()`. Tipe itu tidak menyimpan
 * zona sama sekali — yang tersimpan adalah "jam dinding" menurut zona SESI
 * yang sedang berjalan.
 *
 * Di mesin pengembangan ini, Postgres mewarisi `Asia/Bangkok` (UTC+7) dari
 * locale sistem, sehingga nilainya kebetulan sudah WIB. Di Railway zonanya
 * `UTC`, sehingga baris yang sama tersimpan TUJUH JAM lebih awal — dan
 * "darurat pukul 21.10" tampil sebagai pukul 14.10 tanpa satu pun galat.
 *
 * Kebetulan yang benar di satu mesin dan salah di mesin lain adalah bentuk
 * kesalahan yang paling sulit ditemukan, karena pengujian lokal selalu lulus.
 *
 * ===================================================================
 * Kenapa menyetel zona sesi, bukan mengubah tipe kolom
 * ===================================================================
 *
 * Mengubah kolom menjadi `timestamptz` adalah perbaikan yang lebih dalam,
 * tetapi menyentuh SETIAP tabel yang punya `created_at`, menuntut migrasi
 * konversi, penangkapan ulang `schema.sql`, dan penafsiran ulang seluruh baris
 * lama. Untuk keuntungan praktis yang sama, radius kerusakannya jauh lebih
 * besar.
 *
 * Menyetel zona sesi tidak mengubah satu pun tipe, tidak menyentuh satu pun
 * baris lama, dan berlaku seragam di lokal maupun Railway.
 *
 * ===================================================================
 * Yang TIDAK diperbaiki olehnya, dan itu harus diketahui
 * ===================================================================
 *
 * Baris yang TERLANJUR ditulis di Railway dengan zona UTC tetap tertinggal
 * tujuh jam. Perbaikan ini berlaku ke depan saja. Memperbaiki baris lama
 * menuntut pengetahuan tentang zona apa yang berlaku saat setiap baris ditulis
 * — dan menebaknya berarti merusak data yang sebetulnya sudah benar.
 *
 * Efeknya juga menyeluruh, bukan hanya modul darurat: setiap `NOW()`,
 * `CURRENT_TIMESTAMP`, dan `CURRENT_DATE` kini memakai WIB. Untuk aplikasi RT
 * itu justru yang benar — dan ia sekaligus menutup kelas kesalahan yang sudah
 * dicatat proyek ini, yaitu "tanggal 25" pada penjadwal tagihan yang bergeser
 * tujuh jam ketika server berjalan di UTC.
 *
 * ===================================================================
 * Bagaimana ia dipasang
 * ===================================================================
 *
 *
 * `options: '-c timezone=...'` disetel oleh SERVER saat koneksi dibangun,
 * sebelum satu pun kueri berjalan.
 *
 * Percobaan pertama memakai `pool.on('connect')` yang menjalankan
 * `SET TIME ZONE`, dan itu KELIRU: handler-nya berjalan bersamaan dengan kueri
 * pemanggil, sehingga kueri pertama pada koneksi baru bisa lolos sebelum
 * zonanya sempat disetel. node-postgres bahkan memperingatkannya
 * ("client.query() when the client is already executing a query") dan akan
 * menolaknya sama sekali di pg@9.
 */
const ZONA_BISNIS = process.env.DB_TIMEZONE || 'Asia/Jakarta';

const BATAS_POOL = {
  options: `-c timezone=${ZONA_BISNIS}`,
  max: parseInt(process.env.DB_POOL_MAX, 10) || 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
};

const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DB_SSL === 'true' || process.env.NODE_ENV === 'production'
        ? { rejectUnauthorized: false }
        : false,
      ...BATAS_POOL,
    })
  : new Pool({
      user: process.env.DB_USER || process.env.PGUSER,
      host: process.env.DB_HOST || process.env.PGHOST,
      database: process.env.DB_NAME || process.env.PGDATABASE,
      password: process.env.DB_PASSWORD || process.env.PGPASSWORD,
      port: process.env.DB_PORT || process.env.PGPORT || 5432,
      ...BATAS_POOL,
    });

// Test koneksi secara aktif saat startup
async function testConnection() {
  try {
    const res = await pool.query('SELECT NOW()');
    console.log('✅ Terhubung ke PostgreSQL —', res.rows[0].now);
    await pool.query('ALTER TABLE keluarga ALTER COLUMN langganan_sampah SET DEFAULT false').catch(() => {});
  } catch (err) {
    console.error('❌ Gagal terhubung ke PostgreSQL:', err.message);
  }
}

pool.on('error', (err) => {
  console.error('❌ PostgreSQL Pool Error:', err.message);
});

module.exports = { pool, testConnection };
