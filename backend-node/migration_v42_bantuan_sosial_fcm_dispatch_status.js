require('dotenv').config();
const { assertCanRunMigration } = require('./src/config/db-guard');
assertCanRunMigration('migration_v42_bantuan_sosial_fcm_dispatch_status');

const { pool } = require('./src/config/database');

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v42: penambahan fcm_last_status_dispatch pada tabel bantuan_sosial...');
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE bantuan_sosial
      ADD COLUMN IF NOT EXISTS fcm_last_status_dispatch VARCHAR(50);
    `);

    await client.query('COMMIT');
    console.log('✅ Migrasi v42 selesai: kolom fcm_last_status_dispatch berhasil ditambahkan pada tabel bantuan_sosial.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v42:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
