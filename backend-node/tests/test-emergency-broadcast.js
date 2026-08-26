/**
 * Siaran realtime darurat: HANYA pada jalur yang benar-benar berhasil.
 *
 * ===================================================================
 * Celah yang ditutup
 * ===================================================================
 *
 * `triggerAlarm` dan `dismissAlarm` sudah menyiarkan sejak awal, tetapi kedua
 * jalur TOMBOL DASBOR — `nyalakanDarurat` dan `matikanDarurat` — tidak. Jadi
 * menyalakan alarm dari dasbor satu ponsel tidak terlihat sama sekali di
 * ponsel lain sampai aplikasinya dibuka ulang; padahal itu alur yang paling
 * sering dipakai.
 *
 * ===================================================================
 * Yang dijaga berkas ini
 * ===================================================================
 *
 * Bukan sekadar "siarannya ada", melainkan siarannya TIDAK ADA pada setiap
 * jalur gagal. Siaran yang terkirim padahal transaksinya di-ROLLBACK akan
 * membuat ponsel lain menampilkan darurat yang tidak pernah tercatat — dan
 * tidak ada satu pun galat yang muncul untuk menandainya.
 *
 * `broadcast` dan MQTT diganti SEBELUM controller dimuat, karena controller
 * memegang referensinya saat di-`require`. Selain keduanya, semuanya berjalan
 * sungguhan: transaksi, kunci penasihat, validasi, dan otorisasi.
 */
require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-emergency-broadcast');

const assert = require('assert');
const { pool } = require('../src/config/database');

// --- ganti siaran & broker sebelum controller dimuat ------------------
const ws = require('../src/config/websocket');
const mqttAlarm = require('../src/config/mqtt');

const siaran = [];
let siaranMelempar = false;

ws.broadcast = (data, dataPerangkat) => {
  if (siaranMelempar) throw new Error('WebSocket tidak tersedia (disimulasikan)');
  siaran.push({ data, dataPerangkat });
  return 1;
};

let mqttGagal = false;
mqttAlarm.terbitkanPerintahAlarm = async () => {
  if (mqttGagal) throw new Error('broker tidak tersambung (disimulasikan)');
};
mqttAlarm.terkonfigurasi = () => true;
mqttAlarm.tersambung = () => true;
mqttAlarm.pernahTersambung = () => true;

const { kendaliAlarm } = require('../src/controllers/emergency.controller');

/**
 * RT bawaan, dipakai mengisi `rt_id` dan `rt_kode` pada pengguna palsu.
 *
 * Keduanya biasanya diisi authMiddleware dari join ke tabel `rt`. Uji ini
 * memanggil pengendali secara langsung, jadi harus disebut sendiri — tanpa itu
 * penerbitan alarm menolak, dan menolak memang perilaku yang benar: menebak RT
 * berarti membunyikan sirene di lingkungan yang salah.
 */
let RT_UJI = null;
async function muatRtUji() {
  const r = await pool.query(
    'SELECT id, kode FROM rt WHERE deleted_at IS NULL ORDER BY kode LIMIT 1'
  );
  if (!r.rows.length) throw new Error('Belum ada RT — jalankan migrasi v43 lebih dulu.');
  RT_UJI = r.rows[0];
}


process.env.EMERGENCY_PIN = '135790';
const PIN = '135790';

function mockReqRes({ body = {}, user = null } = {}) {
  let kode = 200;
  let isi = null;
  return {
    req: {
      body, query: {}, params: {}, user,
      headers: {}, ip: '127.0.0.1', socket: { remoteAddress: '127.0.0.1' },
    },
    res: {
      status(c) { kode = c; return this; },
      json(d) { isi = d; return this; },
      getStatusCode() { return kode; },
      getBody() { return isi; },
    },
  };
}

async function panggil(opsi) {
  const { req, res } = mockReqRes(opsi);
  await kendaliAlarm(req, res);
  return { kode: res.getStatusCode(), body: res.getBody() };
}

let warga = null;
let wargaLain = null;
let pengurus = null;

async function buatUser(peran, nama) {
  const r = await pool.query(
    `INSERT INTO users (email, role, nama, password_hash)
     VALUES ($1, $2, $3, 'hash') RETURNING id, nama, role`,
    [`uji_siaran_${Date.now()}_${Math.random().toString(36).slice(2, 8)}@test.local`, peran, nama]
  );
  return r.rows[0];
}

async function bersihkanAktif() {
  await pool.query("DELETE FROM emergency_alerts WHERE status = 'active'");
}

const KET = 'Kebakaran di dapur rumah nomor 12';

