/**
 * Migrasi v43 — satu RW berisi beberapa RT.
 *
 * ===================================================================
 * Kenapa kolom `rt` yang sudah ada tidak cukup
 * ===================================================================
 *
 * `keluarga` sudah punya `rt` dan `rw`, dan `users` punya `no_rt`. Ketiganya
 * `varchar(3)` dan sudah terisi. Tetapi selama ini ketiganya hanya LABEL: ikut
 * tercetak di ekspor, dan tidak pernah menyaring satu kueri pun.
 *
 * Memakai varchar itu langsung sebagai kunci pelingkupan menggoda karena tidak
 * perlu migrasi sama sekali. Ditolak karena tiga hal:
 *
 *   1. Tidak ada yang mencegah salah ketik. '01', '1', dan '001' akan menjadi
 *      tiga RT berbeda tanpa satu pun pesan galat.
 *   2. RT tidak punya tempat menyimpan namanya, ketuanya, atau alamat
 *      sekretariatnya — ketiganya diperlukan begitu RT-nya lebih dari satu.
 *   3. Mengganti nomor RT berarti memperbarui setiap baris di setiap tabel.
 *
 * Jadi `rt` menjadi tabel, dan kolom varchar lama DIPERTAHANKAN karena masih
 * dicetak di ekspor — tetapi berhenti menjadi sumber kebenaran.
 *
 * ===================================================================
 * Kenapa `rt_id` disalin ke tabel milik warga
 * ===================================================================
 *
 * `letters`, `complaints`, `emergency_alerts`, `borrowings`, dan
 * `bantuan_sosial` semuanya punya `user_id`, jadi RT-nya bisa dicari lewat
 * pemiliknya. Tetap disalin ke barisnya sendiri karena satu alasan yang tidak
 * bisa diperbaiki belakangan: **ketika seorang warga pindah RT, riwayatnya
 * harus tetap tercatat di RT tempat kejadiannya berlangsung.** Kalau RT dibaca
 * lewat join ke `users`, seluruh riwayat lama ikut berpindah — pengaduan tahun
 * lalu tiba-tiba menjadi milik RT baru, dan kas RT lama kehilangan jejaknya.
 *
 * Menyalin juga menghapus satu join dari setiap kueri daftar, dan kueri daftar
 * adalah yang paling sering dipanggil.
 *
 * ===================================================================
 * Tabel yang sengaja TIDAK dilingkupi
 * ===================================================================
 *
 * `menu_items` dan `role_permissions` — registri izin berlaku untuk seluruh
 * RW. Melingkupinya berarti tiap RT bisa punya definisi peran sendiri, dan itu
 * bukan yang diminta penguji.
 *
 * `activity_logs` — hanya-tambah dan dilindungi trigger. Menambah kolom masih
 * boleh, tetapi MENGISINYA untuk baris lama tidak: UPDATE ditolak trigger itu.
 * Jadi jejak audit tetap satu untuk seluruh RW, dan penyaringan per RT di layar
 * Log Aktivitas dilakukan lewat pelakunya.
 *
 * `reset_logs`, `tiket_unduh`, `sensor_logs`, `user_fcm_tokens` — milik sistem.
 *
 * Tabel anak dilingkupi lewat induknya: `anggota_keluarga` dan `bills` lewat
 * `keluarga`, `bill_payments` lewat `bills`, dan seterusnya.
 *
 * Idempoten: memeriksa dulu, aman dijalankan berulang. Jalankan terhadap
 * SETIAP database — termasuk Railway, yang tidak menjalankannya sendiri.
 *
 *   node database/migrations/migration_v43_multi_rt.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v43_multi_rt');

const { pool } = require('../../src/config/database');

/**
 * Tabel yang mendapat `rt_id` sendiri, beserta kolom yang dipakai menebak
 * RT-nya saat pengisian ulang.
 *
 * `user_id` dipakai bila ada, karena itu PEMILIK barisnya. `created_by` hanya
 * dipakai bila tidak ada pemilik — kolom itu mencatat siapa yang mengetik, dan
 * seorang sekretaris bisa saja mencatatkan sesuatu atas nama RT lain.
 */
const TABEL_BER_RT = [
  ['finances', 'created_by'],
  ['bop_finances', 'created_by'],
  ['alokasi_bop', 'created_by'],
  ['inventory', 'created_by'],
  ['agenda', 'created_by'],
  ['announcements', 'created_by'],
  ['polling', 'created_by'],
  ['visitors', 'created_by'],
  ['bantuan_sosial', 'user_id'],
  ['letters', 'user_id'],
  ['complaints', 'user_id'],
  ['emergency_alerts', 'user_id'],
  ['borrowings', 'user_id'],
  // Master per RT: tiap RT menetapkan jenis iuran dan kategorinya sendiri.
  // Tidak punya kolom penunjuk pemilik, jadi seluruhnya jatuh ke RT bawaan.
  ['jenis_iuran', null],
  ['kategori_kas', null],
  ['kategori_bop', null],
];

