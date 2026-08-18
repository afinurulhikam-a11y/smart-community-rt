require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-visitor-fcm');

const { pool } = require('./src/config/database');
const {
  createVisitor,
  sendVisitorArrivalPushNotification,
} = require('./src/controllers/visitor.controller');
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

async function runVisitorFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL E-VISITOR (PHASE 2F)');
  console.log('================================================================\n');

  let adminSatpam = null;
  let hostWargaActive = null;
  let hostWargaInactive = null;
  let otherWarga = null;
  const createdVisitorIds = [];

  const tokenHostActive = `fcm_token_host_${Date.now()}`;
  const tokenHostInactive = `fcm_token_host_inact_${Date.now()}`;
  const tokenOther = `fcm_token_other_${Date.now()}`;

  try {
    // 1. Setup fixture (Admin/Satpam, Warga Aktif, Warga Nonaktif, Warga Lain, Tokens)
    console.log('1. Menyiapkan database fixture (Satpam, Warga Tujuan Aktif/Nonaktif, FCM Tokens)...');
    const admRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Satpam Pos RT', `satpam_${Date.now()}@test.local`, `satpam_${Date.now()}`, `3201${Date.now()}`.slice(0, 16)]
    );
    adminSatpam = admRes.rows[0];

    const hostRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Pak RT / Warga Tujuan', `wargatujuan_${Date.now()}@test.local`, `wtujuan_${Date.now()}`, `3202${Date.now()}`.slice(0, 16)]
    );
    hostWargaActive = hostRes.rows[0];

    const hostInactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', false, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Tujuan Nonaktif', `wtujuaninact_${Date.now()}@test.local`, `wtinact_${Date.now()}`, `3203${Date.now()}`.slice(0, 16)]
    );
    hostWargaInactive = hostInactRes.rows[0];

    const otherRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Lain', `wargalain_${Date.now()}@test.local`, `wlain_${Date.now()}`, `3204${Date.now()}`.slice(0, 16)]
    );
    otherWarga = otherRes.rows[0];

    // Daftarkan token FCM (Host active: 1 aktif, 1 nonaktif; Other: 1 aktif)
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, is_active)
       VALUES ($1, $2, 'android', true),
              ($3, $4, 'android', false),
              ($5, $6, 'android', true)`,
      [
        hostWargaActive.id, tokenHostActive,
        hostWargaActive.id, tokenHostInactive,
        otherWarga.id, tokenOther,
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

    // 3. Menguji Event 1: Registrasi Tamu Masuk -> Push Notification ke Warga Tujuan
    console.log('2. Menguji Registrasi Tamu Tiba di Pos -> Push Notification ke Warga Tujuan...');
    interceptedMessages = [];
    let visitor1 = null;
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: hostWargaActive, // didaftarkan oleh warga tujuan langsung
        body: {
          nama_tamu: 'Bambang Santoso (Kurir Paket)',
          no_hp_tamu: '081234567890',
          blok_tujuan: 'Blok B3 No. 12',
          no_hp_tujuan: '081298765432',
          tipe_keperluan: 'Pengantaran',
          detail_keperluan: 'Mengantar paket dokumen penting',
          plat_nomor: 'B 1234 XYZ',
          jenis_kendaraan: 'Mobil',
        },
      });

      await createVisitor(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      visitor1 = res.getBody().data;
      createdVisitorIds.push(visitor1.id);

      // Tunggu background async dispatch selesai
      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];

      assert(msg.notification.title.includes('Tamu Tiba di Pos Keamanan'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.notification.title.includes('Bambang Santoso'), `Title must include guest name: ${msg.notification.title}`);
      assert(msg.notification.body.includes('B 1234 XYZ'), `Body must include vehicle: ${msg.notification.body}`);
      assert(msg.data.entity_type === 'visitor', `entity_type mismatch: ${msg.data.entity_type}`);
      assert(msg.data.entity_id === String(visitor1.id), `entity_id mismatch: ${msg.data.entity_id}`);
      assert(msg.data.action === 'VISITOR_ARRIVED', `action mismatch: ${msg.data.action}`);
      assert(msg.data.nama_tamu === 'Bambang Santoso (Kurir Paket)', `nama_tamu mismatch: ${msg.data.nama_tamu}`);
      assert(msg.data.kendaraan === 'B 1234 XYZ', `kendaraan mismatch: ${msg.data.kendaraan}`);
      assert(msg.data.blok_tujuan === 'Blok B3 No. 12', `blok_tujuan mismatch: ${msg.data.blok_tujuan}`);
      assert(msg.android.priority === 'high', `priority mismatch: ${msg.android.priority}`);
      assert(msg.android.collapseKey === `visitor_arrived_${visitor1.id}`, `collapseKey mismatch: ${msg.android.collapseKey}`);

      // Token verification
      const targetToken = msg.token || msg.tokens?.[0];
      assert(targetToken === tokenHostActive, 'Harus memuat token aktif milik warga tujuan');
      assert(targetToken !== tokenHostInactive, 'Token nonaktif TIDAK boleh termuat');
      assert(targetToken !== tokenOther, 'Token warga lain TIDAK boleh termuat');

      // Database status verification
      const dbCheck = await pool.query('SELECT fcm_dispatch_status FROM visitors WHERE id = $1', [visitor1.id]);
      assert(dbCheck.rows[0].fcm_dispatch_status === 'sent', `Expected 'sent', got: ${dbCheck.rows[0].fcm_dispatch_status}`);

      console.log('   OK — Push notification kedatangan tamu berhasil dikirim ke warga tujuan dengan payload valid.\n');
    }

    // 4. Menguji Event Satpam Mencatatkan Tamu untuk Warga Tertentu (via user_id/created_by)
    console.log('3. Menguji Satpam Mencatatkan Tamu untuk Warga Tujuan -> Push Notification Akurat...');
    interceptedMessages = [];
    let visitor2 = null;
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminSatpam,
        body: {
          nama_tamu: 'dr. Hendra (Keluarga Tamu)',
          no_hp_tamu: '081299887766',
          blok_tujuan: 'Blok B3 No. 12',
          no_hp_tujuan: '081298765432',
          tipe_keperluan: 'Kunjungan',
          detail_keperluan: 'Silaturahmi keluarga',
          plat_nomor: 'D 5678 ABC',
          jenis_kendaraan: 'Mobil',
          user_id: hostWargaActive.id,
        },
      });

      await createVisitor(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      visitor2 = res.getBody().data;
      createdVisitorIds.push(visitor2.id);

      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];
      const targetToken = msg.token || msg.tokens?.[0];
      assert(targetToken === tokenHostActive, 'Harus tetap menargetkan warga tujuan');
      assert(targetToken !== tokenOther, 'TIDAK boleh menargetkan warga lain');

      console.log('   OK — Satpam berhasil mencatat tamu dan notifikasi terkirim tepat ke warga tujuan.\n');
    }

    // 5. Menguji Durable Database Idempotency (Pencegahan siaran ganda pada event yang sama)
    console.log('4. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)...');
    {
      interceptedMessages = [];
      const dupRes = await sendVisitorArrivalPushNotification(visitor1);
      assert(dupRes.skipped === true, 'Duplicate push must be skipped');
      assert(dupRes.reason === 'already_sent_or_pending', `Expected reason 'already_sent_or_pending', got: ${dupRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent on duplicate trigger');
      console.log('   OK — Idempotency guard berhasil menahan siaran ganda pada tamu yang sudah sent.\n');
    }

    // 6. Menguji Warga Tujuan Nonaktif / Tidak Ditemukan -> Skip Aman Tanpa Kirim ke User Lain
    console.log('5. Menguji Warga Tujuan Nonaktif -> Pengiriman push dilewati secara aman...');
    {
      const insRes = await pool.query(
        `INSERT INTO visitors (nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, created_by)
         VALUES ($1, '081211223344', 'Blok C1', '081299990000', 'Kunjungan', 'Tamu Warga Nonaktif', $2)
         RETURNING *`,
        ['Tamu X', hostWargaInactive.id]
      );
      const inactVisitor = insRes.rows[0];
      createdVisitorIds.push(inactVisitor.id);

      interceptedMessages = [];
      const inactRes = await sendVisitorArrivalPushNotification(inactVisitor);
      assert(inactRes.skipped === true, 'Dispatch to inactive host must be skipped');
      assert(inactRes.reason === 'inactive_or_missing_user', `Expected reason 'inactive_or_missing_user', got: ${inactRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent for inactive host');
      console.log('   OK — Warga tujuan nonaktif berhasil dilewati tanpa salah sasaran.\n');
    }

    // 7. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)
    console.log('6. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)...');
    {
      const insRes = await pool.query(
        `INSERT INTO visitors (nama_tamu, no_hp_tamu, blok_tujuan, no_hp_tujuan, tipe_keperluan, detail_keperluan, created_by)
         VALUES ($1, '081211223344', 'Blok B3', '081298765432', 'Kunjungan', 'Tamu Concurrent Test', $2)
         RETURNING *`,
        ['Tamu Concurrency', hostWargaActive.id]
      );
      const concVisitor = insRes.rows[0];
      createdVisitorIds.push(concVisitor.id);

      interceptedMessages = [];
      const results = await Promise.all([
        sendVisitorArrivalPushNotification(concVisitor),
        sendVisitorArrivalPushNotification(concVisitor),
        sendVisitorArrivalPushNotification(concVisitor),
        sendVisitorArrivalPushNotification(concVisitor),
        sendVisitorArrivalPushNotification(concVisitor),
      ]);

      const sentCount = results.filter((r) => r.success === true).length;
      const skippedCount = results.filter((r) => r.skipped === true).length;
      assert(sentCount === 1, `Expected exactly 1 success, got ${sentCount}`);
      assert(skippedCount === 4, `Expected 4 skipped, got ${skippedCount}`);
      assert(interceptedMessages.length === 1, `Expected 1 multicast call, got ${interceptedMessages.length}`);
      console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');
    }

    // 8. Menguji Keandalan & Fail-Safe: FCM Failure TIDAK Membatalkan Registrasi Tamu
    console.log('7. Menguji keandalan: createVisitor tetap sukses saat Firebase error...');
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
        user: hostWargaActive,
        body: {
          nama_tamu: 'Tamu Fail-Safe Test',
          no_hp_tamu: '081299998888',
          blok_tujuan: 'Blok B3 No. 12',
          no_hp_tujuan: '081298765432',
          tipe_keperluan: 'Kunjungan',
          detail_keperluan: 'Uji ketahanan FCM error',
          plat_nomor: 'B 9999 ERR',
          jenis_kendaraan: 'Motor',
        },
      });

      await createVisitor(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      const failVisitor = res.getBody().data;
      createdVisitorIds.push(failVisitor.id);

      // Verifikasi di database baris tetap tersimpan
      const dbCheck = await pool.query('SELECT id, nama_tamu FROM visitors WHERE id = $1', [failVisitor.id]);
      assert(dbCheck.rows.length === 1, 'Baris data tamu harus tetap tersimpan di database');

      console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak registrasi tamu.\n');
    }

    console.log('================================================================');
    console.log('SEMUA 7 SKENARIO INTEGRASI FCM E-VISITOR LULUS 100%!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('❌ PENGUJIAN FCM E-VISITOR GAGAL:', err);
    process.exitCode = 1;
  } finally {
    setMockMessaging(null);
    console.log('Membersihkan database fixture pengujian e-visitor FCM...');
    for (const vId of createdVisitorIds) {
      await pool.query('DELETE FROM visitors WHERE id = $1', [vId]).catch(() => {});
    }
    await pool.query(
      `DELETE FROM user_fcm_tokens WHERE fcm_token IN ($1, $2, $3)`,
      [tokenHostActive, tokenHostInactive, tokenOther]
    ).catch(() => {});
    const userIds = [adminSatpam?.id, hostWargaActive?.id, hostWargaInactive?.id, otherWarga?.id].filter(Boolean);
    if (userIds.length > 0) {
      await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [userIds]).catch(() => {});
    }
    console.log('Database fixture berhasil dibersihkan.');
    await pool.end();
  }
}

if (require.main === module) {
  runVisitorFcmTests();
}

module.exports = { runVisitorFcmTests };
