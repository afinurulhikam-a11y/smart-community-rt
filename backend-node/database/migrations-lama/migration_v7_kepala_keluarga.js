require('dotenv').config();
const { pool } = require('../../src/config/database');

/**
 * Migrasi v7 — Merapikan nama kepala keluarga yang masih berupa tanda hubung.
 *
 * Sebelum perbaikan di warga.controller.js, KK yang anggota pertamanya bukan
 * berstatus "Kepala Keluarga" disimpan dengan kepala_keluarga = '-'. Baris
 * seperti itu tampil sebagai "(Belum diisi)" di layar Iuran Warga.
 *
 * Nilai '-' diganti nama anggota pertama sebagai penanda sementara, sama dengan
 * perilaku baru. Pembaca membedakannya lewat kolom turunan kepala_terkonfirmasi,
 * bukan dari isi namanya, dan nilai ini otomatis tertimpa begitu anggota
 * berstatus Kepala Keluarga ditambahkan.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const hasil = await client.query(`
      UPDATE keluarga k
      SET kepala_keluarga = sub.nama
      FROM (
        SELECT DISTINCT ON (keluarga_id) keluarga_id, nama
        FROM anggota_keluarga
        ORDER BY keluarga_id, id
      ) sub
      WHERE k.id = sub.keluarga_id
        AND (k.kepala_keluarga IS NULL OR TRIM(k.kepala_keluarga) IN ('', '-'))
      RETURNING k.no_kk, k.kepala_keluarga
    `);

    // KK tanpa anggota sama sekali tidak punya nama untuk dipakai; dibiarkan
    // agar tetap terlihat sebagai data yang perlu dilengkapi.
    const yatim = await client.query(`
      SELECT COUNT(*)::int AS c FROM keluarga k
      WHERE (k.kepala_keluarga IS NULL OR TRIM(k.kepala_keluarga) IN ('', '-'))
        AND NOT EXISTS (SELECT 1 FROM anggota_keluarga ak WHERE ak.keluarga_id = k.id)
    `);

    await client.query('COMMIT');

    console.log(`Migrasi v7 berhasil: ${hasil.rowCount} KK dirapikan.`);
    hasil.rows.forEach((r) => console.log(`  KK ${r.no_kk} -> "${r.kepala_keluarga}" (sementara)`));
    if (yatim.rows[0].c > 0) {
      console.log(`  Catatan: ${yatim.rows[0].c} KK tanpa anggota dibiarkan apa adanya.`);
    }
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v7 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
