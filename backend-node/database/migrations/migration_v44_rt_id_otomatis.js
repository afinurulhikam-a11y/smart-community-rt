/**
 * Migrasi v44 — mengisi `rt_id` secara otomatis pada setiap baris baru.
 *
 * ===================================================================
 * Cacat yang ditutup migrasi ini
 * ===================================================================
 *
 * v43 melingkupi seluruh PEMBACAAN per RT, dan uji isolasi membuktikannya.
 * Tetapi separuh lainnya tertinggal: ada 28 perintah INSERT yang tidak pernah
 * mengisi `rt_id`, sehingga setiap baris yang lahir sesudah v43 ber-`rt_id`
 * NULL — dan NULL tidak pernah cocok dengan `rt_id = $n`.
 *
 * Akibatnya bukan galat, melainkan yang lebih buruk: **pengaduan yang baru
 * dikirim warga langsung hilang dari daftar pengurus.** Tersimpan rapi di
 * basis data, tidak terlihat oleh siapa pun. Ditemukan oleh
 * test-emergency-keterangan, bukan dengan membaca kode.
 *
 * ===================================================================
 * Kenapa pemicu basis data, bukan 28 suntingan di pengendali
 * ===================================================================
 *
 * Menambahkan `rt_id` ke 28 INSERT berarti 28 kesempatan untuk lupa, dan
 * kelalaiannya tidak berbunyi — persis kelas cacat yang baru saja terjadi.
 * Lebih buruk lagi, setiap INSERT yang ditulis SETELAH hari ini akan mengulang
 * kesalahan yang sama, dan tidak ada yang menghentikannya.
 *
 * Pemicu ini tidak bisa dilupakan. Ia mengisi `rt_id` dari RT pemilik barisnya
 * ketika kolomnya dibiarkan kosong, dan **tidak menyentuh apa pun bila nilainya
 * sudah disebut** — jadi administrator yang sengaja membuat data atas nama RT
 * tertentu tetap menang atas pemicu ini.
 *
 * ===================================================================
 * Kenapa nama kolom pemiliknya dikirim sebagai argumen
 * ===================================================================
 *
 * Sebagian tabel menyimpan pemiliknya di `user_id`, sebagian lagi hanya punya
 * `created_by`. Satu fungsi yang menebak sendiri akan salah pada separuhnya,
 * jadi nama kolomnya disebut per tabel lewat `TG_ARGV[0]` dan dibaca dengan
 * `to_jsonb(NEW)`. Yang tidak punya keduanya jatuh ke RT bawaan.
 *
 * Idempoten. Jalankan terhadap SETIAP database, termasuk Railway.
 *
 *   node database/migrations/migration_v44_rt_id_otomatis.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v44_rt_id_otomatis');

const { pool } = require('../../src/config/database');

/**
 * Tabel dan kolom yang menunjuk pemilik barisnya.
 *
 * `user_id` lebih diutamakan daripada `created_by` di mana pun keduanya ada:
 * yang menentukan RT adalah PEMILIK datanya, bukan petugas yang mengetikkan.
 * Seorang sekretaris bisa mencatatkan sesuatu atas nama warga RT lain.
 *
 * `null` berarti tabelnya tidak punya penunjuk pemilik sama sekali, sehingga
 * jatuh ke RT bawaan — pengendalinya tetap boleh menyebut `rt_id` sendiri, dan
 * bila disebut, nilai itulah yang dipakai.
 */
const TABEL = [
  ['emergency_alerts', 'user_id'],
  ['complaints', 'user_id'],
  ['letters', 'user_id'],
  ['borrowings', 'user_id'],
  ['bantuan_sosial', 'user_id'],
  ['finances', 'created_by'],
  ['bop_finances', 'created_by'],
  ['alokasi_bop', 'created_by'],
  ['inventory', 'created_by'],
  ['agenda', 'created_by'],
  ['announcements', 'created_by'],
  ['polling', 'created_by'],
  ['visitors', 'created_by'],
  ['jenis_iuran', null],
  ['kategori_kas', null],
  ['kategori_bop', null],
  ['keluarga', null],
  ['users', null],
];

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v44: pengisian rt_id otomatis pada baris baru...');
    await client.query('BEGIN');

    await client.query(`
      CREATE OR REPLACE FUNCTION isi_rt_id() RETURNS trigger AS $isi$
      DECLARE
        uid uuid;
        rid uuid;
      BEGIN
        -- Nilai yang sudah disebut selalu menang. Inilah yang membuat
        -- administrator tetap bisa membuat data atas nama RT tertentu.
        IF NEW.rt_id IS NOT NULL THEN
          RETURN NEW;
        END IF;

        IF TG_NARGS > 0 AND TG_ARGV[0] IS NOT NULL AND TG_ARGV[0] <> '' THEN
          BEGIN
            uid := NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid;
          EXCEPTION WHEN others THEN
            uid := NULL;
          END;
        END IF;

        IF uid IS NOT NULL THEN
          SELECT u.rt_id INTO rid FROM users u WHERE u.id = uid;
        END IF;

        IF rid IS NULL THEN
          SELECT r.id INTO rid FROM rt r
            WHERE r.deleted_at IS NULL ORDER BY r.kode LIMIT 1;
        END IF;

        NEW.rt_id := rid;
        RETURN NEW;
      END
      $isi$ LANGUAGE plpgsql;
    `);

    for (const [tabel, kolom] of TABEL) {
      const nama = `trg_${tabel}_isi_rt_id`;
      await client.query(`DROP TRIGGER IF EXISTS ${nama} ON ${tabel};`);
      const arg = kolom ? `('${kolom}')` : `('')`;
      await client.query(`
        CREATE TRIGGER ${nama}
          BEFORE INSERT ON ${tabel}
          FOR EACH ROW EXECUTE FUNCTION isi_rt_id${arg};
      `);
    }

    // Baris yang terlanjur lahir tanpa RT sejak v43 dan sebelum v44.
    let dirapikan = 0;
    for (const [tabel, kolom] of TABEL) {
      if (kolom) {
        const r = await client.query(`
          UPDATE ${tabel} t SET rt_id = u.rt_id
            FROM users u
           WHERE u.id = t.${kolom} AND t.rt_id IS NULL AND u.rt_id IS NOT NULL;
        `);
        dirapikan += r.rowCount;
      }
      const r2 = await client.query(`
        UPDATE ${tabel} SET rt_id = (
          SELECT id FROM rt WHERE deleted_at IS NULL ORDER BY kode LIMIT 1
        ) WHERE rt_id IS NULL;
      `);
      dirapikan += r2.rowCount;
    }

    await client.query('COMMIT');
    console.log(`✅ Migrasi v44 selesai: pemicu terpasang pada ${TABEL.length} tabel`
      + `${dirapikan ? `, ${dirapikan} baris tanpa RT dirapikan` : ''}.`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v44:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
