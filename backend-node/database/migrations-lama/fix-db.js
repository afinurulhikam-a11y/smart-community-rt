require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('fix-db');

const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

async function fixDB() {
  const client = new Client({
    user: 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
    host: 'localhost',
    port: 5432,
    database: 'smart_community_rt'
  });

  try {
    await client.connect();
    console.log("Connected. Fixing database...");

    // 1. Add missing columns to users table
    await client.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS nama VARCHAR(255);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS email VARCHAR(255) UNIQUE;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS no_hp VARCHAR(20);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS no_kk VARCHAR(16);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS alamat TEXT;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS no_rt VARCHAR(3) DEFAULT '001';
      ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'warga';
    `);

    // 2. Create missing tables
    await client.query(`
      CREATE TABLE IF NOT EXISTS bills (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID REFERENCES users(id),
        jenis_tagihan VARCHAR(50) NOT NULL,
        bulan VARCHAR(7) NOT NULL,
        nominal NUMERIC NOT NULL,
        keterangan TEXT,
        status VARCHAR(20) DEFAULT 'unpaid',
        created_by UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS bill_payments (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        bill_id UUID REFERENCES bills(id),
        user_id UUID REFERENCES users(id),
        jumlah_bayar NUMERIC NOT NULL,
        metode_bayar VARCHAR(50) NOT NULL,
        invoice_number VARCHAR(100) NOT NULL,
        paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS finances (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        tipe VARCHAR(20) NOT NULL,
        kategori VARCHAR(50) NOT NULL,
        jumlah NUMERIC NOT NULL,
        deskripsi TEXT,
        tanggal DATE DEFAULT CURRENT_DATE,
        created_by UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS bop_finances (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        tipe VARCHAR(20) NOT NULL,
        jumlah NUMERIC NOT NULL,
        deskripsi TEXT,
        tanggal DATE DEFAULT CURRENT_DATE,
        created_by UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS emergency_alerts (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID REFERENCES users(id),
        message TEXT,
        latitude NUMERIC,
        longitude NUMERIC,
        status VARCHAR(20) DEFAULT 'active',
        dismissed_by UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS letters (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID REFERENCES users(id),
        jenis_surat VARCHAR(100) NOT NULL,
        keperluan TEXT NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        approved_by UUID REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS sensor_logs (
        id SERIAL PRIMARY KEY,
        sensor_type VARCHAR(50) NOT NULL,
        value NUMERIC NOT NULL,
        unit VARCHAR(20),
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // 3. Execute migration_v2.sql
    const migrationSQL = fs.readFileSync(path.join(__dirname, 'database', 'migration_v2.sql'), 'utf8');
    console.log("Applying migration_v2.sql...");
    await client.query(migrationSQL);
    
    // 4. Update the seeded user to match the controller expectation
    await client.query(`
      UPDATE users SET email = 'admin@example.com', password_hash = password, role = 'admin', nama = 'Administrator'
      WHERE username = 'admin_developer';

      UPDATE users SET email = 'budi@example.com', password_hash = password, role = 'warga', nama = 'Budi Santoso'
      WHERE username = 'warga_budi';

      UPDATE users SET email = 'warga@example.com', password_hash = password, role = 'warga', nama = 'Siti Aminah'
      WHERE username = 'warga_siti';
    `);

    console.log("Database fixed successfully!");
  } catch (err) {
    console.error("Error fixing database:", err);
  } finally {
    await client.end();
  }
}

fixDB();
