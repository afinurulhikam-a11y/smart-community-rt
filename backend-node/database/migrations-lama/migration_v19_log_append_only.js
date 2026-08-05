/**
 * Migrasi v19 — jejak audit menjadi HANYA-TAMBAH, dan bisa dicari.
 *
 * ===================================================================
 * Kenapa di lapisan database, bukan cukup di kode?
 * ===================================================================
 *
 * Sebelum ini, seorang administrator bisa menghapus seluruh jejaknya sendiri:
 *
 *     await pool.query('DELETE FROM activity_logs');           // log.controller.js
 *     await logActivity(req, 'DELETE', 'Membersihkan ...');    // menyisakan 1 baris
 *
 * Yang tersisa cuma satu baris, dan baris itu tidak menyebutkan apa pun tentang
 * yang dihapus. Kelompok "Log Aktivitas" di Reset Sistem serta Reset Total juga
 * mengosongkan tabel yang sama.
 *
 * Menghapus ketiga jalur itu dari kode sudah menutup pintunya — tetapi hanya
 * selama tidak ada yang menambahkan jalur baru. Trigger di bawah ini membuat
 * penolakannya berlaku untuk SETIAP perintah, termasuk yang belum ditulis
 * siapa pun hari ini, dan termasuk `psql` yang memakai kredensial aplikasi.
 *
 * Ini bukan perlindungan terhadap pemilik server: siapa pun dengan hak SUPERUSER
 * masih bisa membuang trigger-nya. Yang dijaga di sini adalah penyalahgunaan
 * lewat aplikasi — dan itu memang ancaman yang nyata di sistem RT.
 *
 * ===================================================================
 * Indeks
 * ===================================================================
 *
 * Tabelnya sama sekali tidak punya indeks. Setiap kueri memindai seluruh tabel
 * lalu mengurutkannya. Tidak terasa pada 67 baris; sangat terasa begitu jejaknya
 * tidak pernah dihapus lagi — yang justru menjadi tujuan migrasi ini.
 *
 * Idempoten: aman dijalankan berulang.
 */
require('dotenv').config();
const { pool } = require('./src/config/database');

