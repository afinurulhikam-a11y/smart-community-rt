/**
 * Migrasi v22 — menyamakan database lama dengan `database/schema.sql`.
 *
 * ===================================================================
 * Kenapa berkas ini ada
 * ===================================================================
 *
 * `schema.sql` hanya dibaca oleh `init-db.js`, yaitu saat membuat database
 * BARU. Database yang sudah berjalan lebih dulu — seperti PostgreSQL di
 * Railway — tidak pernah menerima apa pun darinya. Setiap perbaikan skema yang
 * ditulis ke `schema.sql` karena itu hanya berlaku untuk instalasi baru, dan
 * database produksi tetap tertinggal tanpa ada yang menyadarinya.
 *
 * Yang paling berbahaya dari ketertinggalan itu bukan galat yang terlihat,
 * melainkan yang TIDAK terlihat:
 *
 *   `authMiddleware` menjalankan
 *       SELECT ... FROM users WHERE id = $1 AND deleted_at IS NULL
 *   Tanpa kolom itu kueri melempar, dan blok catch-nya jatuh kembali memakai
 *   payload JWT apa adanya supaya sesi pengguna tidak ikut putus.
 *
 *   Akibatnya seluruh perbaikan "sesi bisa dicabut" menjadi mati suri: peran
 *   dibaca dari token lagi, sehingga menonaktifkan, menurunkan, atau menghapus
 *   akun TIDAK memutus sesinya sampai tokennya kedaluwarsa sendiri — tujuh
 *   hari kemudian. Aplikasinya tetap berjalan mulus, jadi tidak ada satu pun
 *   gejala yang memberi tahu bahwa penjagaannya sedang tidak bekerja.
 *
 * Berkas ini memeriksa, melaporkan apa yang tertinggal, lalu menambalnya.
 *
 * Idempoten: aman dijalankan berulang, dan tidak mengubah apa pun yang sudah
 * benar. Jalankan terhadap SETIAP database yang dibuat sebelum perubahan ini —
 * termasuk Railway.
 */
require('dotenv').config();
const { pool } = require('./src/config/database');

/** Tabel yang memakai soft delete, sesuai dua skrip migrasi aslinya. */
const TABEL_SOFT_DELETE = [
  'users', 'keluarga', 'inventory', 'complaints', 'letters', 'agenda', 'finances',
];

/** Indeks parsial untuk tiap tabel di atas — daftar hanya menyaring yang aktif. */
const INDEKS_AKTIF = {
  users: 'idx_users_aktif',
  keluarga: 'idx_keluarga_aktif',
  inventory: 'idx_inventory_aktif',
  complaints: 'idx_complaints_aktif',
  letters: 'idx_letters_aktif',
  agenda: 'idx_agenda_aktif',
  finances: 'idx_finances_aktif',
};

/** Indeks kolom panas dari v21. */
const INDEKS_V21 = [
  ['idx_bill_payments_bill', 'bill_payments (bill_id)'],
  ['idx_visitors_status', 'visitors (status)'],
  ['idx_visitors_tipe', 'visitors (tipe_keperluan)'],
  ['idx_visitors_tanggal', 'visitors ((jam_masuk::date))'],
  ['idx_visitors_pembuat', 'visitors (created_by)'],
  ['idx_patrol_absensi_user_tgl', 'patrol_attendances (user_id, tanggal)'],
  ['idx_patrol_absensi_tanggal', 'patrol_attendances (tanggal DESC)'],
  ['idx_complaints_user', 'complaints (user_id)'],
  ['idx_complaints_status', 'complaints (status)'],
  ['idx_letters_user', 'letters (user_id)'],
  ['idx_letters_status', 'letters (status)'],
  ['idx_borrowings_user', 'borrowings (user_id)'],
  ['idx_payment_trx_user', 'payment_transactions (user_id)'],
  ['idx_anggota_keluarga_kk', 'anggota_keluarga (keluarga_id)'],
  ['idx_polling_options_polling', 'polling_options (polling_id)'],
];

async function adaKolom(client, tabel, kolom) {
  const r = await client.query(
    `SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2`,
    [tabel, kolom]
  );
  return r.rows.length > 0;
}

async function adaTabel(client, tabel) {
  const r = await client.query(
    `SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = $1`,
    [tabel]
  );
  return r.rows.length > 0;
}

