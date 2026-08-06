/**
 * Migrasi v20 — melepas FK `activity_logs.user_id → users.id`.
 *
 * ===================================================================
 * Kenapa
 * ===================================================================
 *
 * Migrasi v19 membuat `activity_logs` hanya-tambah: trigger menolak UPDATE,
 * DELETE, dan TRUNCATE. Kolom `user_id` sementara itu memegang foreign key
 * dengan `ON DELETE SET NULL`.
 *
 * Kedua rancangan itu saling meniadakan, dan baru terlihat saat seseorang
 * benar-benar menghapus akun:
 *
 *     DELETE FROM users WHERE id = '...';
 *     -- Postgres menjalankan aksi FK: UPDATE activity_logs SET user_id = NULL
 *     -- ERROR: activity_logs bersifat hanya-tambah: UPDATE ditolak.
 *
 * `SET NULL` DIWUJUDKAN SEBAGAI UPDATE. Selama FK itu ada, tidak ada satu pun
 * akun yang pernah muncul di jejak audit yang bisa dihapus — selamanya. Itu
 * bukan kebijakan yang pernah diputuskan siapa pun; itu efek samping.
 *
 * ===================================================================
 * Kenapa FK-nya yang dilepas, bukan trigger-nya yang dilonggarkan
 * ===================================================================
 *
 * Melonggarkan trigger agar mengizinkan UPDATE pada `user_id` akan membuka
 * lubang: siapa pun dengan akses SQL bisa memutus hubungan sebuah tindakan
 * dari pelakunya, satu per satu, tanpa menghapus apa pun. Justru itu bentuk
 * penyalahgunaan yang paling sulit terdeteksi.
 *
 * FK-nya sendiri tidak memberi apa-apa di sini:
 *
 * 1. `activity_logs` sudah menyimpan salinannya sendiri di `user_nama` dan
 *    `user_role`, ditulis saat barisnya dibuat. Nama pelaku tetap terbaca
 *    meski akunnya sudah lama tiada — memang itu gunanya kolom tersebut.
 * 2. `getActivityLogs` tidak pernah JOIN ke `users`. Ia hanya membaca kolom
 *    `activity_logs` sendiri, jadi layar Log Aktivitas tidak berubah sama
 *    sekali setelah migrasi ini.
 *
 * Konsekuensi yang diterima: `user_id` pada baris lama bisa menunjuk akun
 * yang sudah dihapus. Penyaring "berdasarkan pengguna" tetap bekerja untuk
 * akun yang masih ada, dan untuk yang sudah tiada nama pelakunya tetap
 * tercatat. Jejaknya tidak kehilangan apa pun.
 *
 * Trigger v19 TIDAK disentuh: UPDATE, DELETE, dan TRUNCATE tetap ditolak.
 *
 * Idempoten: aman dijalankan berulang.
 */
require('dotenv').config();
const { pool } = require('../../src/config/database');

async function jalankan() {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const sebelum = await client.query(`
      SELECT conname FROM pg_constraint
      WHERE conrelid = 'activity_logs'::regclass
        AND contype = 'f'
        AND conname = 'activity_logs_user_id_fkey'
    `);

    if (sebelum.rows.length === 0) {
      console.log('  ℹ️  FK activity_logs_user_id_fkey sudah tidak ada — tidak ada yang dikerjakan.');
    } else {
      await client.query('ALTER TABLE activity_logs DROP CONSTRAINT activity_logs_user_id_fkey');
      console.log('  ✅ FK activity_logs_user_id_fkey dilepas');
    }

    // Trigger v19 harus tetap terpasang. Kalau migrasi ini sampai ikut
    // membuangnya, seluruh perlindungan jejak audit hilang tanpa suara.
    const trigger = await client.query(`
      SELECT tgname FROM pg_trigger
      WHERE tgrelid = 'activity_logs'::regclass
        AND NOT tgisinternal
      ORDER BY tgname
    `);
    const nama = trigger.rows.map((r) => r.tgname);
    const wajib = ['trg_activity_logs_append_only', 'trg_activity_logs_no_truncate'];
    const hilang = wajib.filter((w) => !nama.includes(w));

    if (hilang.length > 0) {
      throw new Error(
        `Trigger hanya-tambah tidak lengkap: ${hilang.join(', ')} tidak terpasang. ` +
        'Jalankan migration_v19_log_append_only.js lebih dulu.'
      );
    }
    console.log(`  ✅ Trigger v19 masih utuh (${nama.join(', ')})`);

    // Bukti, bukan asumsi: UPDATE harus tetap ditolak setelah FK dilepas.
    await client.query('SAVEPOINT uji');
    try {
      await client.query('UPDATE activity_logs SET user_id = NULL WHERE id IS NOT NULL');
      throw new Error('GAGAL: UPDATE pada activity_logs berhasil — trigger v19 tidak bekerja.');
    } catch (err) {
      if (err.message.startsWith('GAGAL:')) throw err;
      await client.query('ROLLBACK TO SAVEPOINT uji');
      console.log('  ✅ Terbukti: UPDATE pada activity_logs masih ditolak database');
    }

    await client.query('COMMIT');
    console.log('\nMigrasi v20 selesai.');
    console.log('Akun pengguna kini bisa dihapus tanpa merusak jejak audit —');
    console.log('nama dan peran pelakunya tetap tersimpan di baris lognya sendiri.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v20 dibatalkan:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

jalankan();
