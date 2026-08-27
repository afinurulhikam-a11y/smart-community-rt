/**
 * Migrasi v47 — persetujuan surat bertingkat RT lalu RW.
 *
 * ===================================================================
 * Kenapa satu tahap tidak cukup
 * ===================================================================
 *
 * Surat pengantar di Indonesia mengalir RT → RW → Kelurahan. `letters` hanya
 * memodelkan satu tahap: satu `status`, satu `approved_by`. Selama sebuah
 * pemasangan hanya melayani satu RT itu memang cukup — begitu RW ikut ada,
 * separuh alurnya hilang, dan Ketua RW tidak punya apa pun untuk dikerjakan
 * pada modul yang justru paling membutuhkannya.
 *
 * ===================================================================
 * Kolom baru, bukan menumpang `approved_by`
 * ===================================================================
 *
 * `approved_by` mencatat pengurus RT yang meneruskan. Memakainya ulang untuk
 * Ketua RW akan MENGHAPUS jejak siapa yang menyetujui lebih dulu — dan pada
 * dokumen yang dipakai mengurus keperluan resmi, "siapa yang meloloskan"
 * adalah justru pertanyaan yang paling mungkin ditanyakan belakangan.
 *
 * ===================================================================
 * Surat yang sudah ada TIDAK disentuh
 * ===================================================================
 *
 * Baris berstatus `approved`/`rejected` tetap apa adanya: keputusannya sudah
 * diambil, dan memundurkannya ke `menunggu_rw` berarti membatalkan surat yang
 * mungkin sudah dicetak dan dibawa orang.
 *
 * Idempoten. Jalankan terhadap SETIAP database, termasuk Railway.
 *
 *   node database/migrations/migration_v47_surat_rt_rw.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v47_surat_rt_rw');

const { pool } = require('../../src/config/database');

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v47: persetujuan surat bertingkat RT → RW...');
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE letters
        ADD COLUMN IF NOT EXISTS disetujui_rw_oleh UUID,
        ADD COLUMN IF NOT EXISTS disetujui_rw_pada TIMESTAMP,
        ADD COLUMN IF NOT EXISTS catatan_rw TEXT;
    `);

    // FK dipasang terpisah supaya ALTER di atas tetap berhasil pada basis data
    // yang urutan pembuatan tabelnya berbeda. ON DELETE SET NULL: menghapus
    // akun tidak boleh menggagalkan penghapusan hanya karena ia pernah
    // menyetujui sebuah surat — jejak namanya sudah ada di activity_logs.
    await client.query(`
      DO $tambah$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'letters_disetujui_rw_oleh_fkey'
        ) THEN
          ALTER TABLE letters ADD CONSTRAINT letters_disetujui_rw_oleh_fkey
            FOREIGN KEY (disetujui_rw_oleh) REFERENCES users(id) ON DELETE SET NULL;
        END IF;
      END
      $tambah$;
    `);

    // Dipakai daftar "menunggu persetujuan saya" milik Ketua RW.
    await client.query(
      `CREATE INDEX IF NOT EXISTS letters_status_idx ON letters (status);`
    );

    await client.query('COMMIT');

    const n = await pool.query(
      `SELECT status, COUNT(*)::int c FROM letters WHERE deleted_at IS NULL GROUP BY 1 ORDER BY 1`
    );
    console.log('✅ Migrasi v47 selesai. Status surat saat ini:',
      n.rows.map((r) => `${r.status}=${r.c}`).join(', ') || '(belum ada surat)');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v47:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
