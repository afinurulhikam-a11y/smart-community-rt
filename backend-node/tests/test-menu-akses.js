/**
 * Menu & Akses — matriks otorisasi dan penegakannya.
 *
 * ===================================================================
 * Yang diuji, dan kenapa justru ini
 * ===================================================================
 *
 * Layar Menu & Akses menampilkan ratusan saklar. Yang menentukan apakah layar
 * itu jujur bukan tampilannya, melainkan apakah setiap saklar benar-benar
 * mengubah jawaban `requirePermission`. Karena itu berkas ini memanggil
 * middleware-nya SUNGGUHAN terhadap baris database sungguhan, bukan meniru
 * hasilnya.
 *
 * Tiga penjagaan yang paling penting diuji dari sisi yang merugikan:
 *
 *   - Administrator tidak boleh bisa mengunci dirinya sendiri.
 *   - Menu sistem tidak boleh bisa diberikan ke peran lain.
 *   - Menu yang dinonaktifkan harus menutup ENDPOINT-nya, bukan sekadar
 *     menyembunyikan entri sidebar. Menyembunyikan menu bukan lapis keamanan;
 *     ia hanya kenyamanan.
 *
 * ===================================================================
 * Data asli dipulihkan
 * ===================================================================
 *
 * Uji ini menulis ke `role_permissions` dan `menu_items` yang sesungguhnya —
 * tidak ada tabel bayangan. Karena itu seluruh isinya difoto lebih dulu dan
 * dikembalikan persis di akhir, termasuk bila ada assert yang gagal di tengah.
 */
require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-menu-akses');

const assert = require('assert');
const { pool } = require('../src/config/database');
const { MENU_ITEMS, DEFAULT_PERMISSIONS, ROLES } = require('../src/config/permissions');
const { requirePermission } = require('../src/middleware/auth.middleware');
const {
  updateMenuAkses,
  toggleMenuAktif,
  getMenuAksesSaya,
} = require('../src/controllers/menu_akses.controller');

function mockReqRes({ body = {}, params = {}, user = null } = {}) {
  let kode = 200;
  let isi = null;
  return {
    req: { body, params, query: {}, user, headers: {}, ip: '127.0.0.1', socket: { remoteAddress: '127.0.0.1' } },
    res: {
      status(c) { kode = c; return this; },
      json(d) { isi = d; return this; },
      getStatusCode() { return kode; },
      getBody() { return isi; },
    },
  };
}

/** Menjalankan middleware `requirePermission` dan melaporkan hasilnya. */
async function cobaIzin(menuKode, aksi, role) {
  const mw = requirePermission(menuKode, aksi);
  const { req, res } = mockReqRes({ user: { id: '00000000-0000-0000-0000-000000000001', role } });
  let lolos = false;
  await mw(req, res, () => { lolos = true; });
  return { lolos, kode: res.getStatusCode(), pesan: res.getBody()?.message };
}

async function panggil(fn, opsi) {
  const { req, res } = mockReqRes(opsi);
  await fn(req, res);
  return { kode: res.getStatusCode(), body: res.getBody() };
}

let fotoIzin = null;
let fotoMenu = null;
const ADMIN = { id: '00000000-0000-0000-0000-0000000000ad', role: 'admin', nama: 'Admin Uji' };

