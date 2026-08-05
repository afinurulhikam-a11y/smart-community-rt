const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { pool } = require('./database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS } = require('./permissions');

/**
 * Penyemaian saat server start.
 *
 * ===================================================================
 * Aturan utama: MENYEMAI, BUKAN MEMAKSA
 * ===================================================================
 *
 * Fungsi ini berjalan pada SETIAP start — di Railway berarti setiap deploy.
 * Versi sebelumnya menulis ulang tiga hal tanpa memedulikan keadaan yang ada,
 * dan ketiganya membatalkan keputusan yang diambil administrator:
 *
 * 1. `users` dengan username 'Administrator' di-upsert dengan sandi 'admin123'
 *    yang tertulis di kode. Mengganti sandinya percuma — deploy berikutnya
 *    mengembalikannya. Menghapusnya percuma — ia dibuat lagi. Sistem produksi
 *    jadi punya akun admin bersandi yang terbaca siapa pun di repositori.
 *
 * 2. `role_permissions` ditimpa dengan DEFAULT_PERMISSIONS. Setiap perubahan
 *    lewat layar Menu & Akses kembali ke bawaan pada deploy berikutnya — dan
 *    tanpa satu baris log pun. Jejak audit mencatat "izin warga diubah", lalu
 *    diam-diam berubah balik; pembaca log akan yakin perubahan masih berlaku.
 *
 * 3. `menu_items.is_aktif` dipaksa true, sehingga menu yang sengaja dimatikan
 *    menyala lagi.
 *
 * Sekarang: baris hanya dibuat bila belum ada. Metadata yang memang milik kode
 * (nama menu, grup, urutan) tetap disegarkan, karena itu tidak pernah diedit
 * lewat aplikasi. Untuk mengembalikan izin ke bawaan sudah ada jalannya sendiri
 * dan jalan itu tercatat di log: POST /api/menu-akses/reset.
 */
async function autoSetupCloud() {
  console.log('🔄 Memeriksa & menginisialisasi database PostgreSQL...');

  // 1. Skema database (Abaikan jika tabel sudah ada)
  try {
    await pool.query(`
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
      ALTER TABLE patrol_schedules ADD COLUMN IF NOT EXISTS tanggal DATE;

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
      ALTER TABLE patrol_attendances ADD COLUMN IF NOT EXISTS tipe_absen VARCHAR(20) DEFAULT 'Masuk';
      ALTER TABLE patrol_attendances ADD COLUMN IF NOT EXISTS waktu_masuk TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
      ALTER TABLE patrol_attendances ADD COLUMN IF NOT EXISTS waktu_pulang TIMESTAMP WITH TIME ZONE;
      ALTER TABLE patrol_attendances ADD COLUMN IF NOT EXISTS foto_url TEXT;

      CREATE TABLE IF NOT EXISTS patrol_qr_tokens (
        id SERIAL PRIMARY KEY,
        token VARCHAR(100) NOT NULL UNIQUE,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log('✅ Skema tabel Siskamling (patrol_schedules, patrol_attendances, patrol_qr_tokens) terverifikasi.');
  } catch (e) {
    console.log('ℹ️ Catatan Skema (Lanjut):', e.message);
  }

  // 2. Menu items
  try {
    for (let i = 0; i < MENU_ITEMS.length; i++) {
      const m = MENU_ITEMS[i];
      // `is_aktif` SENGAJA tidak ikut diperbarui: kolom itu milik administrator,
      // disetel lewat Menu & Akses. Memaksanya true di sini membuat menu yang
      // sengaja dimatikan menyala lagi setiap deploy. Sisanya metadata milik
      // kode dan tidak pernah diedit lewat aplikasi, jadi aman disegarkan.
      await pool.query(
        `INSERT INTO menu_items (kode, nama, grup, menu_index, urutan, is_sistem, is_aktif)
         VALUES ($1, $2, $3, $4, $5, $6, true)
         ON CONFLICT (kode) DO UPDATE SET
           nama = EXCLUDED.nama, grup = EXCLUDED.grup,
           menu_index = EXCLUDED.menu_index, urutan = EXCLUDED.urutan,
           is_sistem = EXCLUDED.is_sistem`,
        [m.kode, m.nama, m.grup, m.menu_index, i, m.is_sistem === true]
      );
    }
  } catch (e) {
    console.log('ℹ️ Catatan Menu:', e.message);
  }

  // 3. Permissions
  try {
    for (const [role, menus] of Object.entries(DEFAULT_PERMISSIONS)) {
      for (const [kode, p] of Object.entries(menus)) {
        await pool.query(
          // DO NOTHING, bukan DO UPDATE. Baris izin yang sudah ada adalah
          // keputusan administrator; menimpanya di sini membuat layar Menu &
          // Akses hanya berlaku sampai deploy berikutnya. Untuk kembali ke
          // bawaan gunakan POST /api/menu-akses/reset — jalan itu tercatat.
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (role, menu_kode) DO NOTHING`,
          [role, kode, p.view, p.create, p.update, p.delete]
        );
      }
    }

    // Koreksi khusus: cabut can_create warga di kegiatan.ronda akibat bug matriks awal
    await pool.query(
      `UPDATE role_permissions
       SET can_create = false
       WHERE role = 'warga' AND menu_kode = 'kegiatan.ronda' AND can_create = true`
    );
  } catch (e) {
    console.log('ℹ️ Catatan Permission:', e.message);
  }

  // 4. Akun admin darurat — HANYA bila sistem sama sekali belum punya admin.
  //
  // Tujuannya satu: instalasi baru tidak boleh terkunci tanpa jalan masuk.
  // Begitu satu akun admin ada, fungsi ini tidak menyentuh apa pun lagi —
  // sandinya tidak dipaksa, perannya tidak dipaksa, statusnya tidak dipaksa.
  //
  // Sandinya diacak dan dicetak SEKALI ke log deploy, tidak ditulis di kode.
  // Sandi tetap di dalam sumber berarti sandi itu terbaca siapa pun yang bisa
  // membuka repositori, dan tidak ada cara menutupnya lewat aplikasi.
  try {
    const adaAdmin = await pool.query(
      "SELECT 1 FROM users WHERE role = 'admin' LIMIT 1"
    );

    if (adaAdmin.rows.length > 0) {
      console.log('✅ Akun admin sudah ada — tidak ada yang diubah.');
    } else {
      // 24 karakter, huruf-angka saja: aman dilewatkan URL dan mudah disalin
      // dari log tanpa salah baca karakter.
      const sandiAwal = crypto.randomBytes(18).toString('base64url').slice(0, 24);
      const hashAdmin = await bcrypt.hash(sandiAwal, await bcrypt.genSalt(10));

      await pool.query(
        `INSERT INTO users (nama, email, username, password_hash, role, is_active)
         VALUES ($1, NULL, $2, $3, 'admin', true)
         ON CONFLICT (username) DO NOTHING`,
        ['Administrator', 'Administrator', hashAdmin]
      );

      console.log('');
      console.log('════════════════════════════════════════════════════════════');
      console.log('  AKUN ADMIN PERTAMA DIBUAT — sandi ini hanya tampil sekali');
      console.log('');
      console.log(`    Username : Administrator`);
      console.log(`    Sandi    : ${sandiAwal}`);
      console.log('');
      console.log('  Catat sekarang, lalu ganti lewat Profil Saya.');
      console.log('════════════════════════════════════════════════════════════');
      console.log('');
    }
  } catch (e) {
    console.error('❌ Gagal memeriksa/membuat akun admin:', e.message);
  }

  // 5. Seed Master Categories (Jenis Iuran, Kategori Kas, Kategori BOP)
  try {
    const { JENIS_IURAN, KATEGORI_KAS, KATEGORI_BOP } = require('./master-data');

    for (const j of JENIS_IURAN) {
      await pool.query(
        `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, is_aktif)
         VALUES ($1, $2, $3, true)
         ON CONFLICT DO NOTHING`,
        [j.nama, j.nominal, j.periode]
      );
    }

    for (const k of KATEGORI_KAS) {
      await pool.query(
        `INSERT INTO kategori_kas (nama_kategori, tipe, is_aktif)
         VALUES ($1, $2, true)
         ON CONFLICT DO NOTHING`,
        [k.nama, k.tipe]
      );
    }

    for (const k of KATEGORI_BOP) {
      await pool.query(
        `INSERT INTO kategori_bop (nama_kategori, tipe, is_aktif)
         VALUES ($1, $2, true)
         ON CONFLICT DO NOTHING`,
        [k.nama, k.tipe]
      );
    }
    console.log('✅ Master Kategori Kas, BOP, dan Jenis Iuran terverifikasi.');
  } catch (e) {
    console.log('ℹ️ Catatan Master Categories:', e.message);
  }
}

module.exports = { autoSetupCloud };