const SEMUA_TABEL = ['users', 'keluarga', ...TABEL_BER_RT.map((t) => t[0])];

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v43: satu RW berisi beberapa RT...');
    await client.query('BEGIN');

    // ------------------------------------------------------------ tabel rt
    await client.query(`
      CREATE TABLE IF NOT EXISTS rt (
        id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        kode                VARCHAR(3)  NOT NULL,
        nama                VARCHAR(120),
        rw_kode             VARCHAR(3)  NOT NULL DEFAULT '001',
        ketua_id            UUID,
        alamat_sekretariat  TEXT,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        deleted_at          TIMESTAMP
      );
    `);

    // Satu nomor RT hanya boleh sekali dalam satu RW. Inilah yang mencegah
    // '001' masuk dua kali karena salah ketik di layar tambah RT.
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS rt_rw_kode_uniq
        ON rt (rw_kode, kode) WHERE deleted_at IS NULL;
    `);

    // FK ke users dipasang terpisah supaya CREATE TABLE di atas tetap berhasil
    // pada database yang urutan pembuatan tabelnya berbeda.
    await client.query(`
      DO $tambah$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rt_ketua_id_fkey') THEN
          ALTER TABLE rt ADD CONSTRAINT rt_ketua_id_fkey
            FOREIGN KEY (ketua_id) REFERENCES users(id) ON DELETE SET NULL;
        END IF;
      END
      $tambah$;
    `);

    // --------------------------------------------------- kolom pelingkupan
    for (const tabel of SEMUA_TABEL) {
      await client.query(`ALTER TABLE ${tabel} ADD COLUMN IF NOT EXISTS rt_id UUID;`);
      await client.query(`
        DO $tambah$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = '${tabel}_rt_id_fkey'
          ) THEN
            ALTER TABLE ${tabel} ADD CONSTRAINT ${tabel}_rt_id_fkey
              FOREIGN KEY (rt_id) REFERENCES rt(id) ON DELETE RESTRICT;
          END IF;
        END
        $tambah$;
      `);
      // Setiap kueri daftar sekarang menyaring kolom ini, jadi indeksnya bukan
      // hiasan.
      await client.query(
        `CREATE INDEX IF NOT EXISTS ${tabel}_rt_id_idx ON ${tabel} (rt_id);`
      );
    }

    // ---------------------------------------------------- RT dari data lama
    // RW diambil dari data yang ada. Bila keluarga masih kosong, '001' dipakai
    // — pemasangan baru tidak boleh gagal hanya karena tabelnya belum terisi.
    const rw = await client.query(`
      SELECT COALESCE(
        (SELECT rw FROM keluarga
          WHERE rw IS NOT NULL AND rw <> '' AND deleted_at IS NULL
          GROUP BY rw ORDER BY COUNT(*) DESC LIMIT 1),
        '001'
      ) AS kode;
    `);
    const RW_KODE = rw.rows[0].kode;

    // Seluruh nomor RT yang pernah muncul, dari kedua sisi.
    await client.query(
      `
      INSERT INTO rt (kode, nama, rw_kode)
      SELECT s.k, 'RT ' || s.k, $1::varchar
      FROM (
        SELECT DISTINCT rt AS k FROM keluarga
          WHERE rt IS NOT NULL AND rt <> '' AND deleted_at IS NULL
        UNION
        SELECT DISTINCT no_rt AS k FROM users
          WHERE no_rt IS NOT NULL AND no_rt <> '' AND deleted_at IS NULL
      ) s
      WHERE NOT EXISTS (
        SELECT 1 FROM rt
         WHERE rt.kode = s.k AND rt.rw_kode = $1 AND rt.deleted_at IS NULL
      );
      `,
      [RW_KODE]
    );

    // Jaring pengaman: database yang benar-benar kosong tetap butuh satu RT,
    // kalau tidak seluruh pengisian ulang di bawah tidak punya sasaran.
    await client.query(
      `
      INSERT INTO rt (kode, nama, rw_kode)
      SELECT '001', 'RT 001', $1
      WHERE NOT EXISTS (SELECT 1 FROM rt WHERE deleted_at IS NULL);
      `,
      [RW_KODE]
    );

    const bawaan = await client.query(
      `SELECT id FROM rt WHERE deleted_at IS NULL ORDER BY kode LIMIT 1;`
    );
    const RT_BAWAAN = bawaan.rows[0].id;

    // ------------------------------------------------------ pengisian ulang
    await client.query(
      `UPDATE keluarga k SET rt_id = r.id
         FROM rt r
        WHERE r.kode = k.rt AND r.rw_kode = $1 AND k.rt_id IS NULL;`,
      [RW_KODE]
    );
    await client.query(
      `UPDATE users u SET rt_id = r.id
         FROM rt r
        WHERE r.kode = u.no_rt AND r.rw_kode = $1 AND u.rt_id IS NULL;`,
      [RW_KODE]
    );
    // Akun tanpa nomor RT yang bisa dikenali — pengurus lama dan akun sistem.
    await client.query(`UPDATE users SET rt_id = $1 WHERE rt_id IS NULL;`, [RT_BAWAAN]);
    await client.query(`UPDATE keluarga SET rt_id = $1 WHERE rt_id IS NULL;`, [RT_BAWAAN]);

    for (const [tabel, kolom] of TABEL_BER_RT) {
      if (kolom) {
        await client.query(`
          UPDATE ${tabel} t SET rt_id = u.rt_id
            FROM users u
           WHERE u.id = t.${kolom} AND t.rt_id IS NULL AND u.rt_id IS NOT NULL;
        `);
      }
      await client.query(`UPDATE ${tabel} SET rt_id = $1 WHERE rt_id IS NULL;`, [RT_BAWAAN]);
    }

    await client.query('COMMIT');

    const n = await pool.query('SELECT COUNT(*) c FROM rt WHERE deleted_at IS NULL');
    console.log(
      `✅ Migrasi v43 selesai: tabel rt dibuat (${n.rows[0].c} RT pada RW ${RW_KODE}), `
      + `kolom rt_id terpasang dan terisi pada ${SEMUA_TABEL.length} tabel.`
    );
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v43:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