async function jalankan() {
  const client = await pool.connect();
  const laporan = { ditambah: [], sudahAda: [], dilewati: [] };

  try {
    await client.query('BEGIN');

    // -----------------------------------------------------------------
    // 1. Kolom soft delete
    // -----------------------------------------------------------------
    console.log('\n── Memeriksa kolom deleted_at ──────────────────────');
    for (const tabel of TABEL_SOFT_DELETE) {
      if (!(await adaTabel(client, tabel))) {
        console.log(`  ⏭️  ${tabel.padEnd(12)} tabelnya belum ada — dilewati`);
        laporan.dilewati.push(tabel);
        continue;
      }
      if (await adaKolom(client, tabel, 'deleted_at')) {
        console.log(`  ✔️  ${tabel.padEnd(12)} sudah ada`);
        laporan.sudahAda.push(tabel);
        continue;
      }
      await client.query(`ALTER TABLE ${tabel} ADD COLUMN deleted_at TIMESTAMP DEFAULT NULL`);
      console.log(`  ➕ ${tabel.padEnd(12)} DITAMBAHKAN`);
      laporan.ditambah.push(tabel);
    }

    // -----------------------------------------------------------------
    // 1b. users.updated_at
    // -----------------------------------------------------------------
    //
    // `users` satu-satunya dari lima belas tabel yang ditulisi `updated_at`
    // oleh kode tetapi tidak punya kolomnya. Setiap perubahan akun karena itu
    // gagal 500 — ubah peran, nonaktifkan akun, atur ulang sandi, ketiganya —
    // dan controller-nya membalas pesan umum sehingga sebabnya hanya terlihat
    // di log server.
    console.log('\n── Memeriksa users.updated_at ──────────────────────');
    if (await adaKolom(client, 'users', 'updated_at')) {
      console.log('  ✔️  users.updated_at sudah ada');
    } else {
      await client.query(
        `ALTER TABLE users ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
      );
      console.log('  ➕ users.updated_at DITAMBAHKAN');
      laporan.ditambah.push('users.updated_at');
    }

    // Indeks parsial menyusul kolomnya.
    for (const [tabel, indeks] of Object.entries(INDEKS_AKTIF)) {
      if (laporan.dilewati.includes(tabel)) continue;
      await client.query(
        `CREATE INDEX IF NOT EXISTS ${indeks} ON ${tabel} (id) WHERE deleted_at IS NULL`
      );
    }

    // -----------------------------------------------------------------
    // 2. Tabel Siskamling
    // -----------------------------------------------------------------
    //
    // Ketiganya dibuat `auto-setup.js` saat server menyala, bukan oleh
    // schema.sql. Dibuat juga di sini supaya database yang belum pernah
    // menjalankan servernya tetap lengkap.
    console.log('\n── Memeriksa tabel Siskamling ──────────────────────');
    await client.query(`
      CREATE TABLE IF NOT EXISTS patrol_schedules (
        id SERIAL PRIMARY KEY,
        hari VARCHAR(20) NOT NULL,
        tanggal DATE,
        shift VARCHAR(50) DEFAULT 'Shift Malam (22:00 - 04:00)',
        petugas_warga TEXT NOT NULL,
        keterangan TEXT,
        created_by UUID REFERENCES users(id) ON DELETE SET NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS patrol_attendances (
        id SERIAL PRIMARY KEY,
        schedule_id INTEGER REFERENCES patrol_schedules(id) ON DELETE SET NULL,
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        nama_petugas VARCHAR(150) NOT NULL,
        tanggal DATE DEFAULT CURRENT_DATE,
        tipe_absen VARCHAR(20) DEFAULT 'Masuk',
        waktu_scan TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        waktu_masuk TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        waktu_pulang TIMESTAMP WITH TIME ZONE,
        lokasi_pos VARCHAR(150) DEFAULT 'Pos Ronda Utama',
        status VARCHAR(50) DEFAULT 'Aktif Ronda',
        catatan TEXT,
        foto_url TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS patrol_qr_tokens (
        id SERIAL PRIMARY KEY,
        token VARCHAR(100) NOT NULL UNIQUE,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log('  ✔️  patrol_schedules / patrol_attendances / patrol_qr_tokens siap');

    // -----------------------------------------------------------------
    // 3. Jaring pengaman konkurensi (v21)
    // -----------------------------------------------------------------
    console.log('\n── Memeriksa jaring pengaman v21 ───────────────────');

    const ganda = await client.query(`
      SELECT bill_id, COUNT(*)::int AS jumlah FROM bill_payments
      GROUP BY bill_id HAVING COUNT(*) > 1
    `);
    if (ganda.rows.length > 0) {
      console.log(`  ⚠️  ${ganda.rows.length} tagihan punya lebih dari satu pembayaran:`);
      for (const r of ganda.rows) console.log(`      bill_id ${r.bill_id} — ${r.jumlah} pembayaran`);
      console.log('      Constraint TIDAK dipasang. Periksa baris di atas lebih dulu —');
      console.log('      kemungkinan besar itu dobel-posting ke Kas RT yang perlu dikoreksi.');
    } else {
      await client.query(
        `CREATE UNIQUE INDEX IF NOT EXISTS bill_payments_satu_per_tagihan ON bill_payments (bill_id)`
      );
      console.log('  ✔️  bill_payments: satu pembayaran per tagihan');
    }

    const absenGanda = await client.query(`
      SELECT user_id, tanggal, COUNT(*)::int AS jumlah FROM patrol_attendances
      WHERE waktu_pulang IS NULL GROUP BY user_id, tanggal HAVING COUNT(*) > 1
    `);
    if (absenGanda.rows.length > 0) {
      console.log(`  ⚠️  ${absenGanda.rows.length} petugas punya lebih dari satu absensi aktif — dilewati.`);
    } else {
      await client.query(`
        CREATE UNIQUE INDEX IF NOT EXISTS patrol_absensi_aktif_uniq
          ON patrol_attendances (user_id, tanggal) WHERE waktu_pulang IS NULL
      `);
      console.log('  ✔️  patrol_attendances: satu absensi aktif per petugas per hari');
    }

    for (const [nama, definisi] of INDEKS_V21) {
      await client.query(`CREATE INDEX IF NOT EXISTS ${nama} ON ${definisi}`);
    }
    console.log(`  ✔️  ${INDEKS_V21.length} indeks kolom panas siap`);

    // -----------------------------------------------------------------
    // 4. Periksa v19 & v20 — hanya melaporkan, tidak menambal
    // -----------------------------------------------------------------
    //
    // Keduanya punya skripnya sendiri dan membuktikan penolakan lewat uji yang
    // tidak layak dijalankan diam-diam di dalam migrasi lain.
    console.log('\n── Memeriksa jejak audit (v19 & v20) ───────────────');

    const trigger = await client.query(`
      SELECT tgname FROM pg_trigger
      WHERE tgrelid = 'activity_logs'::regclass AND NOT tgisinternal ORDER BY tgname
    `);
    const namaTrigger = trigger.rows.map((r) => r.tgname);
    const wajib = ['trg_activity_logs_append_only', 'trg_activity_logs_no_truncate'];
    const kurang = wajib.filter((w) => !namaTrigger.includes(w));

    if (kurang.length === 0) {
      console.log('  ✔️  Trigger hanya-tambah lengkap');
    } else {
      console.log(`  ❗ Trigger belum lengkap: ${kurang.join(', ')}`);
      console.log('      Jalankan: node database/migrations-lama/migration_v19_log_append_only.js');
    }

    const fk = await client.query(`
      SELECT conname FROM pg_constraint
      WHERE conrelid = 'activity_logs'::regclass AND contype = 'f'
    `);
    if (fk.rows.length === 0) {
      console.log('  ✔️  FK activity_logs.user_id sudah dilepas');
    } else {
      console.log(`  ❗ FK masih terpasang: ${fk.rows.map((r) => r.conname).join(', ')}`);
      console.log('      Akun yang pernah muncul di jejak audit tidak akan bisa dihapus.');
      console.log('      Jalankan: node database/migrations-lama/migration_v20_log_lepas_fk_user.js');
    }

    await client.query('COMMIT');

    console.log('\n════════════════════════════════════════════════════');
    if (laporan.ditambah.length > 0) {
      console.log(`✅ Skema disamakan. ${laporan.ditambah.length} kolom deleted_at ditambahkan:`);
      console.log(`   ${laporan.ditambah.join(', ')}`);
      console.log('');
      console.log('   Yang ikut pulih karena ini — semuanya sebelumnya gagal diam-diam:');
      console.log('   • authMiddleware kembali membaca peran dari DATABASE, bukan token.');
      console.log('     Selama kolomnya hilang, kueri itu melempar dan middleware jatuh ke');
      console.log('     payload JWT — sehingga menonaktifkan atau menurunkan peran sebuah');
      console.log('     akun TIDAK memutus sesinya sampai tokennya kedaluwarsa sendiri.');
      console.log('   • Daftar warga, keluarga, pengaduan, surat, inventaris, agenda, dan');
      console.log('     Kas RT tidak lagi menabrak galat kolom.');
    } else {
      console.log('✅ Skema sudah sesuai. Tidak ada yang perlu diubah.');
    }
    console.log('════════════════════════════════════════════════════\n');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migrasi v22 dibatalkan:', err.message);
    console.error('   Tidak ada perubahan yang tersimpan.\n');
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

jalankan();
