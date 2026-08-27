require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-emergency-fcm');

const { pool } = require('../src/config/database');
const {
  triggerAlarm,
  dismissAlarm,
  sendEmergencyPushNotification,
} = require('../src/controllers/emergency.controller');
const { setMockMessaging } = require('../src/config/firebase');

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

async function runEmergencyFcmTests() {
  console.log('================================================================');
  console.log('TEST HARDENING IDEMPOTENSI FCM MODUL EMERGENCY (PHASE 1B.3)');
  console.log('================================================================\n');

  let adminUser = null;
  let activeWarga1 = null;
  let activeWarga2 = null;
  let inactiveWarga = null;
  const createdAlertIds = [];

  const tokenActiveWarga1 = `fcm_emerg_tok_w1_${Date.now()}`;
  const tokenActiveWarga2 = `fcm_emerg_tok_w2_${Date.now()}`;
  const tokenInactiveWarga = `fcm_emerg_tok_inact_${Date.now()}`;

  try {
    // 1. Setup database fixtures
    console.log('1. Menyiapkan database fixture (Pelapor, 2 Warga Aktif, 1 Warga Nonaktif)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, alamat, no_hp)
       VALUES ($1, $2, 'admin', true, $3, $4, 'Blok A1 No 5', '081234567890')
       RETURNING id, nama, role, alamat, no_hp`,
      ['Pak RT Ahmad', `admin_emg_${Date.now()}@test.local`, `adm_emg_${Date.now()}`, `3211${Date.now()}`.slice(0, 16)]
    );
    adminUser = adminRes.rows[0];

    const w1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, alamat, no_hp)
       VALUES ($1, $2, 'warga', true, $3, $4, 'Blok B2 No 12', '081298765432')
       RETURNING id, nama, role, alamat, no_hp`,
      ['Budi Santoso', `w1_emg_${Date.now()}@test.local`, `w1_emg_${Date.now()}`, `3212${Date.now()}`.slice(0, 16)]
    );
    activeWarga1 = w1Res.rows[0];

    const w2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, alamat, no_hp)
       VALUES ($1, $2, 'warga', true, $3, $4, 'Blok C3 No 8', '081311223344')
       RETURNING id, nama, role, alamat, no_hp`,
      ['Siti Rahma', `w2_emg_${Date.now()}@test.local`, `w2_emg_${Date.now()}`, `3213${Date.now()}`.slice(0, 16)]
    );
    activeWarga2 = w2Res.rows[0];

    const inactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, alamat, no_hp)
       VALUES ($1, $2, 'warga', false, $3, $4, 'Blok D4 No 1', '081399887766')
       RETURNING id, nama, role, alamat, no_hp`,
      ['Warga Nonaktif', `winact_emg_${Date.now()}@test.local`, `winact_emg_${Date.now()}`, `3214${Date.now()}`.slice(0, 16)]
    );
    inactiveWarga = inactRes.rows[0];

    // Daftarkan token FCM perangkat
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Pixel 8 Pro', true)`,
      [activeWarga1.id, tokenActiveWarga1]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Galaxy S24 Ultra', true)`,
      [activeWarga2.id, tokenActiveWarga2]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Old Device', true)`,
      [inactiveWarga.id, tokenInactiveWarga]
    );

    console.log(`   Pelapor Admin ID: ${adminUser.id}`);
    console.log(`   Active Warga 1: ${activeWarga1.id} (Token: ${tokenActiveWarga1.slice(0, 16)}...)`);
    console.log(`   Active Warga 2: ${activeWarga2.id} (Token: ${tokenActiveWarga2.slice(0, 16)}...)`);
    console.log(`   Inactive Warga: ${inactiveWarga.id} (Token: ${tokenInactiveWarga.slice(0, 16)}...)`);
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Test Payload Structure & Target Resolution
    console.log('2. Menguji struktur payload notifikasi emergency & resolusi target...');
    const capturedMessages = [];
    const mockMessaging = {
      send: async (msg) => {
        capturedMessages.push(msg);
        return 'mock-emergency-msg-id';
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

    // Insert alert baru di database
    const alert1Insert = await pool.query(
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude, status, fcm_dispatch_status)
       VALUES ($1, $2, $3, $4, 'active', 'unsent')
       RETURNING *`,
      [activeWarga1.id, 'Maling masuk rumah lewat jendela belakang!', -6.2088, 106.8456]
    );
    const alert1 = alert1Insert.rows[0];
    createdAlertIds.push(alert1.id);

    const pushRes = await sendEmergencyPushNotification(alert1, activeWarga1);
    assert(pushRes.success === true, 'Push notification emergency harus sukses');
    assert(capturedMessages.length === 1, 'Pesan multicast emergency harus terkirim');

    const sent = capturedMessages[0];
    assert(sent.notification.title.includes('PERINGATAN DARURAT RT!'), 'Judul harus memuat PERINGATAN DARURAT RT!');
    assert(sent.notification.body.includes('Budi Santoso'), 'Body harus memuat nama pelapor');
    assert(sent.notification.body.includes('Blok B2 No 12'), 'Body harus memuat alamat pelapor');
    assert(sent.notification.body.includes('Maling masuk'), 'Body harus memuat pesan kejadian');
    assert(sent.data.entity_type === 'emergency', 'data.entity_type harus "emergency"');
    assert(sent.data.entity_id === String(alert1.id), 'data.entity_id harus string alert ID');
    assert(sent.data.action === 'ALARM_TRIGGERED', 'data.action harus ALARM_TRIGGERED');
    assert(sent.android.priority === 'high', 'Android priority harus high');
    assert(sent.android.collapseKey === 'emergency_alarm', 'Collapse key harus emergency_alarm');
    assert(sent.tokens.includes(tokenActiveWarga1), 'Harus menargetkan token warga aktif 1');
    assert(sent.tokens.includes(tokenActiveWarga2), 'Harus menargetkan token warga aktif 2');
    assert(!sent.tokens.includes(tokenInactiveWarga), 'TIDAK BOLEH menargetkan token warga nonaktif');

    // Verifikasi status persisten di PostgreSQL
    const alert1Status = await pool.query('SELECT fcm_dispatch_status, fcm_dispatched_at, fcm_dispatch_error FROM emergency_alerts WHERE id = $1', [alert1.id]);
    assert(alert1Status.rows[0].fcm_dispatch_status === 'sent', 'Status database harus beralih menjadi "sent"');
    assert(alert1Status.rows[0].fcm_dispatched_at !== null, 'fcm_dispatched_at harus terisi');
    assert(alert1Status.rows[0].fcm_dispatch_error === null, 'fcm_dispatch_error harus null');
    console.log('   OK — Struktur payload dan status database "sent" valid 100%.\n');

    // 3. Test Process Restart Simulation (Durable Idempotency)
    console.log('3. Menguji simulasi Process Restart (Durable DB Idempotency)...');
    // Memanggil dispatch ulang untuk alert yang sudah berstatus 'sent' di DB
    const restartRes = await sendEmergencyPushNotification(alert1, activeWarga1);
    assert(restartRes.skipped === true, 'Pengiriman ulang harus diskip');
    assert(restartRes.reason === 'already_sent', 'Alasan penolakan harus "already_sent"');
    assert(capturedMessages.length === 1, 'Pesan FCM tidak boleh bertambah');
    console.log('   OK — Status "sent" di database bertahan dan mencegah siaran ganda pasca-restart.\n');

    // 4. Test Concurrent Dispatch Race Condition Guard
    console.log('4. Menguji Race Condition Guard pada pengiriman concurrent / serentak...');
    const alert2Insert = await pool.query(
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude, status, fcm_dispatch_status)
       VALUES ($1, $2, $3, $4, 'active', 'unsent')
       RETURNING *`,
      [activeWarga2.id, 'Kebocoran gas LPG di Blok C3!', -6.2090, 106.8450]
    );
    const alert2 = alert2Insert.rows[0];
    createdAlertIds.push(alert2.id);

    capturedMessages.length = 0;
    // Jalankan 5 dispatch bersamaan untuk alert yang sama
    const concurrentDispatches = await Promise.all([
      sendEmergencyPushNotification(alert2, activeWarga2),
      sendEmergencyPushNotification(alert2, activeWarga2),
      sendEmergencyPushNotification(alert2, activeWarga2),
      sendEmergencyPushNotification(alert2, activeWarga2),
      sendEmergencyPushNotification(alert2, activeWarga2),
    ]);

    const successfulDispatches = concurrentDispatches.filter((r) => r.success === true);
    const skippedDispatches = concurrentDispatches.filter((r) => r.skipped === true);

    assert(successfulDispatches.length === 1, 'Tepat SATU dispatch yang boleh berhasil');
    assert(skippedDispatches.length === 4, 'Empat dispatch lainnya harus diskip (kalah klaim atomik)');
    assert(capturedMessages.length === 1, 'Tepat SATU pesan multicast yang terkirim ke FCM');
    console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');

    // 5. Test FCM Failure Handling (Status transitions to 'failed', retry allowed)
    console.log('5. Menguji penanganan kegagalan FCM & transisi status "failed"...');
    const alert3Insert = await pool.query(
      `INSERT INTO emergency_alerts (user_id, message, status, fcm_dispatch_status)
       VALUES ($1, $2, 'active', 'unsent')
       RETURNING *`,
      [adminUser.id, 'Gangguan Listrik dan Percikan Api Gardu']
    );
    const alert3 = alert3Insert.rows[0];
    createdAlertIds.push(alert3.id);

    const brokenMockMessaging = {
      send: async () => {
        throw new Error('FCM Gateway Timeout 504');
      },
      sendEachForMulticast: async () => {
        throw new Error('FCM Gateway Timeout 504');
      },
    };
    setMockMessaging(brokenMockMessaging);

    const failRes = await sendEmergencyPushNotification(alert3, adminUser);
    assert(failRes.error !== undefined || failRes.success === false, 'Dispatch harus melaporkan kegagalan');

    const alert3FailedStatus = await pool.query(
      'SELECT fcm_dispatch_status, fcm_dispatch_error FROM emergency_alerts WHERE id = $1',
      [alert3.id]
    );
    assert(alert3FailedStatus.rows[0].fcm_dispatch_status === 'failed', 'Status harus menjadi "failed"');
    assert(alert3FailedStatus.rows[0].fcm_dispatch_error.includes('504'), 'Error message harus tersimpan di fcm_dispatch_error');
    console.log('   OK — Status gagal tersimpan sebagai "failed" dan tidak ditandai sukses prematur.\n');

    // 6. Test Retry Mechanism After Failure (Transitions 'failed' -> 'pending' -> 'sent')
    console.log('6. Menguji mekanisme Retry setelah kegagalan FCM...');
    setMockMessaging(mockMessaging);
    capturedMessages.length = 0;

    const retryRes = await sendEmergencyPushNotification(alert3, adminUser);
    assert(retryRes.success === true, 'Retry setelah perbaikan koneksi FCM harus sukses');
    assert(capturedMessages.length === 1, 'Pesan FCM terkirim pada percobaan ulang (retry)');

    const alert3RecoveredStatus = await pool.query(
      'SELECT fcm_dispatch_status, fcm_dispatched_at, fcm_dispatch_error FROM emergency_alerts WHERE id = $1',
      [alert3.id]
    );
    assert(alert3RecoveredStatus.rows[0].fcm_dispatch_status === 'sent', 'Status harus berhasil pulih menjadi "sent"');
    assert(alert3RecoveredStatus.rows[0].fcm_dispatch_error === null, 'Error message harus direset menjadi null');

    // Percobaan setelah 'sent' harus kembali diskip (idempoten)
    const postRetryRes = await sendEmergencyPushNotification(alert3, adminUser);
    assert(postRetryRes.skipped === true && postRetryRes.reason === 'already_sent', 'Post-retry dispatch harus diskip');
    console.log('   OK — Retry berhasil memulihkan status ke "sent" dan mengunci idempotensi selanjutnya.\n');

    // 7. Test Non-Blocking Controller Endpoints with FCM
    console.log('7. Menguji triggerAlarm controller & non-blocking behavior...');
    capturedMessages.length = 0;
    const { req: reqTrig, res: resTrig } = mockReqRes({
      user: activeWarga1,
      body: {
        message: 'Banjir masuk ruang tamu!',
        latitude: -6.2088,
        longitude: 106.8456,
        pin: '1234',
      },
    });

    await triggerAlarm(reqTrig, resTrig);
    assert(resTrig.getStatusCode() === 201, 'triggerAlarm harus mengembalikan HTTP 201');
    assert(resTrig.getBody().success === true, 'Response body success harus true');
    const createdAlertId = resTrig.getBody().data.alert.id;
    createdAlertIds.push(createdAlertId);

    // Tunggu background async dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Push notification FCM harus terpicu saat triggerAlarm');
    console.log(`   Alarm #${createdAlertId} berhasil dipicu dan disiarkan via FCM.`);
    console.log('   OK — Controller triggerAlarm terintegrasi secara non-blocking.\n');

    // 8. Test No Push Notification on Alarm Dismissal
    console.log('8. Menguji dismissAlarm TIDAK mengirim push notification darurat baru...');
    capturedMessages.length = 0;

    const { req: reqDismiss, res: resDismiss } = mockReqRes({
      user: adminUser,
      params: { id: createdAlertId },
      body: { pin: '1234' },
    });

    await dismissAlarm(reqDismiss, resDismiss);
    assert(resDismiss.getStatusCode() === 200, 'dismissAlarm harus HTTP 200');
    assert(capturedMessages.length === 0, 'Penutupan alarm TIDAK BOLEH memicu push notification emergency');
    console.log('   OK — Penutupan alarm tidak mengirim push notification.\n');

    console.log('================================================================');
    console.log('SEMUA 8 SKENARIO HARDENING FCM EMERGENCY LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);

    // Beri jeda kecil agar operasi background selesai sebelum cleanup
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Cleanup fixtures
    console.log('Membersihkan database fixture pengujian emergency FCM...');
    for (const alertId of createdAlertIds) {
      await pool.query('DELETE FROM emergency_alerts WHERE id = $1', [alertId]);
    }
    if (adminUser?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [adminUser.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [adminUser.id]);
    }
    if (activeWarga1?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [activeWarga1.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [activeWarga1.id]);
    }
    if (activeWarga2?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [activeWarga2.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [activeWarga2.id]);
    }
    if (inactiveWarga?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [inactiveWarga.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [inactiveWarga.id]);
    }
    console.log('Database fixture berhasil dibersihkan.\n');
    await pool.end();
  }
}

if (require.main === module) {
  runEmergencyFcmTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST HARDENING EMERGENCY FCM GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runEmergencyFcmTests };
