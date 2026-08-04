require('dotenv').config();
const { pool } = require('./src/config/database');

async function migrate() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    // Add columns if they don't exist
    await client.query(`
      ALTER TABLE anggota_keluarga 
      ADD COLUMN IF NOT EXISTS domisili VARCHAR(50) DEFAULT 'Tetap',
      ADD COLUMN IF NOT EXISTS is_aktif BOOLEAN DEFAULT true;
    `);

    // Update existing schema file (optional, but good practice)
    await client.query('COMMIT');
    console.log('Migration successful!');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migration failed:', err);
  } finally {
    client.release();
    pool.end();
  }
}

migrate();
