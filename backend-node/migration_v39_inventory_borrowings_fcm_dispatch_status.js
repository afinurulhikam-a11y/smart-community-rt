require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v39_inventory_borrowings_fcm_dispatch_status');

const { pool } = require('./src/config/database');

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v39: penambahan fcm_last_status_dispatch pada tabel borrowings...');
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE borrowings
      ADD COLUMN IF NOT EXISTS fcm_last_status_dispatch VARCHAR(50);
    `);

    await client.query('COMMIT');
    console.log('✅ Migrasi v39 selesai: kolom fcm_last_status_dispatch berhasil ditambahkan pada tabel borrowings.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v39:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
