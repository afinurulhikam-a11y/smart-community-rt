/**
 * Migrasi v45 — tabel master menjadi milik masing-masing RT.
 *
 * ===================================================================
 * Apa yang tertinggal dari v43
 * ===================================================================
 *
 * v43 memberi `jenis_iuran`, `kategori_kas`, dan `kategori_bop` kolom `rt_id`
 * dengan niat yang ditulis terang-terangan di sana: "tiap RT menetapkan jenis
 * iuran dan kategorinya sendiri". Yang terjadi hanya separuhnya — seluruh
 * barisnya jatuh ke RT bawaan, dan pengendalinya tidak pernah menyaring.
 *
 * Akibatnya nyata dan bukan sekadar kerapian: nominal iuran, TARIF AIR PER M3,
 * abondement, dan biaya sampah semuanya tersimpan di `jenis_iuran`. Selama
 * tabelnya satu, satu RT yang menaikkan tarif airnya menaikkan tagihan warga
 * SELURUH RW — dan tidak ada satu pun galat, hanya angka yang berubah di
 * tagihan orang lain.
 *
 * ===================================================================
 * Yang sebenarnya menghalangi: sebuah indeks, bukan pengendali
 * ===================================================================
 *
 * `jenis_iuran_nama_iuran_key` unik atas NAMA saja, se-basis-data. Begitu pula
 * `kategori_kas_nama_kategori_key` dan `kategori_bop_nama_kategori_key`.
 * Selama ketiganya ada, RT 002 tidak mungkin punya "Biaya Keamanan" karena
 * RT 001 sudah punya — jadi menambahkan klausa `rt_id` di pengendali saja
 * justru menghasilkan keadaan yang lebih buruk: daftar RT 002 KOSONG, dan
 * dropdown yang kosong membuat Generate Tagihan gagal tanpa keterangan.
 *
 * Karena itu urutannya: indeks dulu, isi menyusul, penyaringan terakhir.
 *
 * ===================================================================
 * Kenapa baris operasional ikut dialihkan
 * ===================================================================
 *
 * `finances.kategori_id`, `bop_finances.kategori_id`, dan `bills.jenis_iuran_id`
 * hari ini semuanya menunjuk baris milik RT bawaan — termasuk baris milik RT
 * kedua, karena dulu memang hanya ada satu salinan. Bila penunjukan itu
 * dibiarkan, transaksi RT 002 akan memakai kategori yang tidak ada di daftar
 * RT 002: layarnya tetap menampilkan namanya (JOIN-nya LEFT), tetapi dropdown
 * saat menyuntingnya tidak memuat pilihan yang sedang terpakai — dan menyimpan
 * ulang akan menggantinya dengan kategori lain tanpa ada yang menyadarinya.
 *
 * Pengalihannya dicocokkan LEWAT NAMA, dan itu bisa dilakukan justru karena
 * langkah penyalinan di atas menyalin dari RT bawaan: setiap nama yang pernah
 * ditunjuk dijamin punya pasangan di RT tujuan.
 *
 * `bills` tidak punya `rt_id`; RT-nya dibaca lewat `keluarga`, sesuai keputusan
 * v43 bahwa yang bertempat tinggal di sebuah RT adalah kartu keluarganya.
 *
 * Idempoten: memeriksa dulu, aman dijalankan berulang. Jalankan terhadap
 * SETIAP database — termasuk Railway, yang tidak menjalankannya sendiri.
 *
 *   node database/migrations/migration_v45_master_per_rt.js
 */
require('dotenv').config();
const { assertCanRunMigration } = require('../../src/config/db-guard');
assertCanRunMigration('migration_v45_master_per_rt');

const { pool } = require('../../src/config/database');

/**
 * [tabel, kolom nama, indeks unik lama, tabel pemakai, kolom penunjuk]
 *
 * Nama indeks lamanya ditulis apa adanya karena itulah yang dibuat Postgres
 * dari `UNIQUE` pada `CREATE TABLE`; `DROP INDEX IF EXISTS` membuat migrasi
 * tetap aman pada basis data yang kebetulan tidak punya salah satunya.
 */
