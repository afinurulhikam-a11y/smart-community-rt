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
    await pool.query(`SELECT 1`);
  } catch (e) {
    console.log('ℹ️ Catatan Skema (Lanjut):', e.message);
  }

  // 1b. Kolom wajib-ganti-sandi pada users
  //
  // `tambahWargaLengkap` dan `updateUserCredentials` menulis kolom
  // `must_change_password`. Kolom itu dibuat oleh migration_v23, yang hanya
  // berjalan sekali lewat skrip manual. Database yang dibuat sebelum migrasi
  // itu (mis. Railway yang dipasang lebih dulu) tidak punya kolomnya, sehingga
  // INSERT akun warga baru gagal dengan "column must_change_password ... does
  // not exist" — dan SELURUH transaksi di-rollback. Entri idempoten ini
  // menutup celah itu tiap deploy, tanpa menimpa apa pun yang sudah ada.
  try {
    await pool.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
    `);
    console.log('✅ users.must_change_password terverifikasi.');
  } catch (e) {
    console.log('ℹ️ Catatan Skema users.must_change_password (Lanjut):', e.message);
  }

  // 1c. Skema & Kolom Bantuan Sosial (v26 & v27)
  try {
    await pool.query(`
      ALTER TABLE bantuan_sosial ADD COLUMN IF NOT EXISTS bentuk_bantuan VARCHAR(50) DEFAULT 'Tunai';
      ALTER TABLE bantuan_sosial ADD COLUMN IF NOT EXISTS sumber_bantuan VARCHAR(100) DEFAULT 'Pemerintah Pusat';
      ALTER TABLE bantuan_sosial ADD COLUMN IF NOT EXISTS no_sk VARCHAR(100);
      ALTER TABLE bantuan_sosial ADD COLUMN IF NOT EXISTS tanggal_bantuan DATE;
      ALTER TABLE bantuan_sosial ADD COLUMN IF NOT EXISTS tanggal_mulai DATE;
      ALTER TABLE bantuan_sosial ADD COLUMN IF NOT EXISTS tanggal_selesai DATE;
      ALTER TABLE bantuan_sosial ALTER COLUMN tahun DROP NOT NULL;
    `);
    console.log('✅ bantuan_sosial skema & kolom terverifikasi.');
  } catch (e) {
    console.log('ℹ️ Catatan Skema bantuan_sosial (Lanjut):', e.message);
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
        `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, is_aktif,
                                  tipe_hitung, tarif_per_m3, abondement, biaya_sampah)
         VALUES ($1, $2, $3, true, $4, $5, $6, $7)
         ON CONFLICT DO NOTHING`,
        [
          j.nama, j.nominal, j.periode,
          j.tipe_hitung || 'tetap', j.tarif_per_m3 || null,
          j.abondement || 0, j.biaya_sampah || 0,
        ]
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

  // 6. Bersihkan Akun Demo Duplikat & Seed Akun Pengurus Bawaan (Ketua RT, Sekretaris, Bendahara)
  try {
    const demoRes = await pool.query(
      `SELECT id FROM users WHERE username IN ('ketua_demo', 'sekretaris_demo', 'bendahara_demo')`
    );
    if (demoRes.rows.length > 0) {
      const ids = demoRes.rows.map((r) => r.id);
      const adminRes = await pool.query(
        `SELECT id FROM users WHERE role = 'admin' AND deleted_at IS NULL ORDER BY created_at LIMIT 1`
      );
      const adminId = adminRes.rows[0]?.id;

      await pool.query(`UPDATE bills SET user_id = $2 WHERE user_id = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE bills SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE bill_payments SET user_id = $2 WHERE user_id = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE finances SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE emergency_alerts SET user_id = $2 WHERE user_id = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE emergency_alerts SET dismissed_by = NULL WHERE dismissed_by = ANY($1)`, [ids]);
      await pool.query(`UPDATE letters SET user_id = $2 WHERE user_id = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE letters SET approved_by = NULL WHERE approved_by = ANY($1)`, [ids]);
      await pool.query(`UPDATE bop_finances SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE alokasi_bop SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE borrowings SET dicatat_oleh = $2 WHERE dicatat_oleh = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE payment_transactions SET user_id = $2 WHERE user_id = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE announcements SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE agenda SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE polling SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE visitors SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE bantuan_sosial SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE inventory SET created_by = $2 WHERE created_by = ANY($1)`, [ids, adminId]);
      await pool.query(`UPDATE complaints SET responded_by = NULL WHERE responded_by = ANY($1)`, [ids]);
      await pool.query(`UPDATE bantuan_sosial_log SET changed_by = NULL WHERE changed_by = ANY($1)`, [ids]);
      await pool.query(`UPDATE reset_logs SET user_id = NULL WHERE user_id = ANY($1)`, [ids]);
      await pool.query(`UPDATE pembacaan_meteran SET diisi_oleh = NULL WHERE diisi_oleh = ANY($1)`, [ids]);
      await pool.query(`UPDATE pembacaan_meteran SET dikoreksi_oleh = NULL WHERE dikoreksi_oleh = ANY($1)`, [ids]);
      await pool.query(`DELETE FROM user_fcm_tokens WHERE user_id = ANY($1)`, [ids]);
      await pool.query(`DELETE FROM users WHERE id = ANY($1)`, [ids]);
      console.log('✅ Akun demo lama (ketua_demo, sekretaris_demo, bendahara_demo) berhasil dibersihkan.');
    }

    const { PENGURUS_AWAL, WARGA_UJI } = require('./master-data');
    const defaultAccounts = [...PENGURUS_AWAL, WARGA_UJI];
    for (const p of defaultAccounts) {
      const ada = await pool.query(
        'SELECT id FROM users WHERE username = $1 OR email = $2',
        [p.username, p.email]
      );
      if (ada.rowCount === 0) {
        const hash = await bcrypt.hash(p.password, 10);
        await pool.query(
          `INSERT INTO users (nama, email, username, password_hash, role, is_active)
           VALUES ($1, $2, $3, $4, $5, true)
           ON CONFLICT (username) DO NOTHING`,
          [p.nama, p.email, p.username, hash, p.role]
        );
        console.log(`✅ Akun default ${p.role} (${p.username}) dibuat.`);
      } else {
        // Pastikan username dan password_hash terpasang bila ada akun lama
        const hash = await bcrypt.hash(p.password, 10);
        await pool.query(
          `UPDATE users SET username = $1, password_hash = $2, nama = $3, is_active = true WHERE id = $4`,
          [p.username, hash, p.nama, ada.rows[0].id]
        );
      }
    }
  } catch (e) {
    console.log('ℹ️ Catatan Akun Pengurus/Warga:', e.message);
  }
}

module.exports = { autoSetupCloud };
