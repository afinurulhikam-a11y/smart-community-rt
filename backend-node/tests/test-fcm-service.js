require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-fcm-service');

const { pool } = require('../src/config/database');
const {
  sendToToken,
  sendToTokens,
  sendToUser,
  sendToUsers,
  buildFcmPayload,
  sanitizeDataPayload,
  deactivateInvalidToken,
  isInvalidTokenError,
} = require('../src/services/fcm.service');
const { setMockMessaging } = require('../src/config/firebase');

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
}

async function runFcmSenderTests() {
  console.log('================================================================');
  console.log('TEST BACKEND FCM PUSH NOTIFICATION SENDER SERVICE (PHASE 1B.1)');
  console.log('================================================================\n');

  let testUser1 = null;
  let testUser2 = null;
  const tokenActive1 = `fcm_mock_active1_${Date.now()}`;
  const tokenActive2 = `fcm_mock_active2_${Date.now()}`;
  const tokenInactive = `fcm_mock_inactive_${Date.now()}`;
  const tokenUnregistered = `fcm_mock_unreg_${Date.now()}`;

  try {
    // 1. Test Payload Formatting & Sanitization
    console.log('1. Menguji sanitasi payload data dan formatting FCM...');
    const rawData = {
      id: 123,
      isActive: true,
      role: 'warga',
      metadata: { key: 'value' },
      nullField: null,
    };
    const sanitized = sanitizeDataPayload(rawData);
    assert(typeof sanitized.id === 'string' && sanitized.id === '123', 'id harus berupa string "123"');
    assert(typeof sanitized.isActive === 'string' && sanitized.isActive === 'true', 'isActive harus berupa string "true"');
    assert(typeof sanitized.metadata === 'string', 'object nested harus diserialisasi ke JSON string');
    assert(sanitized.nullField === undefined, 'nullField harus dibuang dari payload');

    const builtPayload = buildFcmPayload({
      title: 'Peringatan Darurat',
      body: 'Ada warga membutuhkan pertolongan.',
      data: rawData,
      priority: 'high',
      collapseKey: 'darurat_broadcast',
    });
    assert(builtPayload.notification.title === 'Peringatan Darurat', 'Judul harus cocok');
    assert(builtPayload.android.priority === 'high', 'Android priority harus high');
    assert(builtPayload.android.collapseKey === 'darurat_broadcast', 'Collapse key harus terpasang');
    console.log('   OK — Sanitasi payload data string dan formatting FCM lulus.\n');

    // 2. Setup isolated test users & tokens in Database
    console.log('2. Menyiapkan database fixture (User 1 & 2 dengan multi-device & status aktif/nonaktif)...');
    const u1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama`,
      ['FCM Test User 1', `fcm_sender1_${Date.now()}@test.local`, `fcm_s1_${Date.now()}`, `3205${Date.now()}`.slice(0, 16)]
    );
    testUser1 = u1Res.rows[0];

    const u2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama`,
      ['FCM Test User 2', `fcm_sender2_${Date.now()}@test.local`, `fcm_s2_${Date.now()}`, `3206${Date.now()}`.slice(0, 16)]
    );
    testUser2 = u2Res.rows[0];

    // User 1: 2 token aktif (multi-device) + 1 token tidak aktif
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Samsung Phone', true)`,
      [testUser1.id, tokenActive1]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Samsung Tablet', true)`,
      [testUser1.id, tokenActive2]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Old Phone', false)`,
      [testUser1.id, tokenInactive]
    );

    // User 2: 1 token yang nantinya akan disimulasikan UNREGISTERED
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Xiaomi Phone', true)`,
      [testUser2.id, tokenUnregistered]
    );
    console.log(`   User 1 ID: ${testUser1.id} (2 token aktif, 1 nonaktif)`);
    console.log(`   User 2 ID: ${testUser2.id} (1 token aktif)`);
    console.log('   OK — Setup database fixture berhasil.\n');

    // 3. Test Simulation Mode (Without Firebase credentials)
    console.log('3. Menguji mode simulasi pengiriman FCM (kredensial belum dipasang)...');
    setMockMessaging(null); // Pastikan mode fallback simulasi aktif

    const simSingle = await sendToToken(tokenActive1, {
      title: 'Uji Simulasi Token',
      body: 'Pesan uji simulasi FCM',
      data: { key: 'val' },
    });
    assert(simSingle.success === true, 'Simulasi sendToToken harus sukses');
    assert(simSingle.simulated === true, 'Harus bertanda simulated: true');

    const simMulti = await sendToTokens([tokenActive1, tokenActive2], {
      title: 'Uji Simulasi Multicast',
      body: 'Pesan uji multicast',
    });
    assert(simMulti.success === true && simMulti.successCount === 2, 'Simulasi multicast harus sukses dengan count 2');

    const simUser = await sendToUser(testUser1.id, {
      title: 'Uji Multi-Device User 1',
      body: 'Pesan terkirim ke multi-device aktif',
    });
    assert(simUser.success === true && simUser.tokensCount === 2, 'User 1 harus menargetkan 2 token aktif');

    const simUsers = await sendToUsers([testUser1.id, testUser2.id], {
      title: 'Uji Siaran Pengumuman',
      body: 'Pengumuman untuk seluruh warga',
    });
    assert(simUsers.success === true && simUsers.tokensCount === 3, 'Total 3 token aktif untuk kedua user');
    console.log('   OK — Mode simulasi fail-safe berjalan sempurna.\n');

    // 4. Test Mock Firebase Messaging: Successful Dispatch
    console.log('4. Menguji dispatch via Mock Firebase Messaging (Normal Flow)...');
    const mockSentMessages = [];
    const mockMessagingSuccess = {
      send: async (msg) => {
        mockSentMessages.push(msg);
        return `msg-id-${Date.now()}`;
      },
      sendEachForMulticast: async (msg) => {
        mockSentMessages.push(msg);
        return {
          successCount: msg.tokens.length,
          failureCount: 0,
          responses: msg.tokens.map((t) => ({ success: true, messageId: `msg-${t}` })),
        };
      },
    };
    setMockMessaging(mockMessagingSuccess);

    const mockSingleRes = await sendToToken(tokenActive1, {
      title: 'Notifikasi Tagihan Iuran',
      body: 'Tagihan iuran bulan ini telah terbit.',
      data: { bill_id: 'bill-uuid-123' },
    });
    assert(mockSingleRes.success === true && mockSingleRes.simulated === false, 'Mock sendToToken harus sukses');
    assert(mockSentMessages.length === 1, 'Pesan harus tercatat dikirim');
    console.log('   OK — Mock Firebase sendToToken berhasil.\n');

    // 5. Test Mock Firebase Messaging: Invalid Token Error & Auto-Cleanup
    console.log('5. Menguji penanganan error UNREGISTERED dan pembersihan token otomatis...');
    const mockMessagingWithUnreg = {
      send: async (msg) => {
        if (msg.token === tokenUnregistered) {
          const error = new Error('The registration token is not registered');
          error.code = 'messaging/registration-token-not-registered';
          throw error;
        }
        return 'success-id';
      },
      sendEachForMulticast: async (msg) => {
        return {
          successCount: msg.tokens.filter((t) => t !== tokenUnregistered).length,
          failureCount: msg.tokens.filter((t) => t === tokenUnregistered).length,
          responses: msg.tokens.map((t) => {
            if (t === tokenUnregistered) {
              const err = new Error('Token is no longer valid');
              err.code = 'messaging/registration-token-not-registered';
              return { success: false, error: err };
            }
            return { success: true, messageId: `msg-${t}` };
          }),
        };
      },
    };
    setMockMessaging(mockMessagingWithUnreg);

    // Kirim ke token unregistered via sendToToken
    const unregRes = await sendToToken(tokenUnregistered, {
      title: 'Uji Token Mati',
      body: 'Pesan ke token lama',
    });
    assert(unregRes.success === false, 'Kirim ke token unregistered harus mengembalikan success: false');

    // Cek database: tokenUnregistered harus sudah dinonaktifkan (is_active = false)
    const checkDb1 = await pool.query('SELECT is_active FROM user_fcm_tokens WHERE fcm_token = $1', [tokenUnregistered]);
    assert(checkDb1.rows[0].is_active === false, 'Token unregistered harus otomatis diubah menjadi is_active = false');
    console.log('   OK — Token unregistered otomatis dinonaktifkan di database.\n');

    // 6. Test Multi-Device Query Exclusion after Inactivation
    console.log('6. Menguji query user setelah token dinonaktifkan...');
    const user2ResAfterDeactivation = await sendToUser(testUser2.id, {
      title: 'Pesan Baru User 2',
      body: 'Harusnya tidak ada token aktif tersisa',
    });
    assert(user2ResAfterDeactivation.tokensCount === 0, 'User 2 tidak boleh memiliki token aktif');
    assert(user2ResAfterDeactivation.delivered === false, 'Pengiriman harus dilewati (delivered: false)');
    assert(user2ResAfterDeactivation.reason === 'no_active_tokens', 'Alasan harus no_active_tokens');
    console.log('   OK — User tanpa token aktif ditangani dengan elegan.\n');

    // 7. Test Error Pattern Recognition
    console.log('7. Menguji deteksi error code FCM...');
    assert(isInvalidTokenError({ code: 'messaging/registration-token-not-registered' }), 'Harus mengenali code unreg');
    assert(isInvalidTokenError({ message: 'UNREGISTERED token' }), 'Harus mengenali message unreg');
    assert(isInvalidTokenError({ code: 'messaging/invalid-registration-token' }), 'Harus mengenali invalid token');
    assert(!isInvalidTokenError({ code: 'messaging/internal-error' }), 'Internal error bukan token invalid');
    console.log('   OK — Pola error FCM dikenali dengan tepat.\n');

    console.log('================================================================');
    console.log('SEMUA 7 SKENARIO PENGUJIAN FCM SENDER SERVICE LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);
    // Cleanup fixtures
    console.log('Membersihkan database fixture pengujian FCM sender...');
    if (testUser1?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [testUser1.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [testUser1.id]);
    }
    if (testUser2?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [testUser2.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [testUser2.id]);
    }
    console.log('Database fixture berhasil dibersihkan.\n');
    await pool.end();
  }
}

if (require.main === module) {
  runFcmSenderTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST FCM SENDER GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runFcmSenderTests };
