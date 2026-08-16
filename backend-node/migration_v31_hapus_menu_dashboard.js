/**
 * Menghapus menu `dashboard` beserta izinnya.
 *
 * ===================================================================
 * Kenapa dihapus
 * ===================================================================
 *
 * `dashboard` terdaftar sebagai menu yang izinnya bisa diatur, sehingga layar
 * Menu & Akses menampilkan satu baris penuh untuknya: 4 aksi x 5 peran = 20
 * saklar. Audit membuktikan **tidak satu pun dari 20 saklar itu berpengaruh**:
 *
 *   - Nol rute backend memakai `requirePermission('dashboard', ...)`.
 *   - Nol kode Flutter membaca izin `'dashboard'`.
 *   - `sidebar_menu.dart` menampilkan Dashboard TANPA syarat izin apa pun.
 *
 * Saklar yang tidak mengubah apa pun lebih berbahaya daripada tidak ada
 * saklar: administrator yang mematikan "Lihat Dashboard" untuk warga akan
 * yakin sudah menutup sesuatu, padahal warga tetap melihatnya. Kepercayaan
 * yang keliru pada layar kendali akses adalah kegagalan yang tidak
 * memunculkan galat.
 *
 * Dashboard sendiri TIDAK hilang — ia tetap beranda setiap peran. Yang hilang
 * hanyalah kepura-puraan bahwa ia bisa diatur.
 *
 * ===================================================================
 * Urutan hapus: anak dulu, baru induk
 * ===================================================================
 *
 * `role_permissions.menu_kode` punya FK ke `menu_items.kode` dengan aturan
 * CASCADE, jadi menghapus induknya saja sebetulnya cukup. Ia tetap dihapus
 * eksplisit lebih dulu karena dua alasan:
 *
 *   1. Jumlah baris yang benar-benar terhapus bisa dilaporkan apa adanya.
 *      Mengandalkan cascade berarti melaporkan "1 baris" untuk sesuatu yang
 *      sebenarnya menghapus enam.
 *   2. Aturan FK bisa berubah di kemudian hari. Migrasi yang benar hanya
 *      selama CASCADE masih terpasang adalah migrasi yang menunggu untuk
 *      gagal diam-diam.
 *
 * ===================================================================
 * Idempoten
 * ===================================================================
 *
 * Aman dijalankan berulang: jalan kedua menghapus nol baris dan melaporkannya
 * sebagai "sudah bersih". Ia juga tidak akan dihidupkan kembali oleh
 * `auto-setup.js` maupun `POST /menu-akses/reset`, karena keduanya membaca
 * `src/config/permissions.js` — dan `dashboard` sudah tidak ada di sana.
 */
require('dotenv').config();

const { pool } = require('./src/config/database');
const { MENU_ITEMS } = require('./src/config/permissions');

const KODE = 'dashboard';

async function jalankan() {
  console.log(`\n${'═'.repeat(52)}`);
  console.log(`Migrasi v31 — menghapus menu "${KODE}"`);
  console.log('═'.repeat(52));

  // Penjagaan: registry HARUS sudah bersih lebih dulu. Kalau tidak,
  // `auto-setup` akan menyisipkannya kembali pada penyalaan berikutnya dan
  // migrasi ini hanya menunda masalahnya beberapa menit.
  if (MENU_ITEMS.some((m) => m.kode === KODE)) {
    throw new Error(
      `"${KODE}" masih terdaftar di src/config/permissions.js. `
      + 'Hapus dari MENU_ITEMS dan DEFAULT_PERMISSIONS lebih dulu, '
      + 'kalau tidak auto-setup akan menambahkannya kembali saat server menyala.'
    );
  }
  console.log('\n  Registry sudah bersih — auto-setup tidak akan menambahkannya kembali.');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Anak lebih dulu.
    const izin = await client.query(
      'DELETE FROM role_permissions WHERE menu_kode = $1 RETURNING role',
      [KODE]
    );
    console.log(`  role_permissions dihapus : ${izin.rowCount}`
      + (izin.rowCount ? ` (${izin.rows.map((r) => r.role).join(', ')})` : ''));

    // 2. Baru induknya.
    const menu = await client.query(
      'DELETE FROM menu_items WHERE kode = $1 RETURNING nama',
      [KODE]
    );
    console.log(`  menu_items dihapus       : ${menu.rowCount}`
      + (menu.rowCount ? ` ("${menu.rows[0].nama}")` : ''));

    await client.query('COMMIT');

    // Pembuktian sesudah commit, bukan asumsi.
    const sisaMenu = await pool.query('SELECT COUNT(*)::int AS n FROM menu_items WHERE kode = $1', [KODE]);
    const sisaIzin = await pool.query('SELECT COUNT(*)::int AS n FROM role_permissions WHERE menu_kode = $1', [KODE]);
    if (sisaMenu.rows[0].n !== 0 || sisaIzin.rows[0].n !== 0) {
      throw new Error('Masih ada sisa baris setelah penghapusan.');
    }

    const total = await pool.query('SELECT COUNT(*)::int AS n FROM menu_items');
    const totalIzin = await pool.query('SELECT COUNT(*)::int AS n FROM role_permissions');
    console.log(`\n  Sisa menu_items          : ${total.rows[0].n} (registry: ${MENU_ITEMS.length})`);
    console.log(`  Sisa role_permissions    : ${totalIzin.rows[0].n}`);

    console.log(`\n${'═'.repeat(52)}`);
    console.log((izin.rowCount + menu.rowCount) === 0
      ? `✅ Sudah bersih sebelumnya — tidak ada yang dihapus.`
      : `✅ Selesai — ${menu.rowCount} menu dan ${izin.rowCount} baris izin dihapus.`);
    console.log('═'.repeat(52));
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

jalankan()
  .catch((e) => {
    console.error('❌ Migrasi v31 gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
