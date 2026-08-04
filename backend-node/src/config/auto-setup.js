const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { pool } = require('./database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS } = require('./permissions');
const { ADMIN_AWAL } = require('./master-data');

async function autoSetupCloud() {
  try {
    console.log('🔄 Memeriksa & menginisialisasi database PostgreSQL...');
    const schemaPath = path.join(__dirname, '..', '..', 'database', 'schema.sql');
    if (fs.existsSync(schemaPath)) {
      const sql = fs.readFileSync(schemaPath, 'utf8');
      await pool.query(sql);
      console.log('✅ Skema tabel database PostgreSQL terverifikasi.');
    }

    // Check if admin user exists
    const adminCheck = await pool.query("SELECT id FROM users WHERE role = 'admin' LIMIT 1");
    if (adminCheck.rows.length === 0) {
      console.log('🌱 Menanam data master & akun administrator awal...');
      for (let i = 0; i < MENU_ITEMS.length; i++) {
        const m = MENU_ITEMS[i];
        await pool.query(
          `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (kode) DO NOTHING`,
          [m.kode, m.nama, m.grup, m.menu_index, i, m.is_sistem === true]
        );
      }
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
      const salt = await bcrypt.genSalt(10);
      const hash = await bcrypt.hash(ADMIN_AWAL.password, salt);
      await pool.query(
        `INSERT INTO users (nama, email, username, password_hash, role)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (email) DO NOTHING`,
        [ADMIN_AWAL.nama, ADMIN_AWAL.email, ADMIN_AWAL.username, hash, ADMIN_AWAL.role]
      );
      console.log(`✅ Akun Admin (${ADMIN_AWAL.email} / ${ADMIN_AWAL.password}) berhasil ditanam.`);
    }

    // Check if inventory data exists
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
  } catch (err) {
    console.error('⚠️ AutoSetup Error:', err.message);
  }
}

module.exports = { autoSetupCloud };
