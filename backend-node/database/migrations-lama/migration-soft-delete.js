require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration-soft-delete');

const { pool } = require('../../src/config/database');

async function up() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    console.log('Adding deleted_at to users...');
    await client.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');
    
    console.log('Adding deleted_at to keluarga...');
    await client.query('ALTER TABLE keluarga ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');
    
    console.log('Adding deleted_at to inventory...');
    await client.query('ALTER TABLE inventory ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;');

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
