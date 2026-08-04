require('dotenv').config();
const { pool } = require('./src/config/database');

async function run() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS bantuan_sosial_log (
          id SERIAL PRIMARY KEY,
          bantuan_sosial_id INT REFERENCES bantuan_sosial(id) ON DELETE CASCADE,
          changed_by UUID REFERENCES users(id) ON DELETE SET NULL,
          old_status VARCHAR(50),
          new_status VARCHAR(50),
          keterangan_log TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log('Successfully created bantuan_sosial_log table.');
    process.exit(0);
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  }
}
run();
