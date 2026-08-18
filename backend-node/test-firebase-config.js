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
    // GROUP 5: Verifikasi Integrasi Output Health Check
    // ------------------------------------------------------------------------
    console.log('\n--- 5. Verifikasi Integrasi Output Health Check ---');

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
