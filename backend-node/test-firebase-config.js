/**
 * Test Suite: Firebase Admin SDK Configuration & Security Diagnostics
 * ===================================================================
 * Memvalidasi:
 * 1. Dukungan format string JSON dan Base64 pada FIREBASE_SERVICE_ACCOUNT_KEY.
 * 2. Normalisasi karakter newline "\\n" pada private_key.
 * 3. Penggunaan FIREBASE_PROJECT_ID secara benar (fallback / override).
 * 4. Mode simulasi aktif HANYA ketika kredensial tidak tersedia.
 * 5. Diagnostic / readiness check yang aman:
 *    - Melaporkan configured, simulation_mode, project_id, credential_source.
 *    - Assert ketat: TIDAK PERNAH membocorkan private_key, client_email,
 *      nilai secret FIREBASE_SERVICE_ACCOUNT_KEY, atau FCM token.
 * 6. Integrasi dengan mock messaging dan fail-safe fallback.
 * ===================================================================
 */

const assert = require('assert');
const crypto = require('crypto');
const {
  initFirebase,
  getMessaging,
  isFirebaseConfigured,
  getFirebaseDiagnostic,
  setMockMessaging,
  resetFirebaseForTesting,
  parseServiceAccountKey,
} = require('./src/config/firebase');

// Generate valid PKCS8 PEM untuk keperluan fixture pengujian unit
const { privateKey: validTestPem } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

const TEST_SA_OBJECT = {
  type: 'service_account',
  project_id: 'smart-community-rt-test',
  private_key_id: 'test_key_id_987654321',
  private_key: validTestPem.replace(/\n/g, '\\n'), // Simulasikan escaped newlines seperti di env cloud
  client_email: 'firebase-adminsdk-test@smart-community-rt-test.iam.gserviceaccount.com',
  client_id: '123456789012345678901',
  auth_uri: 'https://accounts.google.com/o/oauth2/auth',
  token_uri: 'https://oauth2.googleapis.com/token',
};

const TEST_JSON_STRING = JSON.stringify(TEST_SA_OBJECT);
const TEST_BASE64_STRING = Buffer.from(TEST_JSON_STRING).toString('base64');

