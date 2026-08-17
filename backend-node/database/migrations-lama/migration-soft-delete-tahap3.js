require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration-soft-delete-tahap3');

const { pool } = require('../../src/config/database');

async function up() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    console.log('Adding deleted_at to complaints...');
    await client.query('ALTER TABLE complaints ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');
    
    console.log('Adding deleted_at to letters...');
    await client.query('ALTER TABLE letters ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');
    
    console.log('Adding deleted_at to agenda...');
    await client.query('ALTER TABLE agenda ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');

    console.log('Adding deleted_at to finances...');
    await client.query('ALTER TABLE finances ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');

    await client.query('COMMIT');
    console.log('Migration successful.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migration failed:', err);
  } finally {
    client.release();
    pool.end();
  }
}

up();
