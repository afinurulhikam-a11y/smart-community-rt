require('dotenv').config();
const { pool } = require('../../src/config/database');

/**
 * Migrasi v13 — koreksi hak akses warga.
 *
 * Migrasi v11 menyisipkan matriks izin dengan ON CONFLICT DO NOTHING, sehingga
 * mengubah nilai bawaan di permissions.js saja tidak cukup: barisnya sudah
 * terlanjur ada dengan nilai lama. Dua baris di bawah perlu di-UPDATE.
 *
 * Satu baris yang perlu dikoreksi:
 *
 *  - inventaris.peminjaman: warga sebelumnya nol akses, sehingga tidak punya
 *    jalan mengajukan peminjaman barang RT. `inventaris.barang` sengaja tetap
 *    nol — warga meminjam, bukan mengelola daftar inventaris.
 *
 * `aspirasi.polling` SENGAJA tidak diubah dan tetap `view` saja. Sempat
 * terpikir menaikkannya ke `create` agar warga bisa memilih, tetapi pada modul
 * ini `create` dipakai rute POST /polling untuk MEMBUAT polling — menaikkannya
 * akan sekalian memberi warga hak membuat polling sendiri. Ikut memilih
 * karena itu dijaga `view` di polling.routes.js.
 *
 * Admin tetap bisa mengubahnya lewat layar Menu & Akses setelah ini.
 */

const KOREKSI = [
  {
    role: 'warga',
    menu: 'inventaris.peminjaman',
    izin: { can_view: true, can_create: true, can_update: false, can_delete: false },
    alasan: 'warga boleh mengajukan peminjaman barang',
  },
];

async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const perubahan = [];
    for (const k of KOREKSI) {
      const { can_view, can_create, can_update, can_delete } = k.izin;

      // Idempoten: baris yang sudah bernilai sama tidak dihitung sebagai
      // perubahan, jadi menjalankan ulang migrasi ini aman dan sunyi.
      const r = await client.query(
        `UPDATE role_permissions
            SET can_view = $3, can_create = $4, can_update = $5, can_delete = $6,
                updated_at = CURRENT_TIMESTAMP
          WHERE role = $1 AND menu_kode = $2
            AND (can_view, can_create, can_update, can_delete) IS DISTINCT FROM ($3, $4, $5, $6)
          RETURNING id`,
        [k.role, k.menu, can_view, can_create, can_update, can_delete]
      );

      if (r.rowCount > 0) {
        perubahan.push(`${k.role}/${k.menu} — ${k.alasan}`);
        continue;
      }

      // Baris belum ada sama sekali (misalnya menu ditambahkan belakangan).
      const ada = await client.query(
        'SELECT 1 FROM role_permissions WHERE role = $1 AND menu_kode = $2',
        [k.role, k.menu]
      );
      if (ada.rowCount === 0) {
        await client.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [k.role, k.menu, can_view, can_create, can_update, can_delete]
        );
        perubahan.push(`${k.role}/${k.menu} — disisipkan (${k.alasan})`);
      }
    }

    await client.query('COMMIT');

    if (perubahan.length === 0) {
      console.log('Migrasi v13: izin sudah sesuai, tidak ada perubahan.');
    } else {
      console.log(`Migrasi v13 berhasil, ${perubahan.length} izin diperbarui:`);
      for (const p of perubahan) console.log(`  - ${p}`);
    }
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v13 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