async function runAllFirebaseConfigTests() {
  console.log('\n================================================================');
  console.log('TEST SUITE: FIREBASE ADMIN SDK CONFIGURATION & READINESS CHECK');
  console.log('================================================================\n');

  let passed = 0;
  let total = 0;

  function it(name, fn) {
    total++;
    try {
      fn();
      console.log(`  ✅ PASS: ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ❌ FAIL: ${name}`);
      console.error(`     Reason: ${err.message}\n`);
      throw err;
    }
  }

  async function itAsync(name, fn) {
    total++;
    try {
      await fn();
      console.log(`  ✅ PASS: ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ❌ FAIL: ${name}`);
      console.error(`     Reason: ${err.message}\n`);
      throw err;
    }
  }

  // Backup original env vars
  const origKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
  const origPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  const origProjectId = process.env.FIREBASE_PROJECT_ID;
  const origAdc = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  try {
    // ------------------------------------------------------------------------
    // GROUP 1: Parser FIREBASE_SERVICE_ACCOUNT_KEY (JSON & Base64)
    // ------------------------------------------------------------------------
    console.log('--- 1. Parsing Format FIREBASE_SERVICE_ACCOUNT_KEY ---');

    it('Mendukung format raw string JSON', () => {
      const parsed = parseServiceAccountKey(TEST_JSON_STRING);
      assert(parsed !== null, 'Harus berhasil mem-parsing string JSON');
      assert.strictEqual(parsed.project_id, 'smart-community-rt-test');
      assert.strictEqual(parsed.client_email, TEST_SA_OBJECT.client_email);
    });

    it('Mendukung format Base64 encoded JSON', () => {
      const parsed = parseServiceAccountKey(TEST_BASE64_STRING);
      assert(parsed !== null, 'Harus berhasil mendecode dan mem-parsing Base64');
      assert.strictEqual(parsed.project_id, 'smart-community-rt-test');
      assert.strictEqual(parsed.client_email, TEST_SA_OBJECT.client_email);
    });

    it('Mendukung string dengan tanda kutip pembungkus (single/double quotes di env Railway)', () => {
      const quotedJson = `"${TEST_JSON_STRING.replace(/"/g, '\\"')}"`;
      const parsedJson = parseServiceAccountKey(quotedJson);
      assert(parsedJson !== null, 'Harus berhasil menangani string JSON berbalut kutip');
      assert.strictEqual(parsedJson.project_id, 'smart-community-rt-test');

      const quotedBase64 = `"${TEST_BASE64_STRING}"`;
      const parsedBase64 = parseServiceAccountKey(quotedBase64);
      assert(parsedBase64 !== null, 'Harus berhasil menangani Base64 berbalut kutip');
      assert.strictEqual(parsedBase64.project_id, 'smart-community-rt-test');
    });

    it('Menormalkan karakter newline literal ("\\n" -> "\\n") pada private_key', () => {
      const parsed = parseServiceAccountKey(TEST_JSON_STRING);
      assert(parsed.private_key.includes('\n'), 'Newline nyata harus ada pada private_key');
      assert(!parsed.private_key.includes('\\n'), 'Literal \\n harus telah digantikan dengan newline sebenarnya');
    });

    it('Mengembalikan null secara anggun jika format string tidak valid atau kosong', () => {
      assert.strictEqual(parseServiceAccountKey(''), null);
      assert.strictEqual(parseServiceAccountKey('   '), null);
      assert.strictEqual(parseServiceAccountKey(null), null);
      assert.strictEqual(parseServiceAccountKey('bukan-json-bukan-base64-valid@@!'), null);
    });

    // ------------------------------------------------------------------------
    // GROUP 2: Simulation Mode & Status Ketiadaan Kredensial
    // ------------------------------------------------------------------------
    console.log('\n--- 2. Mode Simulasi & Deteksi Kredensial ---');

    await itAsync('Mode simulasi aktif ketika kredensial TIDAK tersedia di env', async () => {
      delete process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
      delete process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      delete process.env.FIREBASE_PROJECT_ID;
      await resetFirebaseForTesting();

      assert.strictEqual(isFirebaseConfigured(), false, 'isFirebaseConfigured harus false tanpa kredensial');
      assert.strictEqual(getMessaging(), null, 'getMessaging harus null');

      const diagnostic = getFirebaseDiagnostic();
      assert.strictEqual(diagnostic.configured, false);
      assert.strictEqual(diagnostic.simulation_mode, true, 'simulation_mode harus true');
      assert.strictEqual(diagnostic.credential_source, 'none');
      assert.strictEqual(diagnostic.project_id, null);
    });

    await itAsync('Mengambil FIREBASE_PROJECT_ID dari env saat kredensial belum terpasang', async () => {
      delete process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
      delete process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      process.env.FIREBASE_PROJECT_ID = 'my-custom-rt-project';
      await resetFirebaseForTesting();

      const diagnostic = getFirebaseDiagnostic();
      assert.strictEqual(diagnostic.configured, false);
      assert.strictEqual(diagnostic.simulation_mode, true);
      assert.strictEqual(diagnostic.project_id, 'my-custom-rt-project');
    });

    // ------------------------------------------------------------------------
    // GROUP 3: Mock Messaging Integration
    // ------------------------------------------------------------------------
    console.log('\n--- 3. Mock Messaging & Kesiapan FCM ---');

    await itAsync('Mock messaging mengaktifkan configured = true dan mematikan simulation mode', async () => {
      await resetFirebaseForTesting();
      const mockInstance = {
        send: async () => 'mock-id-123',
        sendEachForMulticast: async () => ({ successCount: 1, failureCount: 0, responses: [] }),
      };
      setMockMessaging(mockInstance);

      assert.strictEqual(isFirebaseConfigured(), true, 'isFirebaseConfigured harus true saat mock terpasang');
      assert.strictEqual(getMessaging(), mockInstance, 'getMessaging harus mengembalikan instance mock');

      const diagnostic = getFirebaseDiagnostic();
      assert.strictEqual(diagnostic.configured, true);
      assert.strictEqual(diagnostic.simulation_mode, false);
      assert.strictEqual(diagnostic.credential_source, 'mock');
      assert.strictEqual(diagnostic.app_name, '[MOCK]');

      setMockMessaging(null);
    });

    // ------------------------------------------------------------------------
    // GROUP 4: Inisialisasi Kredensial Nyata & Keamanan Diagnostic (Zero-Leak)
    // ------------------------------------------------------------------------
    console.log('\n--- 4. Inisialisasi Base64 & Jaminan Keamanan: Anti-Bocor Kredensial ---');

    await itAsync('Inisialisasi Firebase Admin dengan Base64 Service Account Key berhasil', async () => {
      // Pasang service account key Base64 di env
      process.env.FIREBASE_SERVICE_ACCOUNT_KEY = TEST_BASE64_STRING;
      process.env.FIREBASE_PROJECT_ID = 'smart-community-rt-test';
      await resetFirebaseForTesting();

      const app = initFirebase();
      assert(app !== null, 'Firebase App harus berhasil diinisialisasi dengan Base64');
      assert.strictEqual(isFirebaseConfigured(), true, 'isFirebaseConfigured harus true');

      const messaging = getMessaging();
      assert(messaging !== null, 'getMessaging harus mengembalikan instance Messaging');

      const diagnostic = getFirebaseDiagnostic();
      assert.strictEqual(diagnostic.configured, true);
      assert.strictEqual(diagnostic.simulation_mode, false);
      assert.strictEqual(diagnostic.project_id, 'smart-community-rt-test');
      assert.strictEqual(diagnostic.credential_source, 'service_account_key');
    });

    await itAsync('Diagnostic check TIDAK PERNAH membocorkan private_key, client_email, secret, atau token', async () => {
      process.env.FIREBASE_SERVICE_ACCOUNT_KEY = TEST_BASE64_STRING;
      process.env.FIREBASE_PROJECT_ID = 'smart-community-rt-test';
      await resetFirebaseForTesting();

      const diagnostic = getFirebaseDiagnostic();

      // Cek whitelist struktur properti yang diizinkan
      const allowedKeys = ['configured', 'simulation_mode', 'project_id', 'credential_source', 'app_name'];
      const actualKeys = Object.keys(diagnostic);
      for (const key of actualKeys) {
        assert(allowedKeys.includes(key), `Key ${key} tidak diizinkan berada di payload diagnostik!`);
      }

      // Assert ketat: tidak ada secret string yang muncul dalam JSON stringified
      const serialized = JSON.stringify(diagnostic);
      assert(!serialized.includes('BEGIN PRIVATE KEY'), 'private_key dilarang keras bocor di output diagnostik!');
      assert(!serialized.includes(TEST_SA_OBJECT.client_email), 'client_email tidak boleh bocor!');
      assert(!serialized.includes(TEST_SA_OBJECT.private_key_id), 'private_key_id tidak boleh bocor!');
      assert(!serialized.includes(TEST_BASE64_STRING), 'Raw Base64 secret key dilarang bocor!');

      assert.strictEqual(diagnostic.project_id, 'smart-community-rt-test', 'project_id aman untuk dilaporkan');
      assert.strictEqual(diagnostic.credential_source, 'service_account_key');
    });

    // ------------------------------------------------------------------------
    // GROUP 5: Verifikasi Integrasi Output Health Check & Token Masking
    // ------------------------------------------------------------------------
    console.log('\n--- 5. Verifikasi Integrasi Output Health Check & Token Masking ---');

    it('Fungsi maskToken memasking token secara aman tanpa membocorkan token penuh', () => {
      const { maskToken } = require('./src/services/fcm.service');
      assert.strictEqual(maskToken('fcm_token_abcdef1234567890'), 'fcm_to...7890');
      assert.strictEqual(maskToken('short123'), '***');
      assert.strictEqual(maskToken(null), '[INVALID_TOKEN]');
      assert.strictEqual(maskToken(''), '[INVALID_TOKEN]');
    });

    it('Objek diagnostic cocok untuk disematkan pada /api/health tanpa membocorkan data rahasia', () => {
      const diagnostic = getFirebaseDiagnostic();
      const mockHealthResponse = {
        success: true,
        message: 'Smart Community RT — Backend API is running 🚀',
        database: 'ok',
        websocket_clients: 0,
        firebase: diagnostic,
        timestamp: new Date().toISOString(),
      };

      assert(typeof mockHealthResponse.firebase === 'object', 'Health response harus memiliki field firebase');
      assert('configured' in mockHealthResponse.firebase, 'Harus memiliki configured');
      assert('simulation_mode' in mockHealthResponse.firebase, 'Harus memiliki simulation_mode');
      assert('project_id' in mockHealthResponse.firebase, 'Harus memiliki project_id');
      assert('credential_source' in mockHealthResponse.firebase, 'Harus memiliki credential_source');

      const jsonStr = JSON.stringify(mockHealthResponse);
      assert(!jsonStr.includes('private_key'), 'private_key dilarang ada di health check');
      assert(!jsonStr.includes('client_email'), 'client_email dilarang ada di health check');
      assert(!jsonStr.includes('fcm_token'), 'fcm_token dilarang ada di health check');
    });

    // ------------------------------------------------------------------------
    // GROUP 6: Verifikasi Project smart-community-rt-78c93 & Security Hardening Test-Send
    // ------------------------------------------------------------------------
    console.log('\n--- 6. Verifikasi Project ID smart-community-rt-78c93 & Security Test-Send ---');

    await itAsync('Memastikan Project ID smart-community-rt-78c93 digunakan dengan benar', async () => {
      process.env.FIREBASE_PROJECT_ID = 'smart-community-rt-78c93';
      delete process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
      delete process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
      await resetFirebaseForTesting();

      const diagnostic = getFirebaseDiagnostic();
      assert.strictEqual(diagnostic.project_id, 'smart-community-rt-78c93', 'Project ID harus smart-community-rt-78c93');
      assert.strictEqual(diagnostic.simulation_mode, true, 'simulation_mode true karena kredensial belum ada');
    });

    const notificationService = require('./src/services/notification.service');
    const { sendTestNotification } = require('./src/controllers/notification.controller');

    function createMockRes() {
      const resObj = {
        code: 200,
        body: null,
        status(c) {
          this.code = c;
          return this;
        },
        json(d) {
          this.body = d;
          return this;
        },
      };
      return resObj;
    }

    await itAsync('User non-admin dengan arbitrary/unowned token DITOLAK dengan HTTP 403 Forbidden', async () => {
      const origIsOwned = notificationService.isTokenOwnedByUser;
      notificationService.isTokenOwnedByUser = async () => false; // Simulasikan token bukan milik user

      try {
        const req = {
          user: { id: 'uuid-user-warga-1', role: 'warga' },
          body: { fcm_token: 'arbitrary_third_party_token_1234567890' },
        };
        const res = createMockRes();
        await sendTestNotification(req, res);

        assert.strictEqual(res.code, 403, 'Harus mengembalikan HTTP 403');
        assert.strictEqual(res.body.success, false);
        assert(res.body.message.includes('Akses ditolak'), 'Pesan harus menyatakan akses ditolak');
      } finally {
        notificationService.isTokenOwnedByUser = origIsOwned;
      }
    });

    await itAsync('User non-admin dengan token miliknya sendiri DIIZINKAN (HTTP 200)', async () => {
      const origIsOwned = notificationService.isTokenOwnedByUser;
      notificationService.isTokenOwnedByUser = async () => true; // Simulasikan token valid milik user

      try {
        const req = {
          user: { id: 'uuid-user-warga-1', role: 'warga' },
          body: { fcm_token: 'owned_valid_token_1234567890' },
        };
        const res = createMockRes();
        await sendTestNotification(req, res);

        assert.strictEqual(res.code, 200, 'Harus mengembalikan HTTP 200');
        assert.strictEqual(res.body.success, true);
        assert(res.body.data.target_masked.includes('...'), 'Token target harus termasking');
      } finally {
        notificationService.isTokenOwnedByUser = origIsOwned;
      }
    });

    await itAsync('Admin diizinkan menguji token tertentu untuk keperluan diagnostik (HTTP 200)', async () => {
      const req = {
        user: { id: 'uuid-admin-1', role: 'admin' },
        body: { fcm_token: 'diagnostic_test_token_1234567890' },
      };
      const res = createMockRes();
      await sendTestNotification(req, res);

      assert.strictEqual(res.code, 200, 'Admin harus diizinkan (HTTP 200)');
      assert.strictEqual(res.body.success, true);
    });

    await itAsync('Fallback ke token aktif user ketika fcm_token tidak diberikan (HTTP 200)', async () => {
      const origGetTokens = notificationService.getTokensByUserId;
      notificationService.getTokensByUserId = async () => ['active_user_token_abcdef123456'];

      try {
        const req = {
          user: { id: 'uuid-user-warga-1', role: 'warga' },
          body: {},
        };
        const res = createMockRes();
        await sendTestNotification(req, res);

        assert.strictEqual(res.code, 200, 'Harus mengembalikan HTTP 200');
        assert.strictEqual(res.body.success, true);
        assert.strictEqual(res.body.data.target_masked, 'active...3456');
      } finally {
        notificationService.getTokensByUserId = origGetTokens;
      }
    });

    await itAsync('Mengembalikan HTTP 404 jika fcm_token tidak diberikan dan user tidak memiliki token aktif', async () => {
      const origGetTokens = notificationService.getTokensByUserId;
      notificationService.getTokensByUserId = async () => []; // Kosong

      try {
        const req = {
          user: { id: 'uuid-user-warga-empty', role: 'warga' },
          body: {},
        };
        const res = createMockRes();
        await sendTestNotification(req, res);

        assert.strictEqual(res.code, 404, 'Harus mengembalikan HTTP 404');
        assert.strictEqual(res.body.success, false);
      } finally {
        notificationService.getTokensByUserId = origGetTokens;
      }
    });

    await itAsync('Validasi input menolak title > 100 karakter atau kosong (HTTP 400)', async () => {
      const res1 = createMockRes();
      await sendTestNotification({ user: { id: 'u1', role: 'admin' }, body: { title: 'A'.repeat(101) } }, res1);
      assert.strictEqual(res1.code, 400, 'Title > 100 harus HTTP 400');

      const res2 = createMockRes();
      await sendTestNotification({ user: { id: 'u1', role: 'admin' }, body: { title: '   ' } }, res2);
      assert.strictEqual(res2.code, 400, 'Title kosong harus HTTP 400');
    });

    await itAsync('Validasi input menolak body > 500 karakter atau kosong (HTTP 400)', async () => {
      const res1 = createMockRes();
      await sendTestNotification({ user: { id: 'u1', role: 'admin' }, body: { body: 'B'.repeat(501) } }, res1);
      assert.strictEqual(res1.code, 400, 'Body > 500 harus HTTP 400');

      const res2 = createMockRes();
      await sendTestNotification({ user: { id: 'u1', role: 'admin' }, body: { body: '   ' } }, res2);
      assert.strictEqual(res2.code, 400, 'Body kosong harus HTTP 400');
    });

    await itAsync('Validasi input menolak fcm_token kosong atau > 500 karakter (HTTP 400)', async () => {
      const res1 = createMockRes();
      await sendTestNotification({ user: { id: 'u1', role: 'admin' }, body: { fcm_token: '   ' } }, res1);
      assert.strictEqual(res1.code, 400, 'fcm_token kosong harus HTTP 400');

      const res2 = createMockRes();
      await sendTestNotification({ user: { id: 'u1', role: 'admin' }, body: { fcm_token: 'C'.repeat(501) } }, res2);
      assert.strictEqual(res2.code, 400, 'fcm_token > 500 harus HTTP 400');
    });

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    console.log('\n================================================================');
    console.log(`HASIL: Semua ${passed} / ${total} test Konfigurasi Firebase LULUS!`);
    console.log('================================================================\n');
  } finally {
    // Restore original env vars
    if (origKey !== undefined) process.env.FIREBASE_SERVICE_ACCOUNT_KEY = origKey;
    else delete process.env.FIREBASE_SERVICE_ACCOUNT_KEY;

    if (origPath !== undefined) process.env.FIREBASE_SERVICE_ACCOUNT_PATH = origPath;
    else delete process.env.FIREBASE_SERVICE_ACCOUNT_PATH;

    if (origProjectId !== undefined) process.env.FIREBASE_PROJECT_ID = origProjectId;
    else delete process.env.FIREBASE_PROJECT_ID;

    if (origAdc !== undefined) process.env.GOOGLE_APPLICATION_CREDENTIALS = origAdc;
    else delete process.env.GOOGLE_APPLICATION_CREDENTIALS;

    await resetFirebaseForTesting();
  }
}

if (require.main === module) {
  runAllFirebaseConfigTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST KONFIGURASI FIREBASE GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runAllFirebaseConfigTests };
