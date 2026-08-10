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
const BATAS_POOL = {
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
