require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-auth-logout');

const jwt = require('jsonwebtoken');
const { pool } = require('../src/config/database');
const { logout } = require('../src/controllers/auth.controller');
const { authMiddleware } = require('../src/middleware/auth.middleware');

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
}

function mockReqRes({ method = 'POST', headers = {}, body = {}, user = null } = {}) {
  const req = {
    method,
    headers: { ...headers },
    body,
    user,
    ip: '127.0.0.1',
    socket: { remoteAddress: '127.0.0.1' },
    get(headerName) {
      return this.headers[headerName.toLowerCase()];
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

async function runAuthLogoutTests() {
  console.log('================================================================');
  console.log('TEST BACKEND AUTH LOGOUT & TOKEN INVOCATION/VERSIONING');
  console.log('================================================================\n');

  let testUser = null;
  const testEmail = `test_logout_${Date.now()}@test.local`;
  const jwtSecret = process.env.JWT_SECRET || 'supersecretkey_rt123_ganti_nanti';

  try {
    // 1. Setup isolated test user
    console.log('1. Membuat akun uji untuk logout test...');
    const uRes = await pool.query(
      `INSERT INTO users (email, role, nama, password_hash, token_versi) 
       VALUES ($1, 'warga', 'Warga Logout Test', 'hash', 1) 
       RETURNING id, email, role, nama, token_versi`,
      [testEmail]
    );
    testUser = uRes.rows[0];
    console.log(`   Akun dibuat: ${testUser.nama} (ID: ${testUser.id}, Token Versi: ${testUser.token_versi})\n`);

    // 2. Terbitkan token JWT dengan token_versi saat ini (tv: 1)
    console.log('2. Menerbitkan JWT token dengan klaim tv = 1...');
    const tokenV1 = jwt.sign(
      { id: testUser.id, email: testUser.email, role: testUser.role, tv: testUser.token_versi },
      jwtSecret,
      { expiresIn: '1h' }
    );

    // 3. Uji verifikasi authMiddleware dengan token yang sah
    console.log('3. Menguji akses authMiddleware dengan token awal (tv: 1)...');
    {
      const { req, res } = mockReqRes({
        headers: { authorization: `Bearer ${tokenV1}` },
      });
      let nextCalled = false;
      await authMiddleware(req, res, () => {
        nextCalled = true;
      });
      assert(nextCalled === true, 'authMiddleware should call next() for valid token');
      assert(req.user != null, 'req.user must be populated');
      assert(req.user.id === testUser.id, 'req.user.id must match testUser');
      console.log('   authMiddleware menerima token awal dengan sukses.\n');
    }

    // 4. Eksekusi endpoint logout
    console.log('4. Memanggil controller logout()...');
    {
      const { req, res } = mockReqRes({
        user: testUser,
      });
      await logout(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      console.log(`   Logout response: ${JSON.stringify(res.getBody())}`);

      // Periksa token_versi di database naik menjadi 2
      const updatedUser = await pool.query('SELECT id, token_versi FROM users WHERE id = $1', [testUser.id]);
      assert(updatedUser.rows[0].token_versi === testUser.token_versi + 1, 'token_versi in DB must increment by 1');
      console.log(`   token_versi di database berhasil naik: ${updatedUser.rows[0].token_versi}\n`);
    }

    // 5. Uji verifikasi bahwa token lama (tv: 1) sekarang DITOLAK oleh authMiddleware (HTTP 401)
    console.log('5. Menguji bahwa token lama (tv: 1) DITOLAK setelah logout...');
    {
      const { req, res } = mockReqRes({
        headers: { authorization: `Bearer ${tokenV1}` },
      });
      let nextCalled = false;
      await authMiddleware(req, res, () => {
        nextCalled = true;
      });
      assert(nextCalled === false, 'authMiddleware must NOT call next() for invalidated token');
      assert(res.getStatusCode() === 401, `Expected 401, got ${res.getStatusCode()}`);
      assert(res.getBody().success === false, 'Expected success === false');
      assert(res.getBody().message.includes('Sesi Anda sudah berakhir'), `Expected message 'Sesi Anda sudah berakhir', got: ${res.getBody().message}`);
      console.log(`   Penolakan token lama berhasil (HTTP 401: "${res.getBody().message}")\n`);
    }

    // 6. Periksa activity_logs mencatat aktivitas logout
    console.log('6. Memeriksa catatan activity_logs...');
    {
      const logs = await pool.query(
        "SELECT * FROM activity_logs WHERE user_id = $1 AND aktivitas LIKE '%Keluar dari semua perangkat%' ORDER BY id DESC LIMIT 1",
        [testUser.id]
      );
      assert(logs.rows.length === 1, 'activity_logs must contain logout record');
      console.log(`   Log tercatat: "${logs.rows[0].aktivitas}" (Tipe: ${logs.rows[0].tipe})\n`);
    }

    console.log('================================================================');
    console.log('SEMUA PENGUJIAN BACKEND LOGOUT & SESI BERHASIL 100%!');
    console.log('================================================================');
  } catch (err) {
    console.error('PENGUJIAN GAGAL:', err);
    process.exitCode = 1;
  } finally {
    if (testUser?.id) {
      await pool.query('DELETE FROM users WHERE id = $1', [testUser.id]);
      console.log('Akun uji berhasil dibersihkan.');
    }
    await pool.end();
  }
}

runAuthLogoutTests();
