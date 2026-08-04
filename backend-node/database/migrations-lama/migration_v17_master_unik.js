require('dotenv').config();
const { pool } = require('./src/config/database');

/**
 * Migrasi v17 — constraint unik untuk tabel master.
 *
 * `seed-master.js` memakai ON CONFLICT DO NOTHING agar aman dijalankan ulang,
 * tetapi klausa itu hanya bekerja bila ADA constraint unik yang bisa dilanggar.
 * `kategori_bop` punya UNIQUE (nama_kategori); `jenis_iuran` dan
 * `kategori_kas` tidak — sehingga setiap kali skrip seed dijalankan ulang,
 * keduanya justru bertambah ganda tanpa suara.
 *
 * Migrasi ini membereskan duplikat yang sudah terlanjur ada, lalu memasang
 * constraint yang hilang supaya kejadian yang sama tidak bisa terulang.
 *
 * Baris duplikat yang dibuang selalu yang ber-id lebih besar, sehingga id
 * terkecil (yang paling mungkin sudah dirujuk tagihan atau transaksi) tetap
 * bertahan.
 */
async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const laporan = [];

    // --- Buang duplikat, sisakan id terkecil per nama -----------------------
    const duplikat = [
      { tabel: 'jenis_iuran', kolom: 'nama_iuran' },
      { tabel: 'kategori_kas', kolom: 'nama_kategori' },
    ];

    for (const d of duplikat) {
      const r = await client.query(
        `DELETE FROM ${d.tabel} a
          USING ${d.tabel} b
          WHERE a.${d.kolom} = b.${d.kolom} AND a.id > b.id`
      );
      const sisa = await client.query(`SELECT COUNT(*)::int n FROM ${d.tabel}`);
      laporan.push(`${d.tabel}: ${r.rowCount} duplikat dibuang, sisa ${sisa.rows[0].n}`);
    }

    // --- Pasang constraint yang hilang -------------------------------------
    // Ditulis lewat DO block karena ADD CONSTRAINT tidak punya IF NOT EXISTS.
    for (const d of duplikat) {
      const nama = `${d.tabel}_${d.kolom}_key`;
      await client.query(`
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = '${nama}'
          ) THEN
            ALTER TABLE ${d.tabel} ADD CONSTRAINT ${nama} UNIQUE (${d.kolom});
          END IF;
        END $$;
      `);
      laporan.push(`${d.tabel}: UNIQUE (${d.kolom}) terpasang`);
    }

    await client.query('COMMIT');

    console.log('Migrasi v17 berhasil:');
    for (const l of laporan) console.log(`  ${l}`);
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migrasi v17 gagal:', err.message);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
