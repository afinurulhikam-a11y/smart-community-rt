const { Pool } = require('pg');

const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DB_SSL === 'true' || process.env.NODE_ENV === 'production'
        ? { rejectUnauthorized: false }
        : false,
    })
  : new Pool({
      user: process.env.DB_USER || process.env.PGUSER,
      host: process.env.DB_HOST || process.env.PGHOST,
      database: process.env.DB_NAME || process.env.PGDATABASE,
      password: process.env.DB_PASSWORD || process.env.PGPASSWORD,
      port: process.env.DB_PORT || process.env.PGPORT || 5432,
    });

// Test koneksi secara aktif saat startup
async function testConnection() {
  try {
    const res = await pool.query('SELECT NOW()');
    console.log('✅ Terhubung ke PostgreSQL —', res.rows[0].now);
  } catch (err) {
    console.error('❌ Gagal terhubung ke PostgreSQL:', err.message);
  }
}

pool.on('error', (err) => {
  console.error('❌ PostgreSQL Pool Error:', err.message);
});

module.exports = { pool, testConnection };
