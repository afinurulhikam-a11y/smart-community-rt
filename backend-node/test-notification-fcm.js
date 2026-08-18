require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-notification-fcm');

const { pool } = require('./src/config/database');
const { registerToken, unregisterToken } = require('./src/controllers/notification.controller');
const notificationService = require('./src/services/notification.service');

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
}

function mockReqRes({ method = 'POST', query = {}, body = {}, params = {}, user = null } = {}) {
  const req = {
    method,
    query,
    body,
    params,
    user,
    ip: '127.0.0.1',
    socket: { remoteAddress: '127.0.0.1' },
    get(headerName) {
      return this.headers?.[headerName.toLowerCase()];
    },
  };

  let statusCode = 200;
  let responseBody = null;

  const res = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(data) {
      responseBody = data;
      return this;
    },
    getStatusCode() {
      return statusCode;
    },
    getBody() {
      return responseBody;
    },
  };

  return { req, res };
}

async function runFcmNotificationTests() {
  console.log('================================================================');
  console.log('TEST BACKEND FCM NOTIFICATION TOKEN REGISTRY & LIFECYCLE');
  console.log('================================================================\n');

  let testUser1 = null;
  let testUser2 = null;
  const tokenFixtureA = `fcm_token_device_a_${Date.now()}`;
  const tokenFixtureB = `fcm_token_device_b_${Date.now()}`;

  try {
    // 1. Setup isolated test users with UUID
    console.log('1. Setup isolated test users...');
    const user1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Test FCM User 1', `fcm_u1_${Date.now()}@test.local`, `fcm_u1_${Date.now()}`, `3201${Date.now()}`.slice(0, 16)]
    );
    testUser1 = user1Res.rows[0];

    const user2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Test FCM User 2', `fcm_u2_${Date.now()}@test.local`, `fcm_u2_${Date.now()}`, `3202${Date.now()}`.slice(0, 16)]
    );
    testUser2 = user2Res.rows[0];

    assert(typeof testUser1.id === 'string' && testUser1.id.length > 20, 'User 1 ID harus UUID string');
    assert(typeof testUser2.id === 'string' && testUser2.id.length > 20, 'User 2 ID harus UUID string');
    console.log(`   User 1 ID (UUID): ${testUser1.id}`);
    console.log(`   User 2 ID (UUID): ${testUser2.id}`);
    console.log('   OK — Setup user fixture berhasil.\n');

    // 2. Test validasi input (fcm_token kosong / invalid)
    console.log('2. Menguji validasi input fcm_token...');
    const { req: reqInvalid, res: resInvalid } = mockReqRes({
      user: testUser1,
      body: { fcm_token: '' },
    });
    await registerToken(reqInvalid, resInvalid);
    assert(resInvalid.getStatusCode() === 400, 'Harus 400 jika fcm_token kosong');
    console.log('   OK — Penolakan token kosong berhasil (HTTP 400).\n');

    // 3. Test registrasi token pertama kali (User 1 -> Token A)
    console.log('3. Menguji registrasi token baru (User 1 -> Token A)...');
    const { req: reqReg1, res: resReg1 } = mockReqRes({
      user: testUser1,
      body: {
        fcm_token: tokenFixtureA,
        device_type: 'android',
        device_name: 'Samsung Galaxy S23',
      },
    });
    await registerToken(reqReg1, resReg1);
    assert(resReg1.getStatusCode() === 200, 'Registrasi token harus HTTP 200');
    assert(resReg1.getBody().success === true, 'Response body success harus true');
    assert(resReg1.getBody().data.device_type === 'android', 'Device type harus android');
    assert(resReg1.getBody().data.is_active === true, 'Status token harus aktif');

    const tokensU1 = await notificationService.getTokensByUserId(testUser1.id);
    assert(tokensU1.includes(tokenFixtureA), 'Token A harus tercatat pada User 1');
    console.log('   OK — Registrasi Token A pada User 1 berhasil.\n');

    // 4. Test re-registrasi / update token yang sama (UPSERT idempoten)
    console.log('4. Menguji UPSERT token (User 1 mendaftar ulang Token A dengan nama perangkat baru)...');
    const { req: reqRegUpdate, res: resRegUpdate } = mockReqRes({
      user: testUser1,
      body: {
        fcm_token: tokenFixtureA,
        device_type: 'android',
        device_name: 'Samsung Galaxy S23 (Updated)',
      },
    });
    await registerToken(reqRegUpdate, resRegUpdate);
    assert(resRegUpdate.getStatusCode() === 200, 'Update token harus HTTP 200');
    assert(resRegUpdate.getBody().data.device_name === 'Samsung Galaxy S23 (Updated)', 'Device name harus terupdate');

    const dbCheck1 = await pool.query('SELECT COUNT(*) FROM user_fcm_tokens WHERE fcm_token = $1', [tokenFixtureA]);
    assert(parseInt(dbCheck1.rows[0].count, 10) === 1, 'Token unik, tidak boleh ada duplikasi baris');
    console.log('   OK — Re-registrasi token bersifat idempoten tanpa duplikasi.\n');

    // 5. Test switch account / device re-assignment (User 2 login di HP yang sama -> Token A)
    console.log('5. Menguji pergantian akun pada perangkat yang sama (Token A berpindah ke User 2)...');
    const { req: reqSwitch, res: resSwitch } = mockReqRes({
      user: testUser2,
      body: {
        fcm_token: tokenFixtureA,
        device_type: 'android',
        device_name: 'Samsung Galaxy S23',
      },
    });
    await registerToken(reqSwitch, resSwitch);
    assert(resSwitch.getStatusCode() === 200, 'Re-assignment token harus HTTP 200');

    const tokensU1AfterSwitch = await notificationService.getTokensByUserId(testUser1.id);
    const tokensU2AfterSwitch = await notificationService.getTokensByUserId(testUser2.id);
    assert(!tokensU1AfterSwitch.includes(tokenFixtureA), 'Token A tidak boleh lagi milik User 1');
    assert(tokensU2AfterSwitch.includes(tokenFixtureA), 'Token A sekarang harus milik User 2');
    console.log('   OK — Token berhasil dialihkan ke User 2 saat berganti akun di perangkat.\n');

    // 6. Test pendaftaran multi-device (User 2 mendaftarkan perangkat kedua -> Token B)
    console.log('6. Menguji multi-device (User 2 mendaftarkan perangkat kedua Token B)...');
    const { req: reqRegB, res: resRegB } = mockReqRes({
      user: testUser2,
      body: {
        fcm_token: tokenFixtureB,
        device_type: 'android',
        device_name: 'Xiaomi Pad 6',
      },
    });
    await registerToken(reqRegB, resRegB);
    assert(resRegB.getStatusCode() === 200, 'Pendaftaran token kedua harus HTTP 200');

    const multiTokensU2 = await notificationService.getTokensByUserId(testUser2.id);
    assert(multiTokensU2.length === 2, 'User 2 harus memiliki 2 token aktif');
    assert(multiTokensU2.includes(tokenFixtureA) && multiTokensU2.includes(tokenFixtureB), 'Kedua token harus ada');
    console.log('   OK — Multi-device didukung penuh (2 token aktif untuk User 2).\n');

    // 7. Test isolasi kepemilikan unregister (User 1 mencoba mencabut Token A milik User 2)
    console.log('7. Menguji isolasi kepemilikan saat unregister token...');
    const { req: reqUnregLain, res: resUnregLain } = mockReqRes({
      user: testUser1,
      body: { fcm_token: tokenFixtureA },
    });
    await unregisterToken(reqUnregLain, resUnregLain);
    assert(resUnregLain.getStatusCode() === 200, 'Unregister harus HTTP 200');
    assert(resUnregLain.getBody().data.deleted_count === 0, 'User 1 tidak boleh bisa menghapus token milik User 2 (deleted_count 0)');

    const tokensU2StillSafe = await notificationService.getTokensByUserId(testUser2.id);
    assert(tokensU2StillSafe.includes(tokenFixtureA), 'Token A milik User 2 harus tetap aman');
    console.log('   OK — Isolasi kepemilikan token UUID terbukti aman.\n');

    // 8. Test pencabutan token yang sah (User 2 logout dari Token A)
    console.log('8. Menguji pencabutan token yang sah (User 2 menghapus Token A)...');
    const { req: reqUnregSah, res: resUnregSah } = mockReqRes({
      user: testUser2,
      body: { fcm_token: tokenFixtureA },
    });
    await unregisterToken(reqUnregSah, resUnregSah);
    assert(resUnregSah.getStatusCode() === 200, 'Unregister sah harus HTTP 200');
    assert(resUnregSah.getBody().data.deleted_count === 1, 'Token A harus berhasil dihapus (deleted_count 1)');

    const tokensU2AfterDelete = await notificationService.getTokensByUserId(testUser2.id);
    assert(!tokensU2AfterDelete.includes(tokenFixtureA), 'Token A harus sudah terhapus dari User 2');
    assert(tokensU2AfterDelete.includes(tokenFixtureB), 'Token B harus tetap aktif');
    console.log('   OK — Token A berhasil dicabut spesifik per perangkat.\n');

    // 9. Test unregister massal seluruh token user (saat logout global)
    console.log('9. Menguji pencabutan seluruh token user saat logout tanpa token spesifik...');
    const { req: reqUnregAll, res: resUnregAll } = mockReqRes({
      user: testUser2,
      body: {},
    });
    await unregisterToken(reqUnregAll, resUnregAll);
    assert(resUnregAll.getStatusCode() === 200, 'Unregister all harus HTTP 200');

    const tokensU2AfterUnregAll = await notificationService.getTokensByUserId(testUser2.id);
    assert(tokensU2AfterUnregAll.length === 0, 'Seluruh token User 2 harus sudah dinonaktifkan');
    console.log('   OK — Seluruh token aktif user dinonaktifkan.\n');

    console.log('================================================================');
    console.log('SEMUA 9 SKENARIO FCM NOTIFICATION TOKEN REGISTRY LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Cleanup fixtures
    console.log('Membersihkan fixture pengujian...');
    if (testUser1?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [testUser1.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [testUser1.id]);
    }
    if (testUser2?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [testUser2.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [testUser2.id]);
    }
    console.log('Fixture pengujian berhasil dibersihkan.\n');
    await pool.end();
  }
}

if (require.main === module) {
  runFcmNotificationTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST FCM REGISTRY GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runFcmNotificationTests };
