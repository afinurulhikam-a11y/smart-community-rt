require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-notification-dispatcher');

const { pool } = require('../src/config/database');
const dispatcher = require('../src/services/notification.dispatcher');
const { setMockMessaging } = require('../src/config/firebase');

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
}

async function runDispatcherTests() {
  console.log('================================================================');
  console.log('TEST UNIT & INTEGRASI NOTIFICATION DISPATCHER (PHASE 2C)');
  console.log('================================================================\n');

  let adminUser = null;
  let ketuaRt = null;
  let inactivePengurus = null;
  let wargaActive = null;
  let wargaInactive = null;

  const tokenAdmin = `fcm_disp_admin_${Date.now()}`;
  const tokenKetua = `fcm_disp_ketua_${Date.now()}`;
  const tokenInactPengurus = `fcm_disp_inactpengurus_${Date.now()}`;
  const tokenWarga = `fcm_disp_warga_${Date.now()}`;
  const tokenWargaInact = `fcm_disp_wargainact_${Date.now()}`;

  const capturedMessages = [];

  try {
    // 1. Setup isolated database fixtures
    console.log('1. Menyiapkan database fixture (Pengurus Aktif/Nonaktif, Warga Aktif/Nonaktif, Token FCM)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin Dispatcher', `admin_disp_${Date.now()}@test.local`, `adm_disp_${Date.now()}`, `3251${Date.now()}`.slice(0, 16)]
    );
    adminUser = adminRes.rows[0];

    const ketuaRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'ketua_rt', true, $3, $4)
       RETURNING id, nama, role`,
      ['Ketua RT Dispatcher', `ketua_disp_${Date.now()}@test.local`, `ket_disp_${Date.now()}`, `3252${Date.now()}`.slice(0, 16)]
    );
    ketuaRt = ketuaRes.rows[0];

    const inactPengurusRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'sekretaris', false, $3, $4)
       RETURNING id, nama, role`,
      ['Sekretaris Nonaktif', `sekret_disp_${Date.now()}@test.local`, `sek_disp_${Date.now()}`, `3253${Date.now()}`.slice(0, 16)]
    );
    inactivePengurus = inactPengurusRes.rows[0];

    const wargaRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Budi Warga Aktif', `budi_disp_${Date.now()}@test.local`, `budi_disp_${Date.now()}`, `3254${Date.now()}`.slice(0, 16)]
    );
    wargaActive = wargaRes.rows[0];

    const wargaInactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', false, $3, $4)
       RETURNING id, nama, role`,
      ['Siti Warga Nonaktif', `siti_disp_${Date.now()}@test.local`, `siti_disp_${Date.now()}`, `3255${Date.now()}`.slice(0, 16)]
    );
    wargaInactive = wargaInactRes.rows[0];

    // Daftarkan token
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Admin Device', true)`,
      [adminUser.id, tokenAdmin]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Ketua Device', true)`,
      [ketuaRt.id, tokenKetua]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Inactive Pengurus Device', true)`,
      [inactivePengurus.id, tokenInactPengurus]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Warga Device', true)`,
      [wargaActive.id, tokenWarga]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Inactive Warga Device', true)`,
      [wargaInactive.id, tokenWargaInact]
    );

    console.log('   OK — Database fixtures berhasil disiapkan.\n');

    // 2. Setup Mock Messaging
    const mockMessaging = {
      send: async (msg) => {
        capturedMessages.push(msg);
        return 'mock-disp-msg-id';
      },
      sendEachForMulticast: async (msg) => {
        capturedMessages.push(msg);
        return {
          successCount: msg.tokens.length,
          failureCount: 0,
          responses: msg.tokens.map((t) => ({ success: true, messageId: `msg-${t}` })),
        };
      },
    };
    setMockMessaging(mockMessaging);

    // 3. Test sendToUser
    console.log('2. Menguji dispatcher.sendToUser...');
    capturedMessages.length = 0;
    const resSendUser = await dispatcher.sendToUser(wargaActive.id, {
      title: 'Pemberitahuan Warga',
      body: 'Halo Budi, ini pesan khusus.',
      data: { entity_type: 'personal', entity_id: '123', action: 'TEST_USER' },
      priority: 'high',
      collapseKey: 'user_notif',
    });
    assert(resSendUser.tokensCount === 1, 'Harus menemukan 1 token aktif');
    assert(capturedMessages.length === 1, 'Pesan harus dikirim');
    const userMsg = capturedMessages[0];
    const targetTokenUser = userMsg.token || userMsg.tokens?.[0];
    assert(targetTokenUser === tokenWarga, 'Token harus milik warga aktif');
    assert(userMsg.notification.title === 'Pemberitahuan Warga', 'Title harus sesuai');
    assert(userMsg.data.entity_type === 'personal', 'data.entity_type harus personal');
    console.log('   OK — dispatcher.sendToUser mendelegasikan ke fcmService secara akurat.\n');

    // Test sendToUser dengan user ID kosong
    const resEmptyUser = await dispatcher.sendToUser(null, { title: 'Test' });
    assert(resEmptyUser.skipped === true, 'sendToUser tanpa userId harus diskip');
    console.log('   OK — dispatcher.sendToUser menangani userId null dengan aman.\n');

    // 4. Test sendToUsers
    console.log('3. Menguji dispatcher.sendToUsers...');
    capturedMessages.length = 0;
    const resSendUsers = await dispatcher.sendToUsers([adminUser.id, wargaActive.id], {
      title: 'Notifikasi Multi User',
      body: 'Pesan untuk Admin dan Warga.',
      data: { entity_type: 'multi', entity_id: '456', action: 'TEST_MULTI' },
    });
    assert(resSendUsers.tokensCount === 2, 'Harus menemukan 2 token aktif');
    assert(capturedMessages.length === 1, 'Multicast harus dikirim');
    const multiMsg = capturedMessages[0];
    const tokensList = multiMsg.tokens || [multiMsg.token];
    assert(tokensList.includes(tokenAdmin), 'Harus memuat token admin');
    assert(tokensList.includes(tokenWarga), 'Harus memuat token warga');
    console.log('   OK — dispatcher.sendToUsers multicast berhasil.\n');

    // 5. Test sendToRoles
    console.log('4. Menguji dispatcher.sendToRoles...');
    capturedMessages.length = 0;
    const resSendRoles = await dispatcher.sendToRoles(dispatcher.PERAN_PENGURUS, {
      title: 'Info Pengurus',
      body: 'Ada agenda pengurus baru.',
      data: { entity_type: 'agenda', entity_id: '789', action: 'NEW_AGENDA' },
    });
    assert(resSendRoles.tokensCount >= 2, 'Harus menemukan token pengurus aktif');
    assert(capturedMessages.length === 1, 'Multicast pengurus harus terkirim');
    const rolesMsg = capturedMessages[0];
    const rolesTokens = rolesMsg.tokens || [rolesMsg.token];
    assert(rolesTokens.includes(tokenAdmin), 'Harus menargetkan admin');
    assert(rolesTokens.includes(tokenKetua), 'Harus menargetkan ketua RT');
    assert(!rolesTokens.includes(tokenInactPengurus), 'TIDAK BOLEH menargetkan pengurus nonaktif');
    assert(!rolesTokens.includes(tokenWarga), 'TIDAK BOLEH menargetkan warga biasa');
    console.log('   OK — dispatcher.sendToRoles berhasil memfilter peran aktif tanpa membocorkan ke peran lain.\n');

    // 6. Test sendToAllActive
    console.log('5. Menguji dispatcher.sendToAllActive (Broadcast)...');
    capturedMessages.length = 0;
    const resSendAll = await dispatcher.sendToAllActive({
      title: 'Broadcast Warga',
      body: 'Pengumuman kerja bakti.',
      data: { entity_type: 'announcement', entity_id: '999', action: 'BROADCAST' },
    });
    assert(resSendAll.tokensCount >= 3, 'Harus menemukan seluruh token aktif');
    assert(capturedMessages.length === 1, 'Broadcast harus terkirim');
    const allMsg = capturedMessages[0];
    const allTokens = allMsg.tokens || [allMsg.token];
    assert(allTokens.includes(tokenAdmin), 'Harus memuat admin aktif');
    assert(allTokens.includes(tokenKetua), 'Harus memuat ketua aktif');
    assert(allTokens.includes(tokenWarga), 'Harus memuat warga aktif');
    assert(!allTokens.includes(tokenInactPengurus), 'TIDAK BOLEH memuat pengurus nonaktif');
    assert(!allTokens.includes(tokenWargaInact), 'TIDAK BOLEH memuat warga nonaktif');
    console.log('   OK — dispatcher.sendToAllActive berhasil menyaring hanya akun aktif.\n');

    // 7. Test dispatchAsync Helper & Error Isolation
    console.log('6. Menguji dispatcher.dispatchAsync untuk eksekusi non-blocking dan error isolation...');
    let asyncExecuted = false;
    dispatcher.dispatchAsync(async () => {
      asyncExecuted = true;
    }, 'TestAsyncSuccess');

    await new Promise((resolve) => setTimeout(resolve, 30));
    assert(asyncExecuted === true, 'Fungsi async harus dieksekusi oleh setImmediate');

    // Uji error isolation (async throwing error tidak boleh membuat proses crash)
    let errorCaughtInSafeHandler = false;
    dispatcher.dispatchAsync(async () => {
      errorCaughtInSafeHandler = true;
      throw new Error('Simulated Async Failure');
    }, 'TestAsyncError');

    await new Promise((resolve) => setTimeout(resolve, 30));
    assert(errorCaughtInSafeHandler === true, 'Handler error harus mengeksekusi dan mengisolasi kegagalan tanpa crash');
    console.log('   OK — dispatcher.dispatchAsync mengisolasi error async dengan sempurna.\n');

    console.log('================================================================');
    console.log('SEMUA PENGUJIAN NOTIFICATION DISPATCHER LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);
    await new Promise((resolve) => setTimeout(resolve, 50));

    console.log('Membersihkan database fixture pengujian dispatcher...');
    if (adminUser?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [adminUser.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [adminUser.id]);
    }
    if (ketuaRt?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [ketuaRt.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [ketuaRt.id]);
    }
    if (inactivePengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [inactivePengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [inactivePengurus.id]);
    }
    if (wargaActive?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [wargaActive.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [wargaActive.id]);
    }
    if (wargaInactive?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [wargaInactive.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [wargaInactive.id]);
    }
    console.log('Database fixture berhasil dibersihkan.\n');
    await pool.end();
  }
}

if (require.main === module) {
  runDispatcherTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST NOTIFICATION DISPATCHER GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runDispatcherTests };