(async () => {
  console.log('\n================================================================');
  console.log('SIARAN REALTIME DARURAT — hanya pada jalur sukses');
  console.log('================================================================\n');

  warga = await buatUser('warga', 'Warga Pelapor');
  wargaLain = await buatUser('warga', 'Warga Lain');
  pengurus = await buatUser('ketua_rt', 'Ketua RT Uji');

  await muatRtUji();


  const sbgWarga = { id: warga.id, role: 'warga', nama: warga.nama, rt_id: RT_UJI.id, rt_kode: RT_UJI.kode };
  const sbgWargaLain = { id: wargaLain.id, role: 'warga', nama: wargaLain.nama, rt_id: RT_UJI.id, rt_kode: RT_UJI.kode };
  const sbgPengurus = { id: pengurus.id, role: 'ketua_rt', nama: pengurus.nama, rt_id: RT_UJI.id, rt_kode: RT_UJI.kode };

  await bersihkanAktif();

  // ------------------------------------------------------------------
  console.log('1. ON dari dasbor menyiarkan TEPAT SATU ALARM_ON...');
  let idAktif;
  {
    siaran.length = 0;
    const r = await panggil({ body: { aksi: 'ON', pin: PIN, keterangan: KET }, user: sbgWarga });

    assert.strictEqual(r.kode, 201);
    assert.strictEqual(siaran.length, 1, `harus 1 siaran, dapat ${siaran.length}`);

    const s = siaran[0];
    idAktif = r.body.data.emergency_id;

    assert.strictEqual(s.data.type, 'ALARM_ON');
    assert.strictEqual(s.data.event, 'emergency_alert');
    assert.strictEqual(s.data.alert_id, idAktif, 'alert_id harus menunjuk kejadian yang dibuat');
    assert.strictEqual(s.data.message, KET);
    assert.strictEqual(s.data.nama, warga.nama);

    // Muatan perangkat direduksi — tanpa nama, alamat, atau keterangan bebas.
    assert.strictEqual(s.dataPerangkat.type, 'ALARM_ON');
    assert.strictEqual(s.dataPerangkat.alert_id, idAktif);
    for (const bocor of ['nama', 'alamat', 'no_hp', 'message']) {
      assert.ok(!(bocor in s.dataPerangkat),
        `muatan perangkat tidak boleh memuat "${bocor}"`);
    }

    console.log(`   ALARM_ON alert_id=${idAktif}, muatan perangkat bersih dari PII.\n`);
  }

  // ------------------------------------------------------------------
  console.log('2. ON berulang: satu siaran per permintaan, kejadian tetap satu...');
  {
    siaran.length = 0;
    const r = await panggil({
      body: { aksi: 'ON', pin: PIN, keterangan: 'Keterangan lain' },
      user: sbgWargaLain,
    });

    assert.strictEqual(r.kode, 200);
    assert.strictEqual(r.body.data.kejadian_baru, false);
    assert.strictEqual(siaran.length, 1, 'satu permintaan = satu siaran, bukan dua');
    assert.strictEqual(siaran[0].data.alert_id, idAktif, 'harus menunjuk kejadian yang SAMA');

    const n = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(n.rows[0].n, 1, 'tidak boleh ada kejadian kedua');
    console.log('   1 siaran, alert_id sama, kejadian tetap satu.\n');
  }

  // ------------------------------------------------------------------
  console.log('3. OFF oleh warga lain (403) TIDAK menyiarkan...');
  {
    siaran.length = 0;
    const r = await panggil({ body: { aksi: 'OFF', pin: PIN }, user: sbgWargaLain });

    assert.strictEqual(r.kode, 403);
    assert.strictEqual(siaran.length, 0, 'otorisasi gagal tidak boleh menyiarkan');

    const b = await pool.query('SELECT status FROM emergency_alerts WHERE id = $1', [idAktif]);
    assert.strictEqual(b.rows[0].status, 'active', 'kejadian harus tetap aktif');
    console.log('   403, nol siaran, kejadian tetap aktif.\n');
  }

  // ------------------------------------------------------------------
  console.log('4. OFF oleh pengurus menyiarkan TEPAT SATU ALARM_OFF...');
  {
    siaran.length = 0;
    const r = await panggil({ body: { aksi: 'OFF', pin: PIN }, user: sbgPengurus });

    assert.strictEqual(r.kode, 200);
    assert.strictEqual(r.body.data.kejadian_ditutup, true);
    assert.strictEqual(siaran.length, 1, `harus 1 siaran, dapat ${siaran.length}`);

    const s = siaran[0];
    assert.strictEqual(s.data.type, 'ALARM_OFF');
    assert.strictEqual(s.data.event, 'emergency_dismissed');
    assert.strictEqual(s.data.alert_id, idAktif, 'harus menutup kejadian yang sama');
    assert.strictEqual(s.data.dismissed_by, pengurus.id);
    assert.strictEqual(s.dataPerangkat.type, 'ALARM_OFF');
    assert.ok(!('dismissed_by_nama' in s.dataPerangkat), 'alat tidak butuh nama penyelesai');

    console.log(`   ALARM_OFF alert_id=${idAktif}, penyelesai=${pengurus.nama}.\n`);
  }

  // ------------------------------------------------------------------
  console.log('5. OFF saat tidak ada kejadian aktif TIDAK menyiarkan...');
  {
    siaran.length = 0;
    const r = await panggil({ body: { aksi: 'OFF', pin: PIN }, user: sbgPengurus });

    assert.strictEqual(r.kode, 200);
    assert.strictEqual(r.body.data.kejadian_ditutup, false);
    // Tidak ada satu baris pun yang berubah, jadi tidak ada yang perlu
    // diumumkan ke perangkat lain.
    assert.strictEqual(siaran.length, 0, 'tanpa perubahan kejadian, tanpa siaran');
    console.log('   Nol siaran (perintah MATI ke alat tetap dikirim).\n');
  }

  // ------------------------------------------------------------------
  console.log('6. PIN salah TIDAK menyiarkan...');
  {
    siaran.length = 0;
    const r = await panggil({ body: { aksi: 'ON', pin: '000000', keterangan: KET }, user: sbgWarga });

    assert.strictEqual(r.kode, 403);
    assert.strictEqual(siaran.length, 0);
    console.log('   403, nol siaran.\n');
  }

  // ------------------------------------------------------------------
  console.log('7. Keterangan tidak sah TIDAK menyiarkan...');
  {
    siaran.length = 0;
    const r = await panggil({
      body: { aksi: 'ON', pin: PIN, keterangan: 'x'.repeat(501) },
      user: sbgWarga,
    });

    assert.strictEqual(r.kode, 400);
    assert.strictEqual(siaran.length, 0);
    console.log('   400, nol siaran.\n');
  }

  // ------------------------------------------------------------------
  console.log('8. MQTT gagal → ROLLBACK, dan TIDAK menyiarkan...');
  {
    await bersihkanAktif();
    siaran.length = 0;
    mqttGagal = true;

    const r = await panggil({ body: { aksi: 'ON', pin: PIN, keterangan: KET }, user: sbgWarga });
    mqttGagal = false;

    assert.ok(r.kode >= 500, `harus >=500, dapat ${r.kode}`);
    // Inilah yang paling berbahaya bila salah: siaran terkirim untuk kejadian
    // yang transaksinya dibatalkan akan membuat ponsel lain menampilkan
    // darurat yang tidak pernah tercatat.
    assert.strictEqual(siaran.length, 0, 'transaksi dibatalkan tidak boleh diumumkan');

    const n = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(n.rows[0].n, 0);
    console.log('   Nol siaran, nol kejadian.\n');
  }

  // ------------------------------------------------------------------
  console.log('9. Siaran gagal TIDAK menggagalkan mutasi...');
  {
    await bersihkanAktif();
    siaran.length = 0;
    siaranMelempar = true;

    const r = await panggil({ body: { aksi: 'ON', pin: PIN, keterangan: KET }, user: sbgWarga });
    siaranMelempar = false;

    // Realtime adalah pemberitahuan tambahan, bukan sumber kebenaran: baris
    // sudah tersimpan dan sirene sudah berbunyi, jadi menggagalkan permintaan
    // hanya akan membuat orang menekan tombolnya lagi.
    assert.strictEqual(r.kode, 201, `mutasi harus tetap berhasil, dapat ${r.kode}`);

    const n = await pool.query("SELECT COUNT(*)::int AS n FROM emergency_alerts WHERE status='active'");
    assert.strictEqual(n.rows[0].n, 1, 'kejadian harus tetap tercatat');
    console.log('   201, kejadian tersimpan walau siaran melempar.\n');

    await bersihkanAktif();
  }

  console.log('================================================================');
  console.log('SELURUH 9 SKENARIO SIARAN REALTIME LULUS.');
  console.log('================================================================\n');
})()
  .then(async () => { await bersihkan(); process.exit(0); })
  .catch(async (e) => {
    console.error('\nPENGUJIAN GAGAL:', e.message);
    await bersihkan();
    process.exit(1);
  });

async function bersihkan() {
  try {
    console.log('Membersihkan fixture pengujian...');
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
