/**
 * Alur kendali darurat: keterangan wajib, idempotensi, dan otorisasi OFF.
 *
 * ===================================================================
 * Kenapa MQTT dipalsukan, dan kenapa itu bukan kecurangan
 * ===================================================================
 *
 * `nyalakanDarurat`/`matikanDarurat` menerbitkan perintah ke broker sungguhan.
 * Menjalankan uji ini apa adanya akan MEMBUNYIKAN SIRENE DI RUMAH ORANG,
 * berkali-kali, setiap kali seseorang menjalankan `node test-*.js`.
 *
 * Jadi hanya penerbitannya yang diganti — `terbitkanPerintahAlarm` diganti
 * dengan pencatat panggilan. Seluruh sisanya berjalan sungguhan: transaksi,
 * `pg_advisory_xact_lock`, validasi, otorisasi, dan tulisan ke database. Yang
 * hilang dari cakupan hanyalah "apakah broker menerima perintahnya", dan itu
 * memang bukan yang diuji berkas ini.
 *
 * Penggantiannya dilakukan SEBELUM controller di-`require`, karena controller
 * memegang referensi ke modul mqtt saat dimuat.
 */
require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-emergency-keterangan');

const assert = require('assert');
const { spawnSync } = require('child_process');
const { pool } = require('./src/config/database');
const { PENANDA_LEGACY, WAJIBKAN_KETERANGAN_DARURAT } = require('./src/config/kompatibilitas');

// --- palsukan broker sebelum controller dimuat ------------------------
const mqttAlarm = require('./src/config/mqtt');

const perintahTerkirim = [];
let mqttGagal = false;

mqttAlarm.terbitkanPerintahAlarm = async (perintah) => {
  if (mqttGagal) throw new Error('broker tidak tersambung (disimulasikan)');
  perintahTerkirim.push(perintah);
};
mqttAlarm.terkonfigurasi = () => true;
mqttAlarm.tersambung = () => true;
mqttAlarm.pernahTersambung = () => true;

const {
  kendaliAlarm,
  statusAlarm,
  getAlerts,
} = require('./src/controllers/emergency.controller');

// PIN dipaksa ke nilai yang diketahui uji ini; nilai aslinya tidak dibaca.
process.env.EMERGENCY_PIN = '246810';
const PIN = '246810';
const PIN_SALAH = '999999';

function mockReqRes({ body = {}, query = {}, user = null } = {}) {
  let statusCode = 200;
  let responseBody = null;
  return {
    req: {
      body, query, params: {}, user,
      headers: {}, ip: '127.0.0.1', socket: { remoteAddress: '127.0.0.1' },
    },
    res: {
      status(c) { statusCode = c; return this; },
      json(d) { responseBody = d; return this; },
      getStatusCode() { return statusCode; },
      getBody() { return responseBody; },
    },
  };
}

async function panggil(fn, opsi) {
  const { req, res } = mockReqRes(opsi);
  await fn(req, res);
  return { kode: res.getStatusCode(), body: res.getBody() };
}

let warga = null;
let wargaLain = null;
let pengurus = null;
const idKejadian = new Set();

async function buatUser(peran, nama) {
  const r = await pool.query(
    `INSERT INTO users (email, role, nama, password_hash)
     VALUES ($1, $2, $3, 'hash') RETURNING id, nama, role`,
    [`uji_darurat_${Date.now()}_${Math.random().toString(36).slice(2, 8)}@test.local`, peran, nama]
  );
  return r.rows[0];
}

/** Menghapus kejadian aktif yang tersisa supaya tiap skenario mulai bersih. */
async function bersihkanKejadianAktif() {
  const r = await pool.query("SELECT id FROM emergency_alerts WHERE status = 'active'");
  r.rows.forEach((x) => idKejadian.add(x.id));
  await pool.query("DELETE FROM emergency_alerts WHERE status = 'active'");
}

