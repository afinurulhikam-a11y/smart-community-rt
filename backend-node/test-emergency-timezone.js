/**
 * Regresi: waktu darurat tidak boleh bergeser +7 jam.
 *
 * ===================================================================
 * Bug yang dijaga berkas ini
 * ===================================================================
 *
 * `emergency_alerts.created_at` bertipe `timestamp WITHOUT time zone` dan sejak
 * `DB_TIMEZONE=Asia/Jakarta` selalu berisi jam dinding WIB. node-postgres
 * menyusun objek Date dari jam dinding itu memakai zona proses NODE — bukan
 * zona sesi Postgres — sehingga nilai yang SAMA menghasilkan instant berbeda
 * di dua mesin:
 *
 *   tersimpan            : 2026-08-16 16:45:00
 *   Node TZ=Asia/Jakarta : 2026-08-16T09:45:00.000Z   ← benar
 *   Node TZ=UTC          : 2026-08-16T16:45:00.000Z   ← maju 7 jam
 *
 * Klien memanggil `.toLocal()`, jadi di perangkat WIB nilai kedua tampil
 * sebagai 23:45 untuk kejadian pukul 16:45. Railway menjalankan Node di UTC,
 * mesin pengembangan di Asia/Jakarta — itulah sebabnya bug ini HANYA hidup di
 * produksi sementara pengujian lokal selalu lulus.
 *
 * ===================================================================
 * Kenapa berkas ini menjalankan dirinya sendiri dua kali
 * ===================================================================
 *
 * Zona waktu proses Node dikunci saat proses lahir; `process.env.TZ = ...` di
 * tengah jalan tidak lagi mengubah cara Date disusun. Satu-satunya cara menguji
 * kondisi Railway adalah MENJALANKAN ULANG berkas ini sebagai proses anak
 * dengan TZ=UTC.
 *
 * Menguji di Asia/Jakarta saja tidak ada gunanya: di zona itu kode yang RUSAK
 * pun lulus. Justru anak TZ=UTC-lah yang membuat uji ini bergigi.
 */
require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-emergency-timezone');

const { spawnSync } = require('child_process');
const assert = require('assert');

const ZONA_UJI = ['Asia/Jakarta', 'UTC'];

// ===================================================================
// Induk: jalankan ulang diri sendiri di setiap zona, lalu berhenti.
// ===================================================================
if (!process.env.ZONA_ANAK) {
  console.log('\n================================================================');
  console.log('REGRESI ZONA WAKTU DARURAT — dijalankan di 2 zona proses Node');
  console.log('================================================================\n');

  let gagal = 0;
  for (const tz of ZONA_UJI) {
    console.log(`---------- Node TZ=${tz} ----------`);
    // `process.argv[1]`, bukan `__filename`: keduanya menunjuk berkas yang
    // sama saat dijalankan langsung, dan yang pertama sudah terdaftar sebagai
    // global di eslint.config.js — jadi uji ini lolos lint tanpa menyentuh
    // konfigurasi lint bersama demi satu berkas.
    const anak = spawnSync(process.execPath, [process.argv[1]], {
      stdio: 'inherit',
      env: { ...process.env, TZ: tz, ZONA_ANAK: '1' },
    });
    if (anak.status !== 0) gagal++;
    console.log('');
  }

  if (gagal > 0) {
    console.error(`PENGUJIAN GAGAL di ${gagal} dari ${ZONA_UJI.length} zona.\n`);
    process.exit(1);
  }

  console.log('================================================================');
  console.log(`LULUS DI SELURUH ${ZONA_UJI.length} ZONA — waktu darurat tidak bergeser.`);
  console.log('================================================================\n');
  process.exit(0);
}

// ===================================================================
// Anak: pengujian yang sebenarnya.
// ===================================================================
const { pool } = require('./src/config/database');
const { getAlerts, statusAlarm } = require('./src/controllers/emergency.controller');