(async () => {
  console.log('\n================================================================');
  console.log('MENU & AKSES — matriks otorisasi & penegakan');
  console.log('================================================================\n');

  fotoIzin = (await pool.query('SELECT role, menu_kode, can_view, can_create, can_update, can_delete FROM role_permissions')).rows;
  fotoMenu = (await pool.query('SELECT kode, is_aktif FROM menu_items')).rows;
  console.log(`Foto data asli diambil: ${fotoIzin.length} baris izin, ${fotoMenu.length} menu.\n`);

  // ------------------------------------------------------------------
  console.log('1. Registry & database sepakat, dan "dashboard" sudah tiada...');
  {
    const db = (await pool.query('SELECT kode FROM menu_items')).rows.map((r) => r.kode);
    const reg = MENU_ITEMS.map((m) => m.kode);

    assert.strictEqual(reg.length, 18, `registry harus 18 menu, dapat ${reg.length}`);
    assert.ok(!reg.includes('dashboard'), 'registry masih memuat "dashboard"');
    assert.ok(!db.includes('dashboard'), 'database masih memuat "dashboard" — migrasi v31 belum dijalankan');

    const hantu = db.filter((k) => !reg.includes(k));
    const hilang = reg.filter((k) => !db.includes(k));
    assert.deepStrictEqual(hantu, [], `menu hantu di DB: ${hantu.join(', ')}`);
    assert.deepStrictEqual(hilang, [], `menu registry belum terseed: ${hilang.join(', ')}`);

    const izinDashboard = await pool.query("SELECT COUNT(*)::int n FROM role_permissions WHERE menu_kode='dashboard'");
    assert.strictEqual(izinDashboard.rows[0].n, 0, 'masih ada baris izin untuk dashboard');

    // Tiap peran di DEFAULT_PERMISSIONS harus menutup seluruh menu — kalau
    // ada yang tertinggal, `reset` akan menghasilkan matriks berlubang.
    for (const r of ROLES) {
      const k = Object.keys(DEFAULT_PERMISSIONS[r]);
      assert.strictEqual(k.length, 18, `${r} punya ${k.length} entri default, harus 18`);
    }

    console.log(`   18 menu, registry = DB, nol sisa dashboard.\n`);
  }

  // ------------------------------------------------------------------
  console.log('2. Administrator selalu lolos, bahkan tanpa baris izin...');
  {
    // Semua izin admin dihapus dari tabel — admin TETAP harus lolos, karena
    // middleware mengembalikan next() sebelum menyentuh tabel sama sekali.
    await pool.query("DELETE FROM role_permissions WHERE role = 'admin'");

    for (const kode of ['kependudukan.warga', 'keuangan.iuran', 'pengaturan.akses']) {
      for (const aksi of ['view', 'create', 'update', 'delete']) {
        const h = await cobaIzin(kode, aksi, 'admin');
        assert.ok(h.lolos, `admin ditolak pada ${kode}:${aksi} (${h.kode})`);
      }
    }
    console.log('   3 menu x 4 aksi tanpa satu pun baris izin admin → semua lolos.\n');
  }

  // ------------------------------------------------------------------
  console.log('3. Menu sistem tertutup untuk SEMUA peran selain admin...');
  {
    // Bahkan bila baris izinnya dipaksa menyala langsung di database.
    for (const role of ROLES.filter((r) => r !== 'admin')) {
      await pool.query(
        `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
         VALUES ($1, 'pengaturan.akses', true, true, true, true)
         ON CONFLICT (role, menu_kode) DO UPDATE SET can_view = true, can_create = true,
           can_update = true, can_delete = true`,
        [role]
      );
      const h = await cobaIzin('pengaturan.akses', 'view', role);
      assert.ok(!h.lolos, `${role} lolos ke menu sistem`);
      assert.strictEqual(h.kode, 403);
    }
    console.log('   Izin dipaksa true di DB pun tetap 403 untuk 4 peran.\n');
  }

  // ------------------------------------------------------------------
  console.log('4. Menu nonaktif menutup ENDPOINT, bukan sekadar sidebar...');
  {
    const KODE = 'kependudukan.bansos';
    await pool.query(
      `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
       VALUES ('ketua_rt', $1, true, true, true, true)
       ON CONFLICT (role, menu_kode) DO UPDATE SET can_view = true, can_create = true,
         can_update = true, can_delete = true`,
      [KODE]
    );

    const sebelum = await cobaIzin(KODE, 'view', 'ketua_rt');
    assert.ok(sebelum.lolos, 'prasyarat: dengan izin view harus lolos');

    // Dimatikan lewat endpoint yang sama dengan yang dipakai layar.
    const t = await panggil(toggleMenuAktif, { params: { kode: KODE }, body: { is_aktif: false }, user: ADMIN });
    assert.strictEqual(t.kode, 200);

    const sesudah = await cobaIzin(KODE, 'view', 'ketua_rt');
    assert.ok(!sesudah.lolos, 'menu nonaktif harus menutup endpoint walau izin view menyala');
    assert.strictEqual(sesudah.kode, 403);
    assert.ok(/dinonaktifkan/i.test(sesudah.pesan), `pesan harus menyebut sebabnya: "${sesudah.pesan}"`);

    // Menu nonaktif juga hilang dari izin yang dikirim ke klien.
    const saya = await panggil(getMenuAksesSaya, { user: { id: ADMIN.id, role: 'ketua_rt' } });
    const daftar = (saya.body.data.menus || []).map((m) => m.kode);
    assert.ok(!daftar.includes(KODE), 'menu nonaktif tidak boleh ikut terkirim ke klien');

    await panggil(toggleMenuAktif, { params: { kode: KODE }, body: { is_aktif: true }, user: ADMIN });
    const pulih = await cobaIzin(KODE, 'view', 'ketua_rt');
    assert.ok(pulih.lolos, 'dihidupkan kembali harus lolos lagi');

    console.log('   Nonaktif → 403 + hilang dari /me; dihidupkan → lolos lagi.\n');
  }

  // ------------------------------------------------------------------
  console.log('5. Menu sistem tidak bisa dinonaktifkan...');
  {
    const t = await panggil(toggleMenuAktif, {
      params: { kode: 'pengaturan.akses' }, body: { is_aktif: false }, user: ADMIN,
    });
    assert.strictEqual(t.kode, 409, `harus 409, dapat ${t.kode}`);

    const m = await pool.query("SELECT is_aktif FROM menu_items WHERE kode='pengaturan.akses'");
    assert.strictEqual(m.rows[0].is_aktif, true, 'menu sistem tidak boleh ikut berubah');
    console.log('   409, dan barisnya tidak berubah.\n');
  }

  // ------------------------------------------------------------------
  console.log('6. updateMenuAkses menolak yang bisa mengunci administrator...');
  {
    const a = await panggil(updateMenuAkses, {
      body: { perubahan: [{ role: 'admin', menu_kode: 'kependudukan.warga', can_view: false }] },
      user: ADMIN,
    });
    assert.strictEqual(a.kode, 409, `mengubah izin admin harus 409, dapat ${a.kode}`);

    const b = await panggil(updateMenuAkses, {
      body: { perubahan: [{ role: 'ketua_rt', menu_kode: 'pengaturan.akses', can_view: true }] },
      user: ADMIN,
    });
    assert.strictEqual(b.kode, 409, `memberi menu sistem harus 409, dapat ${b.kode}`);

    const c = await panggil(updateMenuAkses, {
      body: { perubahan: [{ role: 'satpam', menu_kode: 'kependudukan.warga', can_view: true }] },
      user: ADMIN,
    });
    assert.strictEqual(c.kode, 400, `role tak dikenal harus 400, dapat ${c.kode}`);

    const d = await panggil(updateMenuAkses, { body: { perubahan: [] }, user: ADMIN });
    assert.strictEqual(d.kode, 400, 'perubahan kosong harus 400');

    console.log('   admin 409 · menu sistem 409 · role asing 400 · kosong 400.\n');
  }

  // ------------------------------------------------------------------
  console.log('7. Menyimpan izin benar-benar tersimpan dan berlaku...');
  {
    const KODE = 'inventaris.barang';

    const r = await panggil(updateMenuAkses, {
      body: {
        perubahan: [{
          role: 'sekretaris', menu_kode: KODE,
          can_view: true, can_create: false, can_update: true, can_delete: false,
        }],
      },
      user: ADMIN,
    });
    assert.strictEqual(r.kode, 200, `harus 200, dapat ${r.kode}`);

    // Dibaca ULANG dari database, bukan dari jawaban endpoint.
    const baris = await pool.query(
      'SELECT can_view, can_create, can_update, can_delete FROM role_permissions WHERE role=$1 AND menu_kode=$2',
      ['sekretaris', KODE]
    );
    assert.deepStrictEqual(
      baris.rows[0],
      { can_view: true, can_create: false, can_update: true, can_delete: false },
      'baris tersimpan tidak sama dengan yang dikirim'
    );

    // Dan tiap kolom benar-benar mengubah jawaban middleware.
    assert.ok((await cobaIzin(KODE, 'view', 'sekretaris')).lolos, 'view harus lolos');
    assert.ok((await cobaIzin(KODE, 'update', 'sekretaris')).lolos, 'update harus lolos');

    const tambah = await cobaIzin(KODE, 'create', 'sekretaris');
    assert.ok(!tambah.lolos && tambah.kode === 403, 'create harus 403');
    const hapus = await cobaIzin(KODE, 'delete', 'sekretaris');
    assert.ok(!hapus.lolos && hapus.kode === 403, 'delete harus 403');

    console.log('   Tersimpan apa adanya; view/update lolos, create/delete 403.\n');
  }

  // ------------------------------------------------------------------
  console.log('8. Tanpa baris izin sama sekali → tertutup (gagal tertutup)...');
  {
    await pool.query("DELETE FROM role_permissions WHERE role='warga' AND menu_kode='keuangan.bop'");
    const h = await cobaIzin('keuangan.bop', 'view', 'warga');
    assert.ok(!h.lolos, 'tanpa baris izin harus ditolak, bukan diizinkan');
    assert.strictEqual(h.kode, 403);
    console.log('   Peran tanpa baris izin ditolak 403.\n');
  }

  // ------------------------------------------------------------------
  console.log('9. Kode menu yang tidak terdaftar ditolak, bukan dibiarkan...');
  {
    const h = await cobaIzin('modul.tidak.ada', 'view', 'ketua_rt');
    assert.ok(!h.lolos, 'menu tak dikenal harus ditolak');
    assert.strictEqual(h.kode, 403);
    console.log('   Salah tulis kode rute → 403, bukan lolos diam-diam.\n');
  }

  // ------------------------------------------------------------------
  console.log('10. Matriks bawaan per peran cocok dengan penegakannya...');
  {
    // Kembalikan seluruh izin ke bawaan, lalu buktikan bahwa apa yang
    // dijanjikan DEFAULT_PERMISSIONS memang yang ditegakkan middleware.
    for (const role of ROLES) {
      for (const [kode, izin] of Object.entries(DEFAULT_PERMISSIONS[role])) {
        await pool.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1,$2,$3,$4,$5,$6)
           ON CONFLICT (role, menu_kode) DO UPDATE SET can_view=$3, can_create=$4, can_update=$5, can_delete=$6`,
          [role, kode, izin.view, izin.create, izin.update, izin.delete]
        );
      }
    }

    const sistem = new Set(MENU_ITEMS.filter((m) => m.is_sistem).map((m) => m.kode));
    let diperiksa = 0;

    for (const role of ROLES.filter((r) => r !== 'admin')) {
      for (const m of MENU_ITEMS) {
        if (sistem.has(m.kode)) continue;
        const harap = DEFAULT_PERMISSIONS[role][m.kode];
        for (const aksi of ['view', 'create', 'update', 'delete']) {
          const h = await cobaIzin(m.kode, aksi, role);
          assert.strictEqual(
            h.lolos, harap[aksi],
            `${role} ${m.kode}:${aksi} — bawaan ${harap[aksi]}, middleware ${h.lolos}`
          );
          diperiksa++;
        }
      }
    }
    console.log(`   ${diperiksa} kombinasi peran x menu x aksi cocok seluruhnya.\n`);
  }

  // ------------------------------------------------------------------
  console.log('11. Urutan registry dan penjagaan rute sesuai peta final...');
  {
    const URUTAN_FINAL = [
      'kependudukan.warga', 'kependudukan.kk', 'kependudukan.bansos', 'kependudukan.statistik',
      'keuangan.iuran', 'keuangan.kas', 'keuangan.bop',
      'layanan.visitor', 'layanan.surat',
      'kegiatan.agenda',
      'aspirasi.pengaduan', 'aspirasi.polling', 'aspirasi.darurat',
      'inventaris.barang', 'inventaris.peminjaman',
      'pengaturan.log', 'pengaturan.akses', 'pengaturan.reset',
    ];
    assert.deepStrictEqual(MENU_ITEMS.map((m) => m.kode), URUTAN_FINAL,
      'urutan registry tidak sesuai peta final');

    // `urutan` di database menentukan urutan baris di layar Menu & Akses.
    const dbUrut = (await pool.query('SELECT kode FROM menu_items ORDER BY urutan ASC, id ASC')).rows.map((r) => r.kode);
    assert.deepStrictEqual(dbUrut, URUTAN_FINAL, 'urutan di database belum sesuai — jalankan migrasi v32');

    // Penjagaan rute dibaca dari berkasnya, bukan diasumsikan. Satu kode yang
    // tertinggal di sini berarti sebuah modul dijaga izin yang sudah tidak ada,
    // dan `requirePermission` akan menolak SEMUA orang dengan 403.
    const fs = require('fs');
    const family = fs.readFileSync('src/routes/family.routes.js', 'utf8');
    const announce = fs.readFileSync('src/routes/announcement.routes.js', 'utf8');

    for (const aksi of ['view', 'create', 'update']) {
      assert.ok(family.includes(`requirePermission('kependudukan.kk', '${aksi}')`),
        `family.routes.js belum memakai kependudukan.kk:${aksi}`);
      assert.ok(announce.includes(`requirePermission('kegiatan.agenda', '${aksi}')`),
        `announcement.routes.js belum memakai kegiatan.agenda:${aksi}`);
    }
    assert.ok(!/requirePermission\('kependudukan\.warga'/.test(family),
      'family.routes.js masih menyisakan kependudukan.warga');
    assert.ok(family.includes("roleGuard('admin'), deleteFamily"),
      'DELETE keluarga harus tetap admin-only');

    // Tidak boleh ada kode izin yang sudah dihapus tetapi masih dijaga rute.
    const kodeSah = new Set(MENU_ITEMS.map((m) => m.kode));
    const dir = 'src/routes';
    const tertinggal = [];
    for (const f of fs.readdirSync(dir)) {
      const t = fs.readFileSync(`${dir}/${f}`, 'utf8');
      for (const m of t.matchAll(/requirePermission\('([^']+)'/g)) {
        if (!kodeSah.has(m[1])) tertinggal.push(`${f}: ${m[1]}`);
      }
    }
    assert.deepStrictEqual(tertinggal, [],
      `rute menjaga izin yang tidak ada di registry: ${tertinggal.join(', ')}`);

    console.log('   18 kode berurutan sesuai peta, family→kk, pengumuman→agenda,');
    console.log('   DELETE keluarga tetap admin-only, nol izin yatim di rute.\n');
  }

  console.log('================================================================');
  console.log('SELURUH 11 SKENARIO MENU & AKSES LULUS.');
  console.log('================================================================\n');
})()
  .then(async () => { await pulihkan(); process.exit(0); })
  .catch(async (e) => {
    console.error('\nPENGUJIAN GAGAL:', e.message);
    await pulihkan();
    process.exit(1);
  });

/** Mengembalikan `role_permissions` dan `menu_items.is_aktif` persis semula. */
async function pulihkan() {
  try {
    console.log('Memulihkan data izin ke keadaan semula...');
    if (fotoIzin) {
      await pool.query('DELETE FROM role_permissions');
      for (const r of fotoIzin) {
        await pool.query(
          `INSERT INTO role_permissions (role, menu_kode, can_view, can_create, can_update, can_delete)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [r.role, r.menu_kode, r.can_view, r.can_create, r.can_update, r.can_delete]
        );
      }
    }
    if (fotoMenu) {
      for (const m of fotoMenu) {
        await pool.query('UPDATE menu_items SET is_aktif = $1 WHERE kode = $2', [m.is_aktif, m.kode]);
      }
    }
    const n = await pool.query('SELECT COUNT(*)::int n FROM role_permissions');
    console.log(`Pulih: ${n.rows[0].n} baris izin (semula ${fotoIzin ? fotoIzin.length : '?'}).`);
  } catch (e) {
    console.error('GAGAL MEMULIHKAN DATA:', e.message);
  } finally {
    await pool.end();
  }
}
