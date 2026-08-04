require('dotenv').config();
const bcrypt = require('bcryptjs');
const { pool } = require('./src/config/database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS } = require('./src/config/permissions');
const {
  JENIS_IURAN, KATEGORI_KAS, KATEGORI_BOP, ADMIN_AWAL, WARGA_UJI,
} = require('./src/config/master-data');

/**
 * Mengisi menu, hak akses, tabel master, dan akun admin pertama.
 *
 * Langkah kedua (dan terakhir) pemasangan dari nol, setelah `init-db.js`
 * memuat `database/schema.sql`.
 *
 * Menu dan izin sengaja dibaca dari `src/config/permissions.js`, bukan
 * ditulis ulang sebagai INSERT di schema.sql — berkas itu sudah menjadi satu
 * sumber kebenaran yang sama dipakai middleware dan endpoint reset izin.
 * Menyalinnya ke SQL akan menciptakan sumber kedua yang bisa berbeda diam-diam.
 *
 * Idempoten: seluruhnya ON CONFLICT DO NOTHING, jadi menjalankan ulang pada
 * database yang sudah terisi tidak menimpa pengaturan yang sudah diubah admin.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const hasil = {};

    // --- Menu ---------------------------------------------------------------
    let menuBaru = 0;
    for (let i = 0; i < MENU_ITEMS.length; i++) {
      const m = MENU_ITEMS[i];
      const r = await client.query(
        `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (kode) DO UPDATE SET
           nama = EXCLUDED.nama, grup = EXCLUDED.grup,
           menu_index = EXCLUDED.menu_index, urutan = EXCLUDED.urutan,
           is_sistem = EXCLUDED.is_sistem
         RETURNING (xmax = 0) AS disisipkan`,
        [m.kode, m.nama, m.grup, m.menu_index, i, m.is_sistem === true]
      );
      if (r.rows[0].disisipkan) menuBaru++;
    }
    hasil['menu_items'] = `${MENU_ITEMS.length} menu (${menuBaru} baru)`;

    // --- Hak akses ----------------------------------------------------------
    let izinBaru = 0;
    for (const [role, menus] of Object.entries(DEFAULT_PERMISSIONS)) {
      for (const [kode, p] of Object.entries(menus)) {
        const r = await client.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (role, menu_kode) DO UPDATE SET
             can_view = EXCLUDED.can_view,
             can_create = EXCLUDED.can_create,
             can_update = EXCLUDED.can_update,
             can_delete = EXCLUDED.can_delete
           RETURNING id`,
          [role, kode, p.view, p.create, p.update, p.delete]
        );
        if (r.rowCount > 0) izinBaru++;
      }
    }
    hasil['role_permissions'] = `${izinBaru} baris izin baru`;

    // --- Master -------------------------------------------------------------
    let n = 0;
    for (const j of JENIS_IURAN) {
      const r = await client.query(
        `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, is_aktif)
         VALUES ($1, $2, $3, true)
         ON CONFLICT DO NOTHING RETURNING id`,
        [j.nama, j.nominal, j.periode]
      );
      n += r.rowCount;
    }
    hasil['jenis_iuran'] = `${n} baru`;

    n = 0;
    for (const k of KATEGORI_KAS) {
      const r = await client.query(
        `INSERT INTO kategori_kas (nama_kategori, tipe, is_aktif)
         VALUES ($1, $2, true) ON CONFLICT DO NOTHING RETURNING id`,
        [k.nama, k.tipe]
      );
      n += r.rowCount;
    }
    hasil['kategori_kas'] = `${n} baru`;

    n = 0;
    for (const k of KATEGORI_BOP) {
      const r = await client.query(
        `INSERT INTO kategori_bop (nama_kategori, tipe, is_aktif)
         VALUES ($1, $2, true) ON CONFLICT DO NOTHING RETURNING id`,
        [k.nama, k.tipe]
      );
      n += r.rowCount;
    }
    hasil['kategori_bop'] = `${n} baru`;

    // --- Akun bawaan --------------------------------------------------------
    // Dilewati bila emailnya sudah ada, sehingga menjalankan ulang skrip ini
    // pada database yang sudah terisi tidak menggandakan akun atau menimpa
    // password yang sudah diganti.
    const dibuat = [];
    let dirapikan = 0;
    for (const akun of [ADMIN_AWAL, WARGA_UJI]) {
      const ada = await client.query('SELECT 1 FROM users WHERE email = $1', [akun.email]);
      if (ada.rowCount === 0) {
        const hash = await bcrypt.hash(akun.password, 10);
        await client.query(
          `INSERT INTO users (nama, email, username, password_hash, role, is_active)
           VALUES ($1, $2, $3, $4, $5, true)`,
          [akun.nama, akun.email, akun.username || akun.email, hash, akun.role]
        );
        dibuat.push(akun);
        continue;
      }

      // Akun sudah ada: password TIDAK disentuh, tetapi `username` dirapikan.
      //
      // Baris admin pada pemasangan lama masih menyimpan `admin_developer`
      // warisan `database/migrations-lama/fix-db.js` — nilai yang tidak lagi
      // dihasilkan seed mana pun, dan yang tampil apa adanya di layar Profil
      // Saya. Login tetap aman karena mencocokkan `email = $1 OR username = $1`.
      if (akun.username) {
        const r = await client.query(
          'UPDATE users SET username = $1 WHERE email = $2 AND username IS DISTINCT FROM $1',
          [akun.username, akun.email]
        );
        dirapikan += r.rowCount;
      }
    }
    hasil['users'] = [
      dibuat.length ? `${dibuat.length} akun dibuat` : 'akun bawaan sudah ada',
      dirapikan > 0 ? `${dirapikan} username dirapikan` : null,
    ]
      .filter(Boolean)
      .join(', ');

    await client.query('COMMIT');

    console.log('Seed master berhasil:');
    for (const [k, v] of Object.entries(hasil)) {
      console.log(`  ${k.padEnd(20)} ${v}`);
    }
    if (dibuat.length) {
      console.log('\n  Kredensial bawaan:');
      for (const a of dibuat) {
        console.log(`    ${a.role.padEnd(6)} ${a.email} / ${a.password}`);
      }
      console.log('\n  PENTING: ganti password ini sebelum dipakai sungguhan.');
    }
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed master gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