/** Jam dinding WIB dari sebuah instant, apa pun zona proses ini. */
function jamWib(nilaiJson) {
  const d = new Date(nilaiJson);
  const f = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Jakarta',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false,
  });
  const p = Object.fromEntries(f.formatToParts(d).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}`;
}

function mockReqRes({ query = {}, user = null } = {}) {
  let statusCode = 200;
  let body = null;
  return {
    req: { query, params: {}, body: {}, user, headers: {}, ip: '127.0.0.1', socket: { remoteAddress: '127.0.0.1' } },
    res: {
      status(c) { statusCode = c; return this; },
      json(d) { body = d; return this; },
      getStatusCode() { return statusCode; },
      // Melewati JSON.stringify DENGAN SENGAJA: itulah yang benar-benar
      // dikirim express ke klien. Membandingkan objek Date di memori akan
      // melewatkan bug ini sepenuhnya, karena pergeserannya lahir saat
      // Date diserialisasi menjadi string ISO.
      getBodyKawat() { return JSON.parse(JSON.stringify(body)); },
    },
  };
}

// Jam dinding WIB yang dipakai contoh, persis seperti laporan bug.
const WIB_DIBUAT = '2026-08-16 16:45:00';
const WIB_DITUTUP = '2026-08-16 17:20:00';

const HARAP_DIBUAT = '2026-08-16 16:45';
const HARAP_DITUTUP = '2026-08-16 17:20';
const SALAH_MAJU = '2026-08-16 23:45';   // gejala bug: +7 jam
const SALAH_MUNDUR = '2026-08-16 09:45'; // gejala kebalikannya: -7 jam

let idUji = null;
let idAktif = null;
let userUji = null;

(async () => {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  console.log(`Zona proses Node: ${tz}`);

  // --- fixture -----------------------------------------------------
  const u = await pool.query(
    `INSERT INTO users (email, role, nama, password_hash)
     VALUES ($1, 'warga', 'Warga Uji Zona', 'hash') RETURNING id, nama, role`,
    [`uji_zona_${Date.now()}_${process.pid}@test.local`]
  );
  userUji = u.rows[0];

  // Ditulis sebagai jam dinding LITERAL — persis bentuk yang tersimpan di
  // produksi setelah DB_TIMEZONE dipasang.
  const a = await pool.query(
    `INSERT INTO emergency_alerts (user_id, message, status, created_at, dismissed_at, dismissed_by)
     VALUES ($1, 'Uji zona waktu', 'dismissed', $2::timestamp, $3::timestamp, $1)
     RETURNING id`,
    [userUji.id, WIB_DIBUAT, WIB_DITUTUP]
  );
  idUji = a.rows[0].id;

  const b = await pool.query(
    `INSERT INTO emergency_alerts (user_id, message, status, created_at)
     VALUES ($1, 'Uji zona waktu aktif', 'active', $2::timestamp)
     RETURNING id`,
    [userUji.id, WIB_DIBUAT]
  );
  idAktif = b.rows[0].id;

  // --- 1. created_at lewat GET /emergency/alerts -------------------
  console.log('1. created_at pada daftar riwayat...');
  {
    const { req, res } = mockReqRes({ user: { id: userUji.id, role: 'admin' } });
    await getAlerts(req, res);
    assert.strictEqual(res.getStatusCode(), 200, 'getAlerts harus 200');

    const baris = res.getBodyKawat().data.find((x) => x.id === idUji);
    assert.ok(baris, 'baris uji harus ada di respons');

    const terbaca = jamWib(baris.created_at);
    console.log(`   dikirim  : ${baris.created_at}`);
    console.log(`   di WIB   : ${terbaca}`);

    assert.notStrictEqual(terbaca, SALAH_MAJU,
      `created_at MAJU 7 jam: tampil ${SALAH_MAJU}, seharusnya ${HARAP_DIBUAT}`);
    assert.notStrictEqual(terbaca, SALAH_MUNDUR,
      `created_at MUNDUR 7 jam: tampil ${SALAH_MUNDUR}, seharusnya ${HARAP_DIBUAT}`);
    assert.strictEqual(terbaca, HARAP_DIBUAT,
      `created_at seharusnya ${HARAP_DIBUAT}, tetapi terbaca ${terbaca}`);

    console.log(`   OK — kejadian pukul 16:45 WIB tampil 16:45.\n`);
  }

  // --- 2. dismissed_at ---------------------------------------------
  console.log('2. dismissed_at pada daftar riwayat...');
  {
    const { req, res } = mockReqRes({ user: { id: userUji.id, role: 'admin' } });
    await getAlerts(req, res);

    const baris = res.getBodyKawat().data.find((x) => x.id === idUji);
    assert.ok(baris.dismissed_at, 'dismissed_at tidak boleh null pada baris uji');

    const terbaca = jamWib(baris.dismissed_at);
    console.log(`   dikirim  : ${baris.dismissed_at}`);
    console.log(`   di WIB   : ${terbaca}`);

    assert.notStrictEqual(terbaca, '2026-08-17 00:20',
      'dismissed_at MAJU 7 jam');
    assert.strictEqual(terbaca, HARAP_DITUTUP,
      `dismissed_at seharusnya ${HARAP_DITUTUP}, tetapi terbaca ${terbaca}`);

    console.log(`   OK — penutupan pukul 17:20 WIB tampil 17:20.\n`);
  }

  // --- 3. created_at pada kejadian aktif (statusAlarm) --------------
  console.log('3. created_at pada /emergency/alarm/status...');
  {
    const { req, res } = mockReqRes({ user: { id: userUji.id, role: 'admin' } });
    await statusAlarm(req, res);

    const k = res.getBodyKawat().data.kejadian_aktif;
    assert.ok(k, 'kejadian_aktif harus ada');

    const terbaca = jamWib(k.created_at);
    console.log(`   dikirim  : ${k.created_at}`);
    console.log(`   di WIB   : ${terbaca}`);

    assert.notStrictEqual(terbaca, SALAH_MAJU, 'created_at kejadian aktif MAJU 7 jam');
    assert.strictEqual(terbaca, HARAP_DIBUAT,
      `created_at kejadian aktif seharusnya ${HARAP_DIBUAT}, tetapi ${terbaca}`);

    console.log(`   OK.\n`);
  }

  // --- 4. instant identik di zona proses mana pun -------------------
  console.log('4. Nilai kawat tidak bergantung pada zona proses Node...');
  {
    const { req, res } = mockReqRes({ user: { id: userUji.id, role: 'admin' } });
    await getAlerts(req, res);
    const baris = res.getBodyKawat().data.find((x) => x.id === idUji);

    // Instant yang benar untuk 16:45 WIB adalah 09:45Z. Nilai ini HARUS sama
    // apa pun TZ proses — itulah properti yang dulu tidak dimiliki kode ini.
    assert.strictEqual(baris.created_at, '2026-08-16T09:45:00.000Z',
      `nilai kawat berubah mengikuti zona proses: ${baris.created_at}`);
    assert.strictEqual(baris.dismissed_at, '2026-08-16T10:20:00.000Z',
      `dismissed_at kawat berubah mengikuti zona proses: ${baris.dismissed_at}`);

    console.log('   OK — created_at & dismissed_at identik di Asia/Jakarta maupun UTC.\n');
  }

  console.log(`SELURUH 4 PEMERIKSAAN LULUS pada TZ=${tz}.`);
})()
  .then(async () => {
    await bersihkan();
    process.exit(0);
  })
  .catch(async (e) => {
    console.error('\nPENGUJIAN GAGAL:', e.message);
    await bersihkan();
    process.exit(1);
  });

async function bersihkan() {
  try {
    for (const id of [idUji, idAktif]) {
      if (id) await pool.query('DELETE FROM emergency_alerts WHERE id = $1', [id]);
    }
    if (userUji) await pool.query('DELETE FROM users WHERE id = $1', [userUji.id]);
  } catch (e) {
    console.error('Gagal membersihkan fixture:', e.message);
  } finally {
    await pool.end();
  }
}