const MASTER = [
  {
    tabel: 'jenis_iuran',
    nama: 'nama_iuran',
    indeksLama: 'jenis_iuran_nama_iuran_key',
    pemakai: 'bills',
    kolom: 'jenis_iuran_id',
    // bills tidak punya rt_id sendiri.
    rtPemakai: '(SELECT k.rt_id FROM keluarga k WHERE k.id = p.keluarga_id)',
  },
  {
    tabel: 'kategori_kas',
    nama: 'nama_kategori',
    indeksLama: 'kategori_kas_nama_kategori_key',
    pemakai: 'finances',
    kolom: 'kategori_id',
    rtPemakai: 'p.rt_id',
  },
  {
    tabel: 'kategori_bop',
    nama: 'nama_kategori',
    indeksLama: 'kategori_bop_nama_kategori_key',
    pemakai: 'bop_finances',
    kolom: 'kategori_id',
    rtPemakai: 'p.rt_id',
  },
];

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Menjalankan migrasi v45: tabel master menjadi milik masing-masing RT...');
    await client.query('BEGIN');

    const rt = await client.query(
      'SELECT id, kode FROM rt WHERE deleted_at IS NULL ORDER BY kode'
    );
    if (!rt.rows.length) {
      throw new Error('Belum ada satu pun RT. Jalankan migrasi v43 lebih dulu.');
    }
    const RT_BAWAAN = rt.rows[0].id;
    console.log(`  RT bawaan: ${rt.rows[0].kode} — ${rt.rows.length} RT total`);

    const ringkas = {};

    for (const m of MASTER) {
      // ---------------------------------------------------- indeks unik
      //
      // Constraint dulu, indeks belakangan — bukan sebaliknya. `UNIQUE` pada
      // `CREATE TABLE` menghasilkan sebuah CONSTRAINT yang DIDUKUNG oleh
      // indeks bernama sama, dan Postgres menolak `DROP INDEX` selama
      // constraint-nya masih ada ("requires it"). Menghapus constraint-nya
      // sudah membawa serta indeksnya; `DROP INDEX` sesudahnya hanya untuk
      // basis data yang indeksnya berdiri sendiri tanpa constraint.
      await client.query(`
        ALTER TABLE ${m.tabel}
          DROP CONSTRAINT IF EXISTS ${m.indeksLama};
      `);
      await client.query(`DROP INDEX IF EXISTS ${m.indeksLama};`);
      await client.query(`
        CREATE UNIQUE INDEX IF NOT EXISTS ${m.tabel}_rt_nama_uniq
          ON ${m.tabel} (rt_id, ${m.nama});
      `);

      // -------------------------------------------------------- salinan
      // Kolomnya dibaca dari katalog, bukan ditulis tangan: ketiga tabel ini
      // punya kolom yang berbeda, dan daftar yang ditulis tangan akan basi
      // diam-diam begitu ada kolom baru — sebuah tarif yang tidak ikut
      // tersalin tidak menimbulkan galat, hanya tagihan yang salah.
      const kol = await client.query(
        `SELECT column_name FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1
            AND column_name NOT IN ('id', 'rt_id')
          ORDER BY ordinal_position`,
        [m.tabel]
      );
      const daftarKolom = kol.rows.map((r) => `"${r.column_name}"`).join(', ');

      let disalin = 0;
      for (const r of rt.rows) {
        if (r.id === RT_BAWAAN) continue;
        const hasil = await client.query(
          `INSERT INTO ${m.tabel} (${daftarKolom}, rt_id)
           SELECT ${daftarKolom}, $1 FROM ${m.tabel} WHERE rt_id = $2
           ON CONFLICT DO NOTHING`,
          [r.id, RT_BAWAAN]
        );
        disalin += hasil.rowCount;
      }

      // ------------------------------------------------------ pengalihan
      const alih = await client.query(`
        UPDATE ${m.pemakai} p
           SET ${m.kolom} = tujuan.id
          FROM ${m.tabel} asal, ${m.tabel} tujuan
         WHERE p.${m.kolom} = asal.id
           AND tujuan.${m.nama} = asal.${m.nama}
           AND tujuan.rt_id = ${m.rtPemakai}
           AND tujuan.id <> asal.id
      `);

      ringkas[m.tabel] = { disalin, dialihkan: alih.rowCount };
      console.log(
        `  ${m.tabel.padEnd(14)} +${disalin} salinan, `
        + `${alih.rowCount} baris ${m.pemakai} dialihkan`
      );
    }

    // Penjaga terakhir: tidak boleh ada baris operasional yang masih menunjuk
    // master milik RT lain. Diperiksa DI DALAM transaksi, jadi migrasi yang
    // tidak tuntas dibatalkan seluruhnya alih-alih meninggalkan campuran.
    const sisa = await client.query(`
      SELECT
        (SELECT COUNT(*)::int FROM finances f JOIN kategori_kas k ON k.id = f.kategori_id
          WHERE k.rt_id IS DISTINCT FROM f.rt_id) AS kas,
        (SELECT COUNT(*)::int FROM bop_finances b JOIN kategori_bop k ON k.id = b.kategori_id
          WHERE k.rt_id IS DISTINCT FROM b.rt_id) AS bop,
        (SELECT COUNT(*)::int FROM bills bl
           JOIN keluarga kk ON kk.id = bl.keluarga_id
           JOIN jenis_iuran j ON j.id = bl.jenis_iuran_id
          WHERE j.rt_id IS DISTINCT FROM kk.rt_id) AS iuran
    `);
    const s = sisa.rows[0];
    if (s.kas || s.bop || s.iuran) {
      throw new Error(
        `Masih ada penunjukan lintas RT setelah pengalihan — `
        + `kas=${s.kas}, bop=${s.bop}, iuran=${s.iuran}. Transaksi dibatalkan.`
      );
    }

    await client.query('COMMIT');
    console.log('✅ Migrasi v45 selesai:', JSON.stringify(ringkas));
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Gagal menjalankan migrasi v45:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch(() => process.exit(1));
}

module.exports = { migrate };
