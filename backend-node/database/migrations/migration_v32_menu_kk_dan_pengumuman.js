/**
 * Memisahkan Data KK menjadi izin sendiri, dan meleburkan Pengumuman.
 *
 * ===================================================================
 * Dua perubahan, arah berlawanan
 * ===================================================================
 *
 * TAMBAH `kependudukan.kk`. Data KK selama ini menumpang
 * `kependudukan.warga`, sehingga tidak ada cara membuka Data Warga tanpa ikut
 * membuka Data KK. Keduanya kewenangan berbeda: menyunting anggota keluarga
 * tidak sama dengan menyusun ulang kartu keluarganya. Seluruh `/api/families`
 * kini dijaga izin baru ini.
 *
 * HAPUS `kegiatan.pengumuman`. Pengumuman sudah menjadi tab keempat di dalam
 * layar Agenda & Kegiatan, jadi izin terpisah hanya melahirkan keadaan yang
 * tidak bisa dijelaskan: layar boleh dibuka, satu tab di dalamnya menjawab
 * 403. `announcement.routes.js` kini dijaga `kegiatan.agenda`.
 *
 * ===================================================================
 * Kenapa peleburannya tidak mencabut akses siapa pun
 * ===================================================================
 *
 * Pada matriks bawaan, nilai `kegiatan.agenda` dan `kegiatan.pengumuman`
 * SUDAH identik untuk kelima peran (ketua F/F, sekretaris F/F, bendahara V/V,
 * warga V/V, admin penuh). Jadi memindahkan penjagaan rute dari yang satu ke
 * yang lain tidak menambah maupun mengurangi kewenangan.
 *
 * Yang TIDAK bisa dijamin migrasi ini: bila administrator pernah menyetel
 * pengumuman berbeda dari agenda lewat layar Menu & Akses, setelan itu ikut
 * hilang bersama barisnya. Karena itu selisihnya DILAPORKAN sebelum dihapus —
 * supaya keputusannya terlihat, bukan terjadi diam-diam.
 *
 * ===================================================================
 * Idempoten
 * ===================================================================
 *
 * Aman dijalankan berulang. Penambahan memakai ON CONFLICT DO NOTHING untuk
 * izin (setelan administrator tidak ditimpa) dan menyegarkan metadata menu
 * yang memang milik kode. `urutan` ikut disegarkan agar layar Menu & Akses
 * tampil sesuai urutan registry.
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v32');

const { pool } = require('../../src/config/database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS, ROLES } = require('../../src/config/permissions');

const KODE_BARU = 'kependudukan.kk';
const KODE_HAPUS = 'kegiatan.pengumuman';

async function jalankan() {
  console.log(`\n${'═'.repeat(56)}`);
  console.log('Migrasi v32 — Data KK jadi izin sendiri, Pengumuman dilebur');
  console.log('═'.repeat(56));

  // Penjagaan registry, sama seperti v31: kalau kode belum sesuai, auto-setup
  // akan mengembalikan keadaan lama pada penyalaan berikutnya.
  const kode = MENU_ITEMS.map((m) => m.kode);
  if (!kode.includes(KODE_BARU)) {
    throw new Error(`"${KODE_BARU}" belum ada di MENU_ITEMS — perbarui src/config/permissions.js dulu.`);
  }
  if (kode.includes(KODE_HAPUS)) {
    throw new Error(`"${KODE_HAPUS}" masih ada di MENU_ITEMS — hapus dari registry dulu, kalau tidak auto-setup menambahkannya kembali.`);
  }
  console.log(`\n  Registry sesuai: ${MENU_ITEMS.length} menu, memuat ${KODE_BARU}, tanpa ${KODE_HAPUS}.`);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // --- 1. Menu baru + metadata/urutan seluruh menu ------------------
    for (let i = 0; i < MENU_ITEMS.length; i++) {
      const m = MENU_ITEMS[i];
      await client.query(
        `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem, is_aktif)
         VALUES ($1, $2, $3, $4, $5, $6, true)
         ON CONFLICT (kode) DO UPDATE SET
           nama = EXCLUDED.nama, grup = EXCLUDED.grup,
           menu_index = EXCLUDED.menu_index, urutan = EXCLUDED.urutan,
           is_sistem = EXCLUDED.is_sistem`,
        [m.kode, m.nama, m.grup, m.menu_index, i, m.is_sistem === true]
      );
    }
    console.log(`  Metadata & urutan ${MENU_ITEMS.length} menu disegarkan.`);

    // --- 2. Izin bawaan untuk menu baru -------------------------------
    // DO NOTHING: bila barisnya sudah ada (migrasi diulang), setelan yang
    // mungkin sudah diubah administrator tidak ditimpa.
    let izinBaru = 0;
    for (const role of ROLES) {
      const izin = DEFAULT_PERMISSIONS[role][KODE_BARU];
      const r = await client.query(
        `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
         VALUES ($1,$2,$3,$4,$5,$6)
         ON CONFLICT (role, menu_kode) DO NOTHING`,
        [role, KODE_BARU, izin.view, izin.create, izin.update, izin.delete]
      );
      izinBaru += r.rowCount;
    }
    console.log(`  Izin ${KODE_BARU} ditambahkan  : ${izinBaru} baris`);

    // --- 3. Laporkan selisih sebelum menghapus ------------------------
    const beda = await client.query(
      `SELECT a.role
         FROM role_permissions a
         JOIN role_permissions b
           ON b.role = a.role AND b.menu_kode = 'kegiatan.agenda'
        WHERE a.menu_kode = $1
          AND (a.can_view <> b.can_view OR a.can_create <> b.can_create
            OR a.can_update <> b.can_update OR a.can_delete <> b.can_delete)`,
      [KODE_HAPUS]
    );
    if (beda.rows.length) {
      console.log(`  ⚠️  ${beda.rows.length} peran punya setelan pengumuman BERBEDA dari agenda`
        + ` (${beda.rows.map((r) => r.role).join(', ')}) — setelan itu ikut hilang.`);
    } else {
      console.log('  Setelan pengumuman identik dengan agenda di semua peran.');
    }

    // --- 4. Hapus menu lama, anak dulu -------------------------------
    const izinHapus = await client.query(
      'DELETE FROM role_permissions WHERE menu_kode = $1 RETURNING role',
      [KODE_HAPUS]
    );
    const menuHapus = await client.query(
      'DELETE FROM menu_items WHERE kode = $1 RETURNING nama',
      [KODE_HAPUS]
    );
    console.log(`  Izin ${KODE_HAPUS} dihapus : ${izinHapus.rowCount} baris`);
    console.log(`  menu_items dihapus            : ${menuHapus.rowCount}`);

    await client.query('COMMIT');

    // --- Pembuktian sesudah commit ------------------------------------
    const tm = await pool.query('SELECT COUNT(*)::int n FROM menu_items');
    const ti = await pool.query('SELECT COUNT(*)::int n FROM role_permissions');
    const adaHapus = await pool.query('SELECT COUNT(*)::int n FROM menu_items WHERE kode = $1', [KODE_HAPUS]);
    const adaBaru = await pool.query('SELECT COUNT(*)::int n FROM menu_items WHERE kode = $1', [KODE_BARU]);

    if (adaHapus.rows[0].n !== 0) throw new Error(`${KODE_HAPUS} masih tersisa.`);
    if (adaBaru.rows[0].n !== 1) throw new Error(`${KODE_BARU} tidak tersimpan.`);

    console.log(`\n  Total menu_items       : ${tm.rows[0].n} (registry: ${MENU_ITEMS.length})`);
    console.log(`  Total role_permissions : ${ti.rows[0].n} (harap: ${ROLES.length * MENU_ITEMS.length})`);

    console.log(`\n${'═'.repeat(56)}`);
    console.log((izinBaru + menuHapus.rowCount) === 0
      ? '✅ Sudah sesuai sebelumnya — tidak ada perubahan.'
      : '✅ Selesai.');
    console.log('═'.repeat(56));
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

jalankan()
  .catch((e) => {
    console.error('❌ Migrasi v32 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
