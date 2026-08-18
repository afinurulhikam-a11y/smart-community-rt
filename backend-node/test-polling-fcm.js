require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-polling-fcm');

const { pool } = require('./src/config/database');
const {
  createPolling,
  updatePollingStatus,
  sendNewPollingPushNotification,
} = require('./src/controllers/polling.controller');
const { setMockMessaging } = require('./src/config/firebase');

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

async function waitForMessages(capturedArray, expectedCount = 1, maxAttempts = 20, delayMs = 25) {
  for (let i = 0; i < maxAttempts; i++) {
    if (capturedArray.length >= expectedCount) return;
    await new Promise((r) => setTimeout(r, delayMs));
  }
}

async function runPollingFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL POLLING (PHASE 2G)');
  console.log('================================================================\n');

  let adminUser = null;
  let wargaActive1 = null;
  let wargaActive2 = null;
  let wargaInactive = null;
  const createdPollingIds = [];

  const tokenAdmin = `fcm_token_admin_${Date.now()}`;
  const tokenWarga1 = `fcm_token_w1_${Date.now()}`;
  const tokenWarga2 = `fcm_token_w2_${Date.now()}`;
  const tokenInactiveToken = `fcm_token_inact_${Date.now()}`;
  const tokenInactiveUser = `fcm_token_userinact_${Date.now()}`;

  try {
    // 1. Setup database fixture
    console.log('1. Menyiapkan database fixture (Admin, Warga Aktif, Warga Nonaktif, FCM Tokens)...');
    const admRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin Polling', `adminpoll_${Date.now()}@test.local`, `admpoll_${Date.now()}`, `3201${Date.now()}`.slice(0, 16)]
    );
    adminUser = admRes.rows[0];

    const w1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Pemilih 1', `wargapoll1_${Date.now()}@test.local`, `wpoll1_${Date.now()}`, `3202${Date.now()}`.slice(0, 16)]
    );
    wargaActive1 = w1Res.rows[0];

    const w2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Pemilih 2', `wargapoll2_${Date.now()}@test.local`, `wpoll2_${Date.now()}`, `3203${Date.now()}`.slice(0, 16)]
    );
    wargaActive2 = w2Res.rows[0];

    const inactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', false, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Nonaktif', `wargapollinact_${Date.now()}@test.local`, `wpinact_${Date.now()}`, `3204${Date.now()}`.slice(0, 16)]
    );
    wargaInactive = inactRes.rows[0];

    // Daftarkan token FCM
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, is_active)
       VALUES ($1, $2, 'android', true),
              ($3, $4, 'android', true),
              ($5, $6, 'android', true),
              ($7, $8, 'android', false),
              ($9, $10, 'android', true)`,
      [
        adminUser.id, tokenAdmin,
        wargaActive1.id, tokenWarga1,
        wargaActive2.id, tokenWarga2,
        wargaActive1.id, tokenInactiveToken,
        wargaInactive.id, tokenInactiveUser,
      ]
    );
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Setup Mock Firebase Messaging
    let interceptedMessages = [];
    const mockMessaging = {
      send: async (payload) => {
        interceptedMessages.push(payload);
        return `msg_${Date.now()}`;
      },
      sendEachForMulticast: async (payload) => {
        interceptedMessages.push(payload);
        return {
          successCount: payload.tokens.length,
          failureCount: 0,
          responses: payload.tokens.map(() => ({ success: true, messageId: `msg_${Date.now()}` })),
        };
      },
    };
    setMockMessaging(mockMessaging);

    // 3. Menguji Event 1: Polling Aktif Baru Dibuat -> Push Broadcast ke Semua Warga Pemilih
    console.log('2. Menguji Pembuatan Polling Aktif Baru -> Push Notification ke seluruh pemilih aktif...');
    interceptedMessages = [];
    let poll1 = null;
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminUser,
        body: {
          judul: 'Pemilihan Pengadaan Lampu Jalan RT 01',
          deskripsi: 'Musyawarah pemilihan tipe solar panel atau PLN untuk penerangan lorong',
          tanggal_mulai: '2026-09-01',
          tanggal_selesai: '2026-09-10',
          options: ['Tipe Solar Panel Mandiri', 'Tipe Sambungan PLN Hemat Daya'],
        },
      });

      await createPolling(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      poll1 = res.getBody().data;
      createdPollingIds.push(poll1.id);

      // Tunggu background async dispatch
      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 multicast call, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];

      assert(msg.notification.title.includes('Polling Baru'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.notification.title.includes('Pemilihan Pengadaan Lampu Jalan'), `Title must include poll title: ${msg.notification.title}`);
      assert(msg.notification.body.includes('Suara Anda menentukan lingkungan RT'), `Body mismatch: ${msg.notification.body}`);
      assert(msg.data.entity_type === 'polling', `entity_type mismatch: ${msg.data.entity_type}`);
      assert(msg.data.entity_id === String(poll1.id), `entity_id mismatch: ${msg.data.entity_id}`);
      assert(msg.data.action === 'NEW_POLLING', `action mismatch: ${msg.data.action}`);
      assert(msg.data.judul === 'Pemilihan Pengadaan Lampu Jalan RT 01', `judul mismatch: ${msg.data.judul}`);
      assert(msg.data.tanggal_selesai === '2026-09-10', `tanggal_selesai mismatch: ${msg.data.tanggal_selesai}`);
      assert(msg.android.priority === 'normal', `priority mismatch: ${msg.android.priority}`);
      assert(msg.android.collapseKey === 'polling_broadcast', `collapseKey mismatch: ${msg.android.collapseKey}`);

      // Token verification
      assert(msg.tokens.includes(tokenAdmin), 'Token admin harus termuat');
      assert(msg.tokens.includes(tokenWarga1), 'Token warga pemilih 1 harus termuat');
      assert(msg.tokens.includes(tokenWarga2), 'Token warga pemilih 2 harus termuat');
      assert(!msg.tokens.includes(tokenInactiveToken), 'Token nonaktif TIDAK boleh termuat');
      assert(!msg.tokens.includes(tokenInactiveUser), 'Token user nonaktif TIDAK boleh termuat');

      // Database status verification
      const dbCheck = await pool.query('SELECT fcm_dispatch_status FROM polling WHERE id = $1', [poll1.id]);
      assert(dbCheck.rows[0].fcm_dispatch_status === 'sent', `Expected 'sent', got: ${dbCheck.rows[0].fcm_dispatch_status}`);

      console.log('   OK — Push notification polling aktif berhasil dikirim ke seluruh pemilih aktif dengan payload valid.\n');
    }

    // 4. Menguji Polling Draft / Non-Aktif TIDAK mengirim push
    console.log('3. Menguji Polling Tidak Aktif / Ditutup TIDAK mengirim push...');
    {
      const insRes = await pool.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
         VALUES ('Polling Ditutup Uji', 'Deskripsi', '2026-09-01', '2026-09-10', 'Ditutup', $1)
         RETURNING *`,
        [adminUser.id]
      );
      const closedPoll = insRes.rows[0];
      createdPollingIds.push(closedPoll.id);

      interceptedMessages = [];
      const skipRes = await sendNewPollingPushNotification(closedPoll);
      assert(skipRes.skipped === true, 'Polling not active must be skipped');
      assert(skipRes.reason === 'polling_not_active', `Expected reason 'polling_not_active', got: ${skipRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent for closed polling');
      console.log('   OK — Polling tidak aktif berhasil dilewati tanpa siaran push.\n');
    }

    // 5. Menguji Aktivasi Status Polling (updatePollingStatus menjadi 'Aktif') memicu push
    console.log('4. Menguji Aktivasi Status Polling (updatePollingStatus -> Aktif) memicu push...');
    {
      const insRes = await pool.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
         VALUES ('Polling Draft Baru', 'Deskripsi draft', '2026-09-01', '2026-09-10', 'Ditutup', $1)
         RETURNING *`,
        [adminUser.id]
      );
      const draftPoll = insRes.rows[0];
      createdPollingIds.push(draftPoll.id);

      interceptedMessages = [];
      const { req, res } = mockReqRes({
        method: 'PUT',
        params: { id: draftPoll.id },
        user: adminUser,
        body: { status: 'Aktif' },
      });

      await updatePollingStatus(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);

      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 multicast call, got ${interceptedMessages.length}`);
      console.log('   OK — Pengaktifan status polling memicu push notification siaran dengan sukses.\n');
    }

    // 6. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)
    console.log('5. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)...');
    {
      interceptedMessages = [];
      const dupRes = await sendNewPollingPushNotification(poll1);
      assert(dupRes.skipped === true, 'Duplicate push must be skipped');
      assert(dupRes.reason === 'already_sent_or_pending', `Expected reason 'already_sent_or_pending', got: ${dupRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent on duplicate trigger');
      console.log('   OK — Idempotency guard berhasil menahan siaran ganda pada polling yang sudah sent.\n');
    }

    // 7. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)
    console.log('6. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)...');
    {
      const insRes = await pool.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
         VALUES ('Polling Konkurensi', 'Deskripsi', '2026-09-01', '2026-09-10', 'aktif', $1)
         RETURNING *`,
        [adminUser.id]
      );
      const concPoll = insRes.rows[0];
      createdPollingIds.push(concPoll.id);

      interceptedMessages = [];
      const results = await Promise.all([
        sendNewPollingPushNotification(concPoll),
        sendNewPollingPushNotification(concPoll),
        sendNewPollingPushNotification(concPoll),
        sendNewPollingPushNotification(concPoll),
        sendNewPollingPushNotification(concPoll),
      ]);

      const sentCount = results.filter((r) => r.success === true).length;
      const skippedCount = results.filter((r) => r.skipped === true).length;
      assert(sentCount === 1, `Expected exactly 1 success, got ${sentCount}`);
      assert(skippedCount === 4, `Expected 4 skipped, got ${skippedCount}`);
      assert(interceptedMessages.length === 1, `Expected 1 multicast call, got ${interceptedMessages.length}`);
      console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');
    }

    // 8. Menguji Keandalan & Fail-Safe: FCM Failure TIDAK Membatalkan Pembuatan Polling
    console.log('7. Menguji keandalan: createPolling tetap sukses saat Firebase error...');
    {
      setMockMessaging({
        send: async () => {
          throw new Error('Firebase Unavailable (Simulated Error)');
        },
        sendEachForMulticast: async () => {
          throw new Error('Firebase Unavailable (Simulated Error)');
        },
      });

      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminUser,
        body: {
          judul: 'Polling Uji Ketahanan FCM Error',
          deskripsi: 'Memastikan createPolling tidak pernah gagal jika FCM down',
          tanggal_mulai: '2026-09-01',
          tanggal_selesai: '2026-09-15',
          options: ['Opsi 1', 'Opsi 2'],
        },
      });

      await createPolling(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      const failPoll = res.getBody().data;
      createdPollingIds.push(failPoll.id);

      // Beri jeda kecil agar background async memproses error
      await new Promise((resolve) => setTimeout(resolve, 60));

      const dbCheck = await pool.query('SELECT fcm_dispatch_status FROM polling WHERE id = $1', [failPoll.id]);
      assert(dbCheck.rows[0].fcm_dispatch_status === 'failed', `Expected 'failed', got: ${dbCheck.rows[0].fcm_dispatch_status}`);

      console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak pembuatan polling.\n');
    }

    console.log('================================================================');
    console.log('SEMUA 7 SKENARIO INTEGRASI FCM POLLING LULUS 100%!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('❌ PENGUJIAN FCM POLLING GAGAL:', err);
    process.exitCode = 1;
  } finally {
    setMockMessaging(null);
    console.log('Membersihkan database fixture pengujian polling FCM...');
    for (const pId of createdPollingIds) {
      await pool.query('DELETE FROM polling_votes WHERE polling_id = $1', [pId]).catch(() => {});
      await pool.query('DELETE FROM polling_options WHERE polling_id = $1', [pId]).catch(() => {});
      await pool.query('DELETE FROM polling WHERE id = $1', [pId]).catch(() => {});
    }
    await pool.query(
      `DELETE FROM user_fcm_tokens WHERE fcm_token IN ($1, $2, $3, $4, $5)`,
      [tokenAdmin, tokenWarga1, tokenWarga2, tokenInactiveToken, tokenInactiveUser]
    ).catch(() => {});
    const userIds = [adminUser?.id, wargaActive1?.id, wargaActive2?.id, wargaInactive?.id].filter(Boolean);
    if (userIds.length > 0) {
      await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [userIds]).catch(() => {});
    }
    console.log('Database fixture berhasil dibersihkan.');
    await pool.end();
  }
}

if (require.main === module) {
  runPollingFcmTests();
}

module.exports = { runPollingFcmTests };
