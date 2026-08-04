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
    const schemaPath = path.join(__dirname, '..', '..', 'database', 'schema.sql');
    if (fs.existsSync(schemaPath)) {
      const sql = fs.readFileSync(schemaPath, 'utf8');
      await pool.query(sql);
      console.log('✅ Skema tabel database PostgreSQL terverifikasi.');
    }
  } catch (e) {
    console.log('ℹ️ Catatan Skema (Lanjut):', e.message);
  }

  // 2. Menu items
  try {
    for (let i = 0; i < MENU_ITEMS.length; i++) {
      const m = MENU_ITEMS[i];
      await pool.query(
        `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (kode) DO UPDATE SET
           nama = EXCLUDED.nama, grup = EXCLUDED.grup,
           menu_index = EXCLUDED.menu_index, urutan = EXCLUDED.urutan,
           is_sistem = EXCLUDED.is_sistem`,
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
           ON CONFLICT (role, menu_kode) DO NOTHING`,
          [role, kode, p.view, p.create, p.update, p.delete]
        );
      }
    }
  } catch (e) {
    console.log('ℹ️ Catatan Permission:', e.message);
  }

  // 4. ALWAYS Upsert Admin User (Email: admin@example.com, Username: Developer & admin, Pass: admin123)
  try {
    const saltAdmin = await bcrypt.genSalt(10);
    const hashAdmin = await bcrypt.hash('admin123', saltAdmin);

    // Upsert email admin@example.com
    await pool.query(
      `INSERT INTO users (nama, email, username, password_hash, role, is_active)
       VALUES ($1, $2, $3, $4, $5, true)
       ON CONFLICT (email) DO UPDATE SET
         password_hash = EXCLUDED.password_hash,
         role = 'admin',
         is_active = true`,
      ['Administrator', 'admin@example.com', 'Developer', hashAdmin, 'admin']
    );

    // Also ensure username 'admin' or 'Developer' is upserted if searching by username
    await pool.query(
      `INSERT INTO users (nama, email, username, password_hash, role, is_active)
       VALUES ($1, $2, $3, $4, $5, true)
       ON CONFLICT (username) DO UPDATE SET
         password_hash = EXCLUDED.password_hash,
         role = 'admin',
         is_active = true`,
      ['Administrator Secondary', 'admin_dev@example.com', 'admin', hashAdmin, 'admin']
    );

    console.log('✅ Akun Admin berhasil ditanam dan diaktifkan (admin@example.com / admin123).');
  } catch (e) {
    console.error('❌ Admin Upsert Error:', e.message);
  }

  // 5. ALWAYS Upsert Warga User (Email: warga@example.com, NIK: 3171010101010001, Pass: 123456)
  try {
    const saltWarga = await bcrypt.genSalt(10);
    const hashWarga = await bcrypt.hash('123456', saltWarga);
    await pool.query(
      `INSERT INTO users (nama, email, username, nik, password_hash, role, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, true)
       ON CONFLICT (email) DO UPDATE SET
         password_hash = EXCLUDED.password_hash,
         is_active = true`,
      ['Warga Uji Coba', 'warga@example.com', 'warga', '3171010101010001', hashWarga, 'warga']
    );
    console.log('✅ Akun Warga berhasil ditanam dan diaktifkan (warga@example.com / 123456).');
  } catch (e) {
    console.error('❌ Warga Upsert Error:', e.message);
  }

  // 6. Seed dummy inventory
  try {
    const invCheck = await pool.query("SELECT id FROM inventory LIMIT 1");
    if (invCheck.rows.length === 0) {
      const dummyItems = [
        { nama_barang: 'Tenda Lipat 3x3 Meter', kategori: 'Peralatan Acara', jumlah: 5, kondisi: 'Baik', lokasi: 'Gudang Balai RT', nilai_barang: 450000, keterangan: 'Tenda acara outdoor warga' },
        { nama_barang: 'Kursi Plastik Napolly', kategori: 'Peralatan Acara', jumlah: 50, kondisi: 'Baik', lokasi: 'Gudang Balai RT', nilai_barang: 65000, keterangan: 'Set kursi rapat & hajatan' },
        { nama_barang: 'Sound System Portable + Wireless Mic', kategori: 'Elektronik', jumlah: 2, kondisi: 'Baik', lokasi: 'Rumah Ketua RT', nilai_barang: 1200000, keterangan: 'Speaker & 2 mic wireless' },
        { nama_barang: 'HT (Handy Talkie) Baofeng', kategori: 'Perlengkapan Keamanan', jumlah: 8, kondisi: 'Baik', lokasi: 'Pos Satpam RT', nilai_barang: 250000, keterangan: 'Frekuensi siskamling RT 05' },
      ];
      for (const item of dummyItems) {
        await pool.query(
          `INSERT INTO inventory (nama_barang, kategori, jumlah, kondisi, lokasi, nilai_barang, keterangan, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())`,
          [item.nama_barang, item.kategori, item.jumlah, item.kondisi, item.lokasi, item.nilai_barang, item.keterangan]
        );
      }
      console.log('✅ Data barang ready terisi.');
    }
  } catch (e) {
    console.log('ℹ️ Catatan Inventaris:', e.message);
  }
}

module.exports = { autoSetupCloud };
