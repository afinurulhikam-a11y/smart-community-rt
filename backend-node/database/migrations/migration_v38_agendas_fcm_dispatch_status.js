require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v38_agendas_fcm_dispatch_status');

const { pool } = require('../../src/config/database');

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v38: penambahan fcm_dispatch_status pada tabel agenda...');
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE agenda
      ADD COLUMN IF NOT EXISTS fcm_dispatch_status VARCHAR(20) DEFAULT 'unsent';
    `);

    await client.query('COMMIT');
    console.log('✅ Migrasi v38 selesai: kolom fcm_dispatch_status berhasil ditambahkan pada tabel agenda.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v38:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