/**
 * TAHAP 2, dijalankan sebagai proses ANAK dengan
 * `WAJIBKAN_KETERANGAN_DARURAT=true`.
 *
 * Harus proses terpisah: saklarnya dibaca sekali saat modul dimuat — sama
 * seperti `IZINKAN_TOKEN_QUERY` — jadi mengubah `process.env` di tengah jalan
 * tidak berpengaruh. Menjalankannya lewat variabel lingkungan pada proses baru
 * juga berarti yang diuji adalah cara ia akan benar-benar dipasang nanti,
 * bukan tiruannya.
 *
 * Inilah gladi resik pencabutan: kalau bagian ini lulus, Tahap 2 tinggal
 * menyetel variabelnya di Railway — tanpa satu baris kode pun berubah.
 */
async function jalankanFase2() {
  console.log('\n--- TAHAP 2 (WAJIBKAN_KETERANGAN_DARURAT=true) ---');
  assert.strictEqual(WAJIBKAN_KETERANGAN_DARURAT, true,
    'anak harus berjalan dengan saklar menyala');

  const u = await buatUser('warga', 'Warga Fase 2');
  const sbg = { id: u.id, role: 'warga', nama: u.nama };

  try {
    await pool.query("DELETE FROM emergency_alerts WHERE status = 'active'");

    // Klien lama kini DITOLAK — inilah yang membedakan Tahap 2 dari Tahap 1.
    const lama = await panggil(kendaliAlarm, { body: { aksi: 'ON', pin: PIN }, user: sbg });
    assert.strictEqual(lama.kode, 400, `Tahap 2: klien lama harus 400, dapat ${lama.kode}`);

    const sisa = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(sisa.rows[0].n, 0, 'Tahap 2: penolakan tidak boleh membuat kejadian');
    console.log('   Klien lama → 400, tanpa kejadian.');

    // Klien baru tetap jalan.
    const baru = await panggil(kendaliAlarm, {
      body: { aksi: 'ON', pin: PIN, keterangan: 'Banjir setinggi lutut di gang tiga' },
      user: sbg,
    });
    assert.strictEqual(baru.kode, 201, `Tahap 2: klien baru harus 201, dapat ${baru.kode}`);
    assert.strictEqual(baru.body.data.legacy_without_keterangan, false);
    console.log('   Klien baru → 201, tidak ditandai legacy.');

    await pool.query('DELETE FROM emergency_alerts WHERE user_id = $1', [u.id]);
    console.log('--- TAHAP 2 LULUS ---\n');
  } finally {
    await pool.query('DELETE FROM emergency_alerts WHERE user_id = $1 OR dismissed_by = $1', [u.id]);
    await pool.query('DELETE FROM users WHERE id = $1', [u.id]);
    await pool.end();
  }
}