async function jalankan() {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // ---------------------------------------------------------------
    // 1. Indeks
    // ---------------------------------------------------------------
    // created_at DESC: layar log SELALU mengurutkan terbaru dulu, dan
    // penyaring rentang tanggal bersandar pada indeks yang sama.
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at
        ON activity_logs (created_at DESC)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_activity_logs_tipe
        ON activity_logs (tipe)
    `);
    // Menjawab "apa saja yang pernah dilakukan akun ini" — pertanyaan pertama
    // saat sebuah akun dicurigai.
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_activity_logs_user
        ON activity_logs (user_id, created_at DESC)
    `);
    console.log('  ✅ Tiga indeks siap (created_at, tipe, user_id)');

    // ---------------------------------------------------------------
    // 2. Trigger hanya-tambah
    // ---------------------------------------------------------------
    await client.query(`
      CREATE OR REPLACE FUNCTION tolak_ubah_activity_logs()
      RETURNS TRIGGER AS $$
      BEGIN
        RAISE EXCEPTION
          'activity_logs bersifat hanya-tambah: % ditolak. Jejak audit tidak boleh diubah atau dihapus.',
          TG_OP
          USING ERRCODE = 'insufficient_privilege';
      END;
      $$ LANGUAGE plpgsql
    `);

    // DROP dulu supaya idempoten — CREATE TRIGGER tidak punya IF NOT EXISTS
    // di semua versi Postgres yang mungkin dipakai.
    await client.query('DROP TRIGGER IF EXISTS trg_activity_logs_append_only ON activity_logs');
    await client.query(`
      CREATE TRIGGER trg_activity_logs_append_only
        BEFORE UPDATE OR DELETE ON activity_logs
        FOR EACH ROW EXECUTE FUNCTION tolak_ubah_activity_logs()
    `);

    // TRUNCATE butuh trigger TERPISAH, dan ini bukan kerapian belaka.
    //
    // `FOR EACH ROW` tidak pernah menyala pada TRUNCATE — perintah itu membuang
    // seluruh isi tabel tanpa menyentuh baris satu per satu. Jadi trigger di
    // atas, sendirian, memberi rasa aman yang keliru: DELETE ditolak, tetapi
    // `TRUNCATE activity_logs` tetap melenyapkan semuanya tanpa perlawanan.
    //
    // Kesenjangan itu terbukti nyata di basis data pengembangan ini: jejaknya
    // menyusut dari 67 baris menjadi 10 SETELAH trigger baris terpasang.
    await client.query('DROP TRIGGER IF EXISTS trg_activity_logs_no_truncate ON activity_logs');
    await client.query(`
      CREATE TRIGGER trg_activity_logs_no_truncate
        BEFORE TRUNCATE ON activity_logs
        FOR EACH STATEMENT EXECUTE FUNCTION tolak_ubah_activity_logs()
    `);
    console.log('  ✅ Trigger hanya-tambah terpasang (UPDATE, DELETE & TRUNCATE ditolak)');

    await client.query('COMMIT');

    // ---------------------------------------------------------------
    // 3. Buktikan trigger-nya benar-benar bekerja
    // ---------------------------------------------------------------
    // Migrasi yang mengaku berhasil tanpa membuktikannya tidak ada gunanya di
    // sini: seluruh nilai perubahan ini terletak pada penolakan itu terjadi.
    let terbukti = false;
    try {
      await client.query('DELETE FROM activity_logs WHERE 1=0');
    } catch (e) {
      terbukti = /hanya-tambah/.test(e.message);
    }

    if (terbukti) {
      console.log('  ✅ Terbukti: DELETE pada activity_logs ditolak database');
    } else {
      // DELETE ... WHERE 1=0 tidak menyentuh baris mana pun, sehingga trigger
      // FOR EACH ROW memang tidak terpicu. Diuji ulang dengan baris sungguhan.
      const uji = await client.query(
        `INSERT INTO activity_logs (user_nama, user_role, tipe, aktivitas)
         VALUES ('Migrasi v19', 'Sistem', 'UPDATE', 'Uji trigger hanya-tambah') RETURNING id`
      );
      const id = uji.rows[0].id;
      try {
        await client.query('DELETE FROM activity_logs WHERE id = $1', [id]);
        console.log('  ❌ GAGAL: baris uji berhasil dihapus — trigger TIDAK bekerja');
        process.exitCode = 1;
      } catch (e) {
        if (/hanya-tambah/.test(e.message)) {
          console.log('  ✅ Terbukti: DELETE baris nyata ditolak database');
        } else {
          console.log('  ⚠️ Ditolak, tapi bukan oleh trigger kita:', e.message);
          process.exitCode = 1;
        }
      }
    }

    // ---------------------------------------------------------------
    // 4. Buktikan TRUNCATE juga ditolak
    // ---------------------------------------------------------------
    // Diuji di dalam transaksi lalu dibatalkan: TRUNCATE bersifat transaksional
    // di PostgreSQL, jadi seandainya trigger-nya TIDAK bekerja pun, ROLLBACK
    // mengembalikan seluruh isinya. Ujinya aman terhadap data sungguhan.
    try {
      await client.query('BEGIN');
      await client.query('TRUNCATE activity_logs');
      await client.query('ROLLBACK');
      console.log('  ❌ GAGAL: TRUNCATE TIDAK ditolak — jejak masih bisa dilenyapkan sekaligus');
      process.exitCode = 1;
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      if (/hanya-tambah/.test(e.message)) {
        console.log('  ✅ Terbukti: TRUNCATE pada activity_logs ditolak database');
      } else {
        console.log('  ⚠️ TRUNCATE ditolak, tapi bukan oleh trigger kita:', e.message);
        process.exitCode = 1;
      }
    }

    console.log('\nMigrasi v19 selesai.');
    console.log('Catatan: baris uji dari migrasi ini memang tidak bisa dihapus lagi.');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migrasi v19 gagal:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

jalankan();
