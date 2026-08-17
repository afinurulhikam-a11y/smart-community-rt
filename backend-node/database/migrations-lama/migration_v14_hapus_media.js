require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v14_hapus_media');

const { pool } = require('../../src/config/database');

/**
 * Migrasi v14 — menghapus modul Media (Berita & Video).
 *
 * Modul ini tidak diperlukan RT ini. Layar Berita dan Video memang sudah ada,
 * tetapi tombol "Buat Berita" dan "Tambah Video" tidak pernah punya form di
 * baliknya, dan tabel `media` kosong sejak dibuat — jadi tidak ada data warga
 * yang hilang bersamanya.
 *
 * Yang dibersihkan:
 *  - tabel `media`
 *  - baris menu `kegiatan.media` di `menu_items`; lima baris izinnya di
 *    `role_permissions` ikut terhapus lewat ON DELETE CASCADE
 *
 * Berkas yang dihapus bersama migrasi ini: media.controller.js,
 * media.routes.js, media_provider.dart, media_berita_screen.dart, dan
 * media_video_screen.dart.
 *
 * PERINGATAN: penjatuhan tabel tidak bisa dibatalkan. Ambil pg_dump lebih dulu.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Laporkan lebih dulu, supaya jumlahnya terlihat sebelum benar-benar
    // lenyap. Kalau ternyata ada isinya, itu tanda modul ini sempat dipakai
    // dan penghapusannya perlu ditinjau ulang.
    let barisMedia = null;
    const ada = await client.query("SELECT to_regclass('public.media') AS ada");
    if (ada.rows[0].ada) {
      const c = await client.query('SELECT COUNT(*)::int AS n FROM media');
      barisMedia = c.rows[0].n;
    }

    await client.query('DROP TABLE IF EXISTS media;');

    // role_permissions.menu_kode ber-ON DELETE CASCADE terhadap menu_items,
    // jadi menghapus satu baris menu sekaligus membersihkan izin kelima role.
    const izinSebelum = await client.query(
      "SELECT COUNT(*)::int AS n FROM role_permissions WHERE menu_kode = 'kegiatan.media'"
    );
    const menu = await client.query(
      "DELETE FROM menu_items WHERE kode = 'kegiatan.media' RETURNING kode"
    );

    await client.query('COMMIT');

    console.log('Migrasi v14 berhasil.');
    console.log(
      barisMedia === null
        ? '  Tabel media sudah tidak ada.'
        : `  Tabel media dijatuhkan (${barisMedia} baris).`
    );
    console.log(
      menu.rowCount > 0
        ? `  Menu kegiatan.media dihapus, beserta ${izinSebelum.rows[0].n} baris izin.`
        : '  Menu kegiatan.media sudah tidak terdaftar.'
    );
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v14 gagal:', err.message);
    console.error('Tidak ada perubahan yang diterapkan.');
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
