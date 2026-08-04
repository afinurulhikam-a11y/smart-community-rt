const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { pool } = require('./database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS } = require('./permissions');
const { ADMIN_AWAL } = require('./master-data');

async function autoSetupCloud() {
  console.log('🔄 Memeriksa & menginisialisasi database PostgreSQL...');

  // 1. Skema database (Abaikan jika tabel sudah ada)
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS patrol_schedules (
        id SERIAL PRIMARY KEY,
        hari VARCHAR(20) NOT NULL,
        shift VARCHAR(50) DEFAULT 'Shift Malam (22:00 - 04:00)',
        petugas_warga TEXT NOT NULL,
        keterangan TEXT,
        created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS patrol_attendances (
        id SERIAL PRIMARY KEY,
        schedule_id INTEGER REFERENCES patrol_schedules(id) ON DELETE SET NULL,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        nama_petugas VARCHAR(150) NOT NULL,
        tanggal DATE DEFAULT CURRENT_DATE,
        waktu_scan TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        lokasi_pos VARCHAR(150) DEFAULT 'Pos Ronda Utama',
        status VARCHAR(50) DEFAULT 'Hadir',
        catatan TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log('✅ Skema tabel Siskamling (patrol_schedules & patrol_attendances) terverifikasi.');
  } catch (e) {
    console.log('ℹ️ Catatan Skema (Lanjut):', e.message);
  }

  // 2. Menu items
  try {
    for (let i = 0; i < MENU_ITEMS.length; i++) {
      const m = MENU_ITEMS[i];
      await pool.query(
        `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem, is_aktif)
         VALUES ($1, $2, $3, $4, $5, $6, true)
         ON CONFLICT (kode) DO UPDATE SET
           nama = EXCLUDED.nama, grup = EXCLUDED.grup,
           menu_index = EXCLUDED.menu_index, urutan = EXCLUDED.urutan,
           is_sistem = EXCLUDED.is_sistem, is_aktif = true`,
        [m.kode, m.nama, m.grup, m.menu_index, i, m.is_sistem === true]
      );
    }
  } catch (e) {
    console.log('ℹ️ Catatan Menu:', e.message);
  }

  // 3. Permissions
  try {
    for (const [role, menus] of Object.entries(DEFAULT_PERMISSIONS)) {
      for (const [kode, p] of Object.entries(menus)) {
        await pool.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (role, menu_kode) DO UPDATE SET
             can_view = EXCLUDED.can_view,
             can_create = EXCLUDED.can_create,
             can_update = EXCLUDED.can_update,
             can_delete = EXCLUDED.can_delete`,
          [role, kode, p.view, p.create, p.update, p.delete]
        );
      }
    }
  } catch (e) {
    console.log('ℹ️ Catatan Permission:', e.message);
  }

  // 4. ALWAYS Upsert Single Administrator Account (Username: Administrator, Email: null, Pass: admin123)
  try {
    const saltAdmin = await bcrypt.genSalt(10);
    const hashAdmin = await bcrypt.hash('admin123', saltAdmin);

    await pool.query(
      `INSERT INTO users (nama, email, username, password_hash, role, is_active)
       VALUES ($1, NULL, $2, $3, $4, true)
       ON CONFLICT (username) DO UPDATE SET
         nama = EXCLUDED.nama,
         email = NULL,
         password_hash = EXCLUDED.password_hash,
         role = 'admin',
         is_active = true`,
      ['Administrator', 'Administrator', hashAdmin, 'admin']
    );

    console.log('✅ Akun Admin tunggal terverifikasi (Username: Administrator / Pass: admin123).');
  } catch (e) {
    console.error('❌ Admin Upsert Error:', e.message);
  }

  // 5. Seed Master Categories (Jenis Iuran, Kategori Kas, Kategori BOP)
  try {
    const { JENIS_IURAN, KATEGORI_KAS, KATEGORI_BOP } = require('./master-data');

    for (const j of JENIS_IURAN) {
      await pool.query(
        `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, is_aktif)
         VALUES ($1, $2, $3, true)
         ON CONFLICT DO NOTHING`,
        [j.nama, j.nominal, j.periode]
      );
    }

    for (const k of KATEGORI_KAS) {
      await pool.query(
        `INSERT INTO kategori_kas (nama_kategori, tipe, is_aktif)
         VALUES ($1, $2, true)
         ON CONFLICT DO NOTHING`,
        [k.nama, k.tipe]
      );
    }

    for (const k of KATEGORI_BOP) {
      await pool.query(
        `INSERT INTO kategori_bop (nama_kategori, tipe, is_aktif)
         VALUES ($1, $2, true)
         ON CONFLICT DO NOTHING`,
        [k.nama, k.tipe]
      );
    }
    console.log('✅ Master Kategori Kas, BOP, dan Jenis Iuran terverifikasi.');
  } catch (e) {
    console.log('ℹ️ Catatan Master Categories:', e.message);
  }
}

module.exports = { autoSetupCloud };
