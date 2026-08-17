require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v11_hak_akses');

const { pool } = require('../../src/config/database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS } = require('./src/config/permissions');

/**
 * Migrasi v11 — Menu & Hak Akses per Role.
 *
 * Sebelum ini, 52 rute memakai roleGuard('admin','pengurus_rt') dan middleware
 * memperluas 'pengurus_rt' menjadi ketua_rt + sekretaris + bendahara, sehingga
 * ketiga role itu punya akses yang SAMA PERSIS. Sidebar sudah membedakan, tapi
 * menyembunyikan menu bukan kontrol akses.
 *
 * Dua tabel di bawah memindahkan pembagian akses ke database supaya bisa
 * diatur admin, sambil menjaga admin tidak mungkin terkunci: menu ber-is_sistem
 * tidak bisa diberikan ke role lain, dan middleware meloloskan admin lebih dulu
 * tanpa membaca tabel sama sekali.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS menu_items (
        id SERIAL PRIMARY KEY,
        kode VARCHAR(60) UNIQUE NOT NULL,
        nama VARCHAR(100) NOT NULL,
        grup VARCHAR(50),
        menu_index INT,
        urutan INT DEFAULT 0,
        is_aktif BOOLEAN DEFAULT true,
        is_sistem BOOLEAN DEFAULT false
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS role_permissions (
        id SERIAL PRIMARY KEY,
        role VARCHAR(30) NOT NULL,
        menu_kode VARCHAR(60) NOT NULL REFERENCES menu_items(kode) ON DELETE CASCADE,
        can_view BOOLEAN DEFAULT false,
        can_create BOOLEAN DEFAULT false,
        can_update BOOLEAN DEFAULT false,
        can_delete BOOLEAN DEFAULT false,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (role, menu_kode)
      );
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS role_permissions_lookup
        ON role_permissions (role, menu_kode);
    `);

    // Menu: DO UPDATE agar penamaan/urutan ikut terbarui bila daftar di
    // permissions.js berubah, tanpa menyentuh izin yang sudah diatur admin.
    let menuBaru = 0;
    for (let i = 0; i < MENU_ITEMS.length; i++) {
      const m = MENU_ITEMS[i];
      const r = await client.query(
        `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (kode) DO UPDATE SET
           nama = EXCLUDED.nama,
           grup = EXCLUDED.grup,
           menu_index = EXCLUDED.menu_index,
           urutan = EXCLUDED.urutan,
           is_sistem = EXCLUDED.is_sistem
         RETURNING (xmax = 0) AS disisipkan`,
        [m.kode, m.nama, m.grup, m.menu_index, i, m.is_sistem === true]
      );
      if (r.rows[0].disisipkan) menuBaru++;
    }

    // Izin: DO NOTHING supaya menjalankan ulang migrasi tidak menimpa
    // pengaturan yang sudah diubah admin lewat layar.
    let izinBaru = 0;
    for (const [role, menus] of Object.entries(DEFAULT_PERMISSIONS)) {
      for (const [kode, p] of Object.entries(menus)) {
        const r = await client.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (role, menu_kode) DO NOTHING
           RETURNING id`,
          [role, kode, p.view, p.create, p.update, p.delete]
        );
        if (r.rowCount > 0) izinBaru++;
      }
    }

    await client.query('COMMIT');
    console.log(
      `Migrasi v11 berhasil: ${MENU_ITEMS.length} menu (${menuBaru} baru), ` +
      `${izinBaru} baris izin baru ditambahkan.`
    );
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v11 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
