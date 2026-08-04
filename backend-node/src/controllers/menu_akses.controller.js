const { pool } = require('../config/database');
const { logActivity } = require('../services/log.service');
const { DEFAULT_PERMISSIONS, ROLES, ROLE_LABEL } = require('../config/permissions');
const { ROLE_ADMIN } = require('../middleware/auth.middleware');

const AKSI = ['can_view', 'can_create', 'can_update', 'can_delete'];

/** Daftar menu beserta izin seluruh role, untuk layar Menu & Akses. */
async function getMenuAkses(req, res) {
  try {
    const [menus, izin] = await Promise.all([
      pool.query('SELECT * FROM menu_items ORDER BY urutan ASC, id ASC'),
      pool.query('SELECT * FROM role_permissions'),
    ]);

    // Peta izin per menu agar klien tidak perlu mencocokkan sendiri.
    const peta = {};
    for (const p of izin.rows) {
      peta[p.menu_kode] ??= {};
      peta[p.menu_kode][p.role] = {
        can_view: p.can_view,
        can_create: p.can_create,
        can_update: p.can_update,
        can_delete: p.can_delete,
      };
    }

    const data = menus.rows.map((m) => ({
      ...m,
      izin: Object.fromEntries(
        ROLES.map((r) => [
          r,
          // Admin selalu ditampilkan penuh: itu yang sebenarnya berlaku di
          // middleware, terlepas dari apa pun isi tabel.
          r === ROLE_ADMIN
            ? { can_view: true, can_create: true, can_update: true, can_delete: true }
            : (peta[m.kode]?.[r] ?? { can_view: false, can_create: false, can_update: false, can_delete: false }),
        ])
      ),
    }));

    return res.status(200).json({
      success: true,
      count: data.length,
      data,
      roles: ROLES.map((r) => ({ kode: r, nama: ROLE_LABEL[r], terkunci: r === ROLE_ADMIN })),
    });
  } catch (err) {
    console.error('GetMenuAkses Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * Izin efektif pengguna yang sedang login — dipakai sidebar untuk menentukan
 * menu apa yang ditampilkan. Semua role boleh memanggilnya untuk dirinya
 * sendiri; tidak ada informasi role lain yang bocor di sini.
 */
async function getMenuAksesSaya(req, res) {
  try {
    const role = req.user.role;

    const menus = await pool.query(
      `SELECT m.kode, m.nama, m.grup, m.menu_index, m.is_sistem,
              COALESCE(p.can_view, false) AS can_view,
              COALESCE(p.can_create, false) AS can_create,
              COALESCE(p.can_update, false) AS can_update,
              COALESCE(p.can_delete, false) AS can_delete
       FROM menu_items m
       LEFT JOIN role_permissions p ON p.menu_kode = m.kode AND p.role = $1
       WHERE m.is_aktif = true
       ORDER BY m.urutan ASC, m.id ASC`,
      [role]
    );

    const data = menus.rows.map((m) =>
      role === ROLE_ADMIN
        ? { ...m, can_view: true, can_create: true, can_update: true, can_delete: true }
        // Menu sistem tidak pernah terbuka untuk selain admin, apa pun isi tabel.
        : (m.is_sistem
            ? { ...m, can_view: false, can_create: false, can_update: false, can_delete: false }
            : m)
    );

    return res.status(200).json({
      success: true,
      data: { role, role_label: ROLE_LABEL[role] || role, menus: data },
    });
  } catch (err) {
    console.error('GetMenuAksesSaya Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/** Simpan perubahan izin secara massal, satu transaksi. */
async function updateMenuAkses(req, res) {
  const client = await pool.connect();
  try {
    const { perubahan } = req.body;
    if (!Array.isArray(perubahan) || perubahan.length === 0) {
      return res.status(400).json({ success: false, message: 'Tidak ada perubahan untuk disimpan.' });
    }

    // Tolak lebih dulu, sebelum menyentuh database sama sekali.
    const adaAdmin = perubahan.some((p) => p.role === ROLE_ADMIN);
    if (adaAdmin) {
      return res.status(409).json({
        success: false,
        message: 'Izin Administrator tidak bisa diubah. Ini disengaja, supaya tidak ada yang bisa mengunci dirinya sendiri dari sistem.',
      });
    }

    const kodeSistem = await client.query('SELECT kode, nama FROM menu_items WHERE is_sistem = true');
    const setSistem = new Map(kodeSistem.rows.map((r) => [r.kode, r.nama]));
    const langgar = perubahan.find((p) => setSistem.has(p.menu_kode));
    if (langgar) {
      return res.status(409).json({
        success: false,
        message: `${setSistem.get(langgar.menu_kode)} hanya untuk Administrator dan tidak bisa diberikan ke role lain.`,
      });
    }

    const roleTidakDikenal = perubahan.find((p) => !ROLES.includes(p.role));
    if (roleTidakDikenal) {
      return res.status(400).json({
        success: false,
        message: `Role "${roleTidakDikenal.role}" tidak dikenali.`,
      });
    }

    await client.query('BEGIN');

    let tersimpan = 0;
    for (const p of perubahan) {
      const r = await client.query(
        `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())
         ON CONFLICT (role, menu_kode) DO UPDATE SET
           can_view = EXCLUDED.can_view,
           can_create = EXCLUDED.can_create,
           can_update = EXCLUDED.can_update,
           can_delete = EXCLUDED.can_delete,
           updated_at = NOW()
         RETURNING id`,
        [
          p.role, p.menu_kode,
          p.can_view === true, p.can_create === true,
          p.can_update === true, p.can_delete === true,
        ]
      );
      if (r.rowCount > 0) tersimpan++;
    }

    await client.query('COMMIT');
    await logActivity(req, 'AKSES', `Mengubah ${tersimpan} pengaturan hak akses role`);
    return res.status(200).json({
      success: true,
      message: `${tersimpan} pengaturan izin berhasil disimpan. Perubahan berlaku setelah pengguna terkait masuk ulang.`,
      data: { tersimpan },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('UpdateMenuAkses Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

/** Kembalikan seluruh izin ke matriks bawaan di config/permissions.js. */
async function resetMenuAkses(req, res) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let jumlah = 0;
    for (const [role, menus] of Object.entries(DEFAULT_PERMISSIONS)) {
      for (const [kode, p] of Object.entries(menus)) {
        await client.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, NOW())
           ON CONFLICT (role, menu_kode) DO UPDATE SET
             can_view = EXCLUDED.can_view,
             can_create = EXCLUDED.can_create,
             can_update = EXCLUDED.can_update,
             can_delete = EXCLUDED.can_delete,
             updated_at = NOW()`,
          [role, kode, p.view, p.create, p.update, p.delete]
        );
        jumlah++;
      }
    }

    await client.query('COMMIT');
    await logActivity(req, 'AKSES', `Mengembalikan seluruh hak akses ke pengaturan bawaan (${jumlah} baris)`);
    return res.status(200).json({
      success: true,
      message: `Hak akses dikembalikan ke pengaturan bawaan (${jumlah} baris).`,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('ResetMenuAkses Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

/** Aktif/nonaktifkan sebuah menu untuk semua role sekaligus. */
async function toggleMenuAktif(req, res) {
  try {
    const { kode } = req.params;
    const { is_aktif } = req.body;

    const menu = await pool.query('SELECT nama, is_sistem FROM menu_items WHERE kode = $1', [kode]);
    if (menu.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Menu tidak ditemukan.' });
    }
    if (menu.rows[0].is_sistem) {
      return res.status(409).json({
        success: false,
        message: `${menu.rows[0].nama} adalah menu sistem dan tidak bisa dinonaktifkan.`,
      });
    }

    const r = await pool.query(
      'UPDATE menu_items SET is_aktif = $1 WHERE kode = $2 RETURNING *',
      [is_aktif === true, kode]
    );
    await logActivity(req, 'AKSES', `Menu ${r.rows[0].nama} ${is_aktif ? 'diaktifkan' : 'dinonaktifkan'}`);
    return res.status(200).json({
      success: true,
      message: `Menu ${r.rows[0].nama} ${is_aktif ? 'diaktifkan' : 'dinonaktifkan'}.`,
      data: r.rows[0],
    });
  } catch (err) {
    console.error('ToggleMenuAktif Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getMenuAkses, getMenuAksesSaya, updateMenuAkses, resetMenuAkses, toggleMenuAktif, AKSI };