if (process.env.UJI_FASE === '2') {
  jalankanFase2()
    .then(() => process.exit(0))
    .catch((e) => { console.error('TAHAP 2 GAGAL:', e.message); process.exit(1); });
} else {
(async () => {
  console.log('\n================================================================');
  console.log('ALUR KENDALI DARURAT — rollout bertahap keterangan & otorisasi OFF');
  console.log('================================================================\n');

  warga = await buatUser('warga', 'Warga Pelapor');
  wargaLain = await buatUser('warga', 'Warga Lain');
  pengurus = await buatUser('ketua_rt', 'Ketua RT Uji');

  await bersihkanKejadianAktif();

  const sbgWarga = { id: warga.id, role: 'warga', nama: warga.nama };
  const sbgWargaLain = { id: wargaLain.id, role: 'warga', nama: wargaLain.nama };
  const sbgPengurus = { id: pengurus.id, role: 'ketua_rt', nama: pengurus.nama };

  // ------------------------------------------------------------------
  console.log('1. Keterangan yang DIKIRIM tetapi tidak sah tetap ditolak...');
  {
    const tanpa = [
      ['terlalu pendek', { aksi: 'ON', pin: PIN, keterangan: 'api' }],
      ['terlalu panjang', { aksi: 'ON', pin: PIN, keterangan: 'x'.repeat(501) }],
    ];

    // Kelonggaran Tahap 1 HANYA untuk "tidak dikirim sama sekali". Panjang yang
    // melanggar berarti klien BARU mengirim data buruk, dan menerimanya diam-diam
    // akan menyimpan potongan kalimat ke riwayat darurat.
    for (const [nama, body] of tanpa) {
      const r = await panggil(kendaliAlarm, { body, user: sbgWarga });
      assert.strictEqual(r.kode, 400, `${nama}: harus 400, dapat ${r.kode}`);
      assert.strictEqual(r.body.success, false, `${nama}: success harus false`);
      assert.ok(r.body.message && r.body.message.length > 0, `${nama}: pesan galat harus ada`);
      console.log(`   ${nama.padEnd(18)} → 400 "${r.body.message}"`);
    }

    const sisa = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(sisa.rows[0].n, 0, 'penolakan tidak boleh meninggalkan kejadian');
    console.log('   Tidak ada kejadian yang terbuat oleh permintaan yang ditolak.\n');
  }

  // ------------------------------------------------------------------
  console.log('1b. TAHAP 1 — klien lama TANPA keterangan tetap bisa menyalakan alarm...');
  {
    // APK 1.1.0+3 yang beredar mengirim hanya {aksi, pin}. Menolaknya berarti
    // mematikan tombol darurat di setiap ponsel yang belum diperbarui — dan
    // matinya baru ketahuan saat ada yang benar-benar menekannya.
    const legacy = [
      ['field tidak ada', { aksi: 'ON', pin: PIN }],
      ['string kosong', { aksi: 'ON', pin: PIN, keterangan: '' }],
      ['hanya spasi', { aksi: 'ON', pin: PIN, keterangan: '     ' }],
      ['hanya tab/newline', { aksi: 'ON', pin: PIN, keterangan: '\t\n  ' }],
    ];

    for (const [nama, body] of legacy) {
      await bersihkanKejadianAktif();

      const r = await panggil(kendaliAlarm, { body, user: sbgWarga });
      assert.strictEqual(r.kode, 201, `${nama}: klien lama harus tetap diterima, dapat ${r.kode}`);
      assert.strictEqual(r.body.data.legacy_without_keterangan, true,
        `${nama}: harus ditandai legacy_without_keterangan`);

      const id = r.body.data.emergency_id;
      idKejadian.add(id);

      const baris = await pool.query('SELECT message FROM emergency_alerts WHERE id = $1', [id]);
      assert.strictEqual(baris.rows[0].message, PENANDA_LEGACY,
        `${nama}: harus memakai penanda legacy, bukan kalimat karangan`);

      assert.ok(perintahTerkirim.includes('ON'), `${nama}: sirene harus tetap dibunyikan`);
      console.log(`   ${nama.padEnd(18)} → 201, ditandai "${PENANDA_LEGACY}"`);
    }

    // Penandanya TIDAK boleh menyerupai kalimat manusia: riwayat darurat yang
    // dipalsukan lebih buruk daripada riwayat yang mengaku kosong.
    assert.ok(!/dinyalakan dari dasbor/i.test(PENANDA_LEGACY),
      'penanda legacy tidak boleh menyamar sebagai keterangan pengguna');

    await bersihkanKejadianAktif();
    console.log('   Alarm klien lama tidak putus, dan jejaknya jujur.\n');
  }

  // ------------------------------------------------------------------
  console.log('2. ON dengan keterangan sah membuat SATU kejadian...');
  let idAktif = null;
  const KETERANGAN = 'Kebakaran di dapur rumah nomor 12, api belum padam';
  {
    const r = await panggil(kendaliAlarm, {
      body: { aksi: 'ON', pin: PIN, keterangan: KETERANGAN },
      user: sbgWarga,
    });

    assert.strictEqual(r.kode, 201, `harus 201, dapat ${r.kode}`);
    assert.strictEqual(r.body.data.kejadian_baru, true);
    assert.strictEqual(r.body.data.keterangan, KETERANGAN, 'keterangan harus dikembalikan apa adanya');

    idAktif = r.body.data.emergency_id;
    idKejadian.add(idAktif);

    const baris = await pool.query('SELECT user_id, message, status FROM emergency_alerts WHERE id = $1', [idAktif]);
    assert.strictEqual(baris.rows[0].message, KETERANGAN, 'keterangan harus tersimpan di kolom message');
    assert.strictEqual(baris.rows[0].user_id, warga.id, 'pelapor harus warga yang menekan');
    assert.strictEqual(baris.rows[0].status, 'active');

    assert.ok(perintahTerkirim.includes('ON'), 'perintah ON harus diterbitkan ke broker');
    console.log(`   Kejadian ${idAktif} dibuat, keterangan tersimpan utuh.\n`);
  }

  // ------------------------------------------------------------------
  console.log('3. Keterangan muncul di riwayat & status...');
  {
    const rw = await panggil(getAlerts, { query: {}, user: sbgPengurus });
    const baris = rw.body.data.find((x) => x.id === idAktif);
    assert.ok(baris, 'kejadian harus ada di riwayat');
    assert.strictEqual(baris.message, KETERANGAN, 'riwayat harus memuat keterangan');
    assert.strictEqual(baris.nama_warga, warga.nama, 'riwayat harus menyebut pelapor');

    const st = await panggil(statusAlarm, { user: sbgPengurus });
    assert.strictEqual(st.body.data.alarm_aktif, true);
    assert.strictEqual(st.body.data.kejadian_aktif.message, KETERANGAN);
    assert.strictEqual(st.body.data.kejadian_aktif.nama_pengaktif, warga.nama);
    console.log('   Riwayat dan /alarm/status keduanya memuat keterangan + pelapor.\n');
  }

  // ------------------------------------------------------------------
  console.log('4. Pemilik boleh menutup kejadiannya sendiri (dan lihat izinnya)...');
  {
    const st = await panggil(statusAlarm, { user: sbgWarga });
    assert.strictEqual(st.body.data.kejadian_aktif.milik_saya, true);
    assert.strictEqual(st.body.data.kejadian_aktif.boleh_matikan, true, 'pemilik harus boleh mematikan');
    console.log('   Pemilik: milik_saya=true, boleh_matikan=true.\n');
  }

  // ------------------------------------------------------------------
  console.log('5. Warga lain TIDAK melihat izin mematikan...');
  {
    const st = await panggil(statusAlarm, { user: sbgWargaLain });
    assert.strictEqual(st.body.data.alarm_aktif, true, 'kejadian tetap terlihat');
    assert.strictEqual(st.body.data.kejadian_aktif.milik_saya, false);
    assert.strictEqual(st.body.data.kejadian_aktif.boleh_matikan, false, 'warga lain tidak boleh mematikan');
    // Menyembunyikan aksi BUKAN menyembunyikan kejadiannya.
    assert.strictEqual(st.body.data.kejadian_aktif.nama_pengaktif, warga.nama,
      'warga lain tetap harus melihat siapa pelapornya');
    assert.strictEqual(st.body.data.kejadian_aktif.message, KETERANGAN,
      'warga lain tetap harus melihat keterangannya');
    console.log('   Warga lain: boleh_matikan=false, tetapi pelapor & keterangan tetap terlihat.\n');
  }

  // ------------------------------------------------------------------
  console.log('6. Warga lain memanggil OFF langsung → 403 dan kejadian TETAP aktif...');
  {
    const r = await panggil(kendaliAlarm, {
      body: { aksi: 'OFF', pin: PIN },
      user: sbgWargaLain,
    });

    assert.strictEqual(r.kode, 403, `harus 403, dapat ${r.kode}`);
    assert.strictEqual(r.body.success, false);

    const baris = await pool.query('SELECT status, dismissed_by FROM emergency_alerts WHERE id = $1', [idAktif]);
    assert.strictEqual(baris.rows[0].status, 'active', 'kejadian TIDAK boleh ikut tertutup');
    assert.strictEqual(baris.rows[0].dismissed_by, null);
    console.log('   403, status tetap active, dismissed_by tetap kosong.\n');
  }

  // ------------------------------------------------------------------
  console.log('7. ON ulang tidak membuat kejadian kedua & keterangan asli bertahan...');
  {
    const sebelum = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");

    const r = await panggil(kendaliAlarm, {
      body: { aksi: 'ON', pin: PIN, keterangan: 'KETERANGAN BARU yang tidak boleh menimpa' },
      user: sbgWargaLain,
    });

    assert.strictEqual(r.kode, 200, `ON idempoten harus 200, dapat ${r.kode}`);
    assert.strictEqual(r.body.data.kejadian_baru, false);
    assert.strictEqual(r.body.data.emergency_id, idAktif, 'harus menunjuk kejadian yang sama');
    assert.strictEqual(r.body.data.keterangan, KETERANGAN,
      'respons harus mengembalikan keterangan ASLI, bukan yang barusan dikirim');

    const sesudah = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(sesudah.rows[0].n, sebelum.rows[0].n, 'jumlah kejadian aktif tidak boleh bertambah');

    const baris = await pool.query('SELECT user_id, message FROM emergency_alerts WHERE id = $1', [idAktif]);
    assert.strictEqual(baris.rows[0].message, KETERANGAN, 'keterangan asli TIDAK boleh tertimpa');
    assert.strictEqual(baris.rows[0].user_id, warga.id, 'pelapor asli tidak boleh berubah');
    console.log('   Tetap 1 kejadian; keterangan & pelapor asli utuh.\n');
  }

  // ------------------------------------------------------------------
  console.log('8. Tiga ON bersamaan tetap menghasilkan satu kejadian...');
  {
    await bersihkanKejadianAktif();

    const hasil = await Promise.all([1, 2, 3].map((i) =>
      panggil(kendaliAlarm, {
        body: { aksi: 'ON', pin: PIN, keterangan: `Serentak nomor ${i} — uji konkurensi` },
        user: sbgWarga,
      })
    ));

    const aktif = await pool.query("SELECT id FROM emergency_alerts WHERE status='active'");
    aktif.rows.forEach((x) => idKejadian.add(x.id));

    assert.strictEqual(aktif.rows.length, 1,
      `tiga ON bersamaan menghasilkan ${aktif.rows.length} kejadian, seharusnya 1`);

    const idUnik = new Set(hasil.map((h) => h.body.data.emergency_id));
    assert.strictEqual(idUnik.size, 1, 'ketiganya harus menunjuk emergency_id yang sama');
    assert.strictEqual(hasil.filter((h) => h.body.data.kejadian_baru).length, 1,
      'tepat satu permintaan yang boleh mengaku membuat kejadian');

    idAktif = aktif.rows[0].id;
    console.log(`   3 permintaan → 1 kejadian (${idAktif}), 1 pembuat.\n`);
  }

  // ------------------------------------------------------------------
  console.log('9. Pengurus menutup kejadian milik warga — baris yang SAMA...');
  {
    const sebelum = await pool.query('SELECT COUNT(*)::int AS n FROM emergency_alerts');

    const r = await panggil(kendaliAlarm, {
      body: { aksi: 'OFF', pin: PIN },
      user: sbgPengurus,
    });

    assert.strictEqual(r.kode, 200, `harus 200, dapat ${r.kode}`);
    assert.strictEqual(r.body.data.kejadian_ditutup, true);
    assert.strictEqual(r.body.data.emergency_id, idAktif, 'harus menutup kejadian yang sama');

    const sesudah = await pool.query('SELECT COUNT(*)::int AS n FROM emergency_alerts');
    assert.strictEqual(sesudah.rows[0].n, sebelum.rows[0].n,
      'OFF tidak boleh membuat baris riwayat baru');

    const baris = await pool.query(
      'SELECT user_id, dismissed_by, status, message, dismissed_at FROM emergency_alerts WHERE id = $1',
      [idAktif]
    );
    const b = baris.rows[0];
    assert.strictEqual(b.status, 'dismissed');
    assert.strictEqual(b.user_id, warga.id, 'pelapor harus tetap warga');
    assert.strictEqual(b.dismissed_by, pengurus.id, 'penyelesai harus pengurus');
    assert.notStrictEqual(b.user_id, b.dismissed_by, 'pelapor dan penyelesai harus berbeda orang');
    assert.ok(b.dismissed_at, 'dismissed_at harus terisi');
    assert.ok(b.message && b.message.includes('uji konkurensi'), 'keterangan harus bertahan setelah ditutup');
    console.log('   Satu baris ON→OFF; pelapor ≠ penyelesai; keterangan bertahan.\n');
  }

  // ------------------------------------------------------------------
  console.log('10. Membaca ulang riwayat mempertahankan detail & otorisasi...');
  {
    const rw = await panggil(getAlerts, { query: {}, user: sbgWargaLain });
    const baris = rw.body.data.find((x) => x.id === idAktif);

    assert.ok(baris, 'kejadian yang sudah ditutup tetap ada di riwayat');
    assert.strictEqual(baris.status, 'dismissed');
    assert.ok(baris.message.includes('uji konkurensi'), 'keterangan tetap ada setelah dimuat ulang');
    assert.strictEqual(baris.nama_warga, warga.nama, 'pelapor tetap warga');
    assert.strictEqual(baris.dismissed_by_nama, pengurus.nama, 'penyelesai tetap pengurus');

    const st = await panggil(statusAlarm, { user: sbgWargaLain });
    assert.strictEqual(st.body.data.alarm_aktif, false, 'tidak ada lagi kejadian aktif');
    assert.strictEqual(st.body.data.kejadian_aktif, null);
    console.log('   Detail & peran bertahan setelah dimuat ulang.\n');
  }

  // ------------------------------------------------------------------
  console.log('11. PIN salah, OFF tanpa kejadian, dan kegagalan broker...');
  {
    // PIN salah → 403, tidak ada kejadian.
    const salah = await panggil(kendaliAlarm, {
      body: { aksi: 'ON', pin: PIN_SALAH, keterangan: 'Keterangan yang sah sekali pun' },
      user: sbgWarga,
    });
    assert.strictEqual(salah.kode, 403, 'PIN salah harus 403');
    const adaAktif = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(adaAktif.rows[0].n, 0, 'PIN salah tidak boleh membuat kejadian');
    console.log('   PIN salah → 403, tanpa kejadian.');

    // OFF tanpa kejadian aktif → 200, perintah tetap dikirim, tanpa riwayat baru.
    const jumlahSebelum = await pool.query('SELECT COUNT(*)::int AS n FROM emergency_alerts');
    const off = await panggil(kendaliAlarm, { body: { aksi: 'OFF', pin: PIN }, user: sbgWarga });
    assert.strictEqual(off.kode, 200, 'OFF tanpa kejadian tetap 200');
    assert.strictEqual(off.body.data.kejadian_ditutup, false);
    const jumlahSesudah = await pool.query('SELECT COUNT(*)::int AS n FROM emergency_alerts');
    assert.strictEqual(jumlahSesudah.rows[0].n, jumlahSebelum.rows[0].n,
      'OFF tanpa kejadian tidak boleh membuat riwayat');
    console.log('   OFF tanpa kejadian → 200, tanpa riwayat baru.');

    // Broker gagal → kejadian TIDAK tercatat (transaksi di-ROLLBACK).
    mqttGagal = true;
    const gagal = await panggil(kendaliAlarm, {
      body: { aksi: 'ON', pin: PIN, keterangan: 'Sirene ini tidak akan pernah berbunyi' },
      user: sbgWarga,
    });
    mqttGagal = false;

    assert.ok(gagal.kode >= 500, `kegagalan broker harus >=500, dapat ${gagal.kode}`);
    const setelahGagal = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(setelahGagal.rows[0].n, 0,
      'kejadian tidak boleh tercatat untuk sirene yang gagal berbunyi');
    console.log('   Broker gagal → tidak ada kejadian yang tercatat.\n');
  }

  // ------------------------------------------------------------------
  console.log('12. Riwayat membedakan keterangan asli dari penanda legacy...');
  {
    await bersihkanKejadianAktif();

    // Satu kejadian klien lama, satu kejadian klien baru — dibandingkan
    // berdampingan di riwayat yang sama.
    const lama = await panggil(kendaliAlarm, { body: { aksi: 'ON', pin: PIN }, user: sbgWarga });
    idKejadian.add(lama.body.data.emergency_id);
    await panggil(kendaliAlarm, { body: { aksi: 'OFF', pin: PIN }, user: sbgPengurus });

    const KET_BARU = 'Maling masuk lewat jendela belakang rumah nomor 7';
    const baru = await panggil(kendaliAlarm, {
      body: { aksi: 'ON', pin: PIN, keterangan: KET_BARU },
      user: sbgWarga,
    });
    idKejadian.add(baru.body.data.emergency_id);

    const rw = await panggil(getAlerts, { query: {}, user: sbgPengurus });
    const barisLama = rw.body.data.find((x) => x.id === lama.body.data.emergency_id);
    const barisBaru = rw.body.data.find((x) => x.id === baru.body.data.emergency_id);

    assert.strictEqual(barisLama.message, PENANDA_LEGACY,
      'kejadian klien lama harus tetap bertanda legacy di riwayat');
    assert.strictEqual(barisBaru.message, KET_BARU,
      'kejadian klien baru harus menampilkan keterangan aslinya');
    assert.notStrictEqual(barisBaru.message, PENANDA_LEGACY);

    console.log(`   Lama → "${PENANDA_LEGACY}"`);
    console.log(`   Baru → "${KET_BARU}"\n`);

    await panggil(kendaliAlarm, { body: { aksi: 'OFF', pin: PIN }, user: sbgPengurus });
  }

  console.log('================================================================');
  console.log('SELURUH SKENARIO ALUR KENDALI DARURAT LULUS (Tahap 1).');
  console.log('================================================================');
})()
  .then(async () => {
    await bersihkan();

    // Gladi resik Tahap 2 dijalankan SETELAH fixture Tahap 1 dibersihkan,
    // supaya keduanya tidak berebut baris kejadian aktif yang sama.
    const anak = spawnSync(process.execPath, [process.argv[1]], {
      stdio: 'inherit',
      env: { ...process.env, UJI_FASE: '2', WAJIBKAN_KETERANGAN_DARURAT: 'true' },
    });
    process.exit(anak.status === 0 ? 0 : 1);
  })
  .catch(async (e) => {
    console.error('\nPENGUJIAN GAGAL:', e.message);
    await bersihkan();
    process.exit(1);
  });
}

async function bersihkan() {
  try {
    console.log('Membersihkan fixture pengujian...');
    const r = await pool.query("SELECT id FROM emergency_alerts WHERE status = 'active'");
    r.rows.forEach((x) => idKejadian.add(x.id));

    for (const id of idKejadian) {
      await pool.query('DELETE FROM emergency_alerts WHERE id = $1', [id]);
    }
    for (const u of [warga, wargaLain, pengurus]) {
      if (u) {
        await pool.query('DELETE FROM emergency_alerts WHERE user_id = $1 OR dismissed_by = $1', [u.id]);
        await pool.query('DELETE FROM users WHERE id = $1', [u.id]);
      }
    }
    console.log('Fixture pengujian berhasil dibersihkan.');
  } catch (e) {
    console.error('Gagal membersihkan fixture:', e.message);
  } finally {
    await pool.end();
  }
}
