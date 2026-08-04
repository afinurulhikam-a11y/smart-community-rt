require('dotenv').config();
const { pool } = require('./src/config/database');
const { GRUP_TOTAL, TABEL_DILINDUNGI } = require('./src/config/reset-groups');

/**
 * Mengosongkan seluruh data operasional, menyisakan akun pengurus dan master.
 *
 * Urutannya TIDAK ditulis di sini melainkan dibaca dari `GRUP_TOTAL` di
 * src/config/reset-groups.js — registry yang sama yang dipakai layar Reset
 * Sistem. Registry itu sudah teruji dan sudah menangani jebakan
 * `keluarga --CASCADE--> bills --RESTRICT--> bill_payments`, jadi menyalin
 * ulang urutannya di sini justru akan menciptakan sumber kebenaran kedua yang
 * bisa berbeda diam-diam.
 *
 * Yang TETAP ADA: akun admin/ketua_rt/sekretaris/bendahara, jenis_iuran,
 * kategori_kas, kategori_bop, menu_items, role_permissions, dan reset_logs.
 *
 * PERINGATAN: tidak bisa dibatalkan. Ambil pg_dump lebih dulu.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const rincian = {};
    let total = 0;
    for (const entri of GRUP_TOTAL.tabel) {
      const where = entri.where ? ` WHERE ${entri.where}` : '';
      const r = await client.query(`DELETE FROM ${entri.tabel}${where}`);
      if (r.rowCount > 0) {
        rincian[entri.tabel] = (rincian[entri.tabel] || 0) + r.rowCount;
        total += r.rowCount;
      }
    }

    await client.query('COMMIT');

    console.log(`Data dikosongkan — ${total} baris dihapus.`);
    for (const [t, n] of Object.entries(rincian)) {
      console.log(`  ${t.padEnd(22)} ${n}`);
    }

    // Tampilkan apa yang tersisa, supaya terbukti perlindungannya bekerja.
    console.log('\nYang tetap ada:');
    const akun = await pool.query(
      "SELECT role, COUNT(*)::int n FROM users GROUP BY role ORDER BY role"
    );
    for (const r of akun.rows) console.log(`  akun ${r.role.padEnd(17)} ${r.n}`);
    for (const t of TABEL_DILINDUNGI) {
      if (t === 'users') continue;
      const ada = await pool.query('SELECT to_regclass($1) AS ada', [`public.${t}`]);
      if (!ada.rows[0].ada) continue;
      const c = await pool.query(`SELECT COUNT(*)::int n FROM ${t}`);
      console.log(`  ${t.padEnd(22)} ${c.rows[0].n}`);
    }

    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Gagal mengosongkan data:', err.message);
    console.error('Tidak ada satu baris pun yang terhapus.');
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
