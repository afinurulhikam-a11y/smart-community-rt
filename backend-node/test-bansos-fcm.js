require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-bansos-fcm');

const { pool } = require('./src/config/database');
const {
  createBantuanSosial,
  updateBantuanSosial,
  sendBansosStatusPushNotification,
} = require('./src/controllers/bantuan_sosial.controller');
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

async function runBansosFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL BANTUAN SOSIAL (PHASE 2H)');
  console.log('================================================================\n');

  let adminPengurus = null;
  let recipientActive = null;
  let recipientInactive = null;
  let otherCitizen = null;
  const createdBansosIds = [];

  const tokenRecipientActive = `fcm_token_bansos_rec_${Date.now()}`;
  const tokenRecipientInactive = `fcm_token_bansos_recinact_${Date.now()}`;
  const tokenOther = `fcm_token_bansos_other_${Date.now()}`;

  try {
    // 1. Setup database fixture
    console.log('1. Menyiapkan database fixture (Admin, Penerima Bansos Aktif/Nonaktif, FCM Tokens)...');
    const admRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin Bansos', `adminbansos_${Date.now()}@test.local`, `admbansos_${Date.now()}`, `3201${Date.now()}`.slice(0, 16)]
    );
    adminPengurus = admRes.rows[0];

    const recRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Ibu Siti Penerima Bansos', `siti_${Date.now()}@test.local`, `siti_${Date.now()}`, `3202${Date.now()}`.slice(0, 16)]
    );
    recipientActive = recRes.rows[0];

    const inactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', false, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Nonaktif', `inactbansos_${Date.now()}@test.local`, `inactbansos_${Date.now()}`, `3203${Date.now()}`.slice(0, 16)]
    );
    recipientInactive = inactRes.rows[0];

    const otherRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Lain', `wargalainbansos_${Date.now()}@test.local`, `wlbansos_${Date.now()}`, `3204${Date.now()}`.slice(0, 16)]
    );
    otherCitizen = otherRes.rows[0];

    // Daftarkan token FCM
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, is_active)
       VALUES ($1, $2, 'android', true),
              ($3, $4, 'android', false),
              ($5, $6, 'android', true)`,
      [
        recipientActive.id, tokenRecipientActive,
        recipientActive.id, tokenRecipientInactive,
        otherCitizen.id, tokenOther,
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

    // 3. Menguji Event 1: Penetapan Penerima Bansos Baru (Status 'Aktif') -> Push Notification ke Penerima
    console.log('2. Menguji Penetapan Penerima Bansos Baru (Aktif) -> Push Notification ke Penerima...');
    interceptedMessages = [];
    let bansos1 = null;
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminPengurus,
        body: {
          user_id: recipientActive.id,
          jenis_bantuan: 'Program Sembako (BPNT)',
          bentuk_bantuan: 'Non-tunai / barang',
          sumber_bantuan: 'Pemerintah Pusat',
          no_sk: `SK-BPNT-${Date.now()}`,
          tanggal_bantuan: '2026-09-15',
          nominal: 200000,
          keterangan: 'Bantuan sembako tahap September',
        },
      });

      await createBantuanSosial(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      bansos1 = res.getBody().data;
      createdBansosIds.push(bansos1.id);

      // Tunggu background async dispatch
      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];

      assert(msg.notification.title.includes('Bantuan Sosial'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.notification.title.includes('Program Sembako (BPNT)'), `Title must include program name: ${msg.notification.title}`);
      assert(msg.notification.body.includes('Aktif'), `Body must include status: ${msg.notification.body}`);
      assert(msg.data.entity_type === 'bansos', `entity_type mismatch: ${msg.data.entity_type}`);
      assert(msg.data.entity_id === String(bansos1.id), `entity_id mismatch: ${msg.data.entity_id}`);
      assert(msg.data.action === 'BANSOS_STATUS_UPDATE', `action mismatch: ${msg.data.action}`);
      assert(msg.data.nama_program === 'Program Sembako (BPNT)', `nama_program mismatch: ${msg.data.nama_program}`);
      assert(msg.data.status === 'Aktif', `status mismatch: ${msg.data.status}`);
      assert(msg.android.priority === 'normal', `priority mismatch: ${msg.android.priority}`);
      assert(msg.android.collapseKey === `bansos_status_${bansos1.id}`, `collapseKey mismatch: ${msg.android.collapseKey}`);

      // Token verification
      const targetToken = msg.token || msg.tokens?.[0];
      assert(targetToken === tokenRecipientActive, 'Harus memuat token aktif milik penerima manfaat');
      assert(targetToken !== tokenRecipientInactive, 'Token nonaktif TIDAK boleh termuat');
      assert(targetToken !== tokenOther, 'Token warga lain TIDAK boleh termuat');

      // Database status verification
      const dbCheck = await pool.query('SELECT fcm_last_status_dispatch FROM bantuan_sosial WHERE id = $1', [bansos1.id]);
      assert(dbCheck.rows[0].fcm_last_status_dispatch === 'Aktif', `Expected 'Aktif', got: ${dbCheck.rows[0].fcm_last_status_dispatch}`);

      console.log('   OK — Push notification penetapan bansos berhasil dikirim ke penerima manfaat dengan payload valid.\n');
    }

    // 4. Menguji Event 2: Penyaluran Bansos (Status Update menjadi 'Selesai') -> Push Notification ke Penerima
    console.log('3. Menguji Penyaluran Bansos (Update Status -> Selesai) -> Push Notification...');
    interceptedMessages = [];
    {
      const { req, res } = mockReqRes({
        method: 'PUT',
        params: { id: bansos1.id },
        user: adminPengurus,
        body: {
          status: 'Selesai',
          keterangan: 'Bansos telah diserahkan di kantor kelurahan',
        },
      });

      await updateBantuanSosial(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);

      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];

      assert(msg.notification.title.includes('Disalurkan'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.notification.body.includes('selesai disalurkan'), `Body mismatch: ${msg.notification.body}`);
      assert(msg.data.status === 'Selesai', `data.status mismatch: ${msg.data.status}`);

      const dbCheck = await pool.query('SELECT fcm_last_status_dispatch FROM bantuan_sosial WHERE id = $1', [bansos1.id]);
      assert(dbCheck.rows[0].fcm_last_status_dispatch === 'Selesai', `Expected 'Selesai', got: ${dbCheck.rows[0].fcm_last_status_dispatch}`);

      console.log('   OK — Notifikasi penyaluran bansos selesai berhasil dikirim ke penerima.\n');
    }

    // 5. Menguji Pembaruan Non-Status TIDAK Mengirimkan Push Ganda
    console.log('4. Menguji Update Non-Status TIDAK memicu push notification ganda...');
    {
      interceptedMessages = [];
      const { req, res } = mockReqRes({
        method: 'PUT',
        params: { id: bansos1.id },
        user: adminPengurus,
        body: {
          keterangan: 'Catatan tambahan pengurus RT',
        },
      });

      await updateBantuanSosial(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);

      // Beri waktu sejenak dan pastikan tidak ada push terkirim
      await new Promise((resolve) => setTimeout(resolve, 50));
      assert(interceptedMessages.length === 0, 'Update non-status tidak boleh mengirim push notification');
      console.log('   OK — Pembaruan field non-status berhasil dilewati tanpa push ganda.\n');
    }

    // 6. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)
    console.log('5. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)...');
    {
      interceptedMessages = [];
      const latestData = (await pool.query('SELECT * FROM bantuan_sosial WHERE id = $1', [bansos1.id])).rows[0];
      const dupRes = await sendBansosStatusPushNotification(latestData);
      assert(dupRes.skipped === true, 'Duplicate push must be skipped');
      assert(dupRes.reason === 'already_sent_or_unchanged', `Expected reason 'already_sent_or_unchanged', got: ${dupRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent on duplicate trigger');
      console.log('   OK — Idempotency guard berhasil menahan siaran ganda pada status bansos yang sama.\n');
    }

    // 7. Menguji Penerima Nonaktif -> Pengiriman push dilewati secara aman
    console.log('6. Menguji Penerima Bansos Nonaktif -> Pengiriman push dilewati secara aman...');
    {
      const insRes = await pool.query(
        `INSERT INTO bantuan_sosial (user_id, jenis_bantuan, bentuk_bantuan, sumber_bantuan, tanggal_bantuan, nominal, status, created_by)
         VALUES ($1, 'BLT Desa', 'Tunai', 'Pemerintah Desa', '2026-09-01', 300000, 'Aktif', $2)
         RETURNING *`,
        [recipientInactive.id, adminPengurus.id]
      );
      const inactBansos = insRes.rows[0];
      createdBansosIds.push(inactBansos.id);

      interceptedMessages = [];
      const inactRes = await sendBansosStatusPushNotification(inactBansos);
      assert(inactRes.skipped === true, 'Dispatch to inactive recipient must be skipped');
      assert(inactRes.reason === 'inactive_or_missing_user', `Expected reason 'inactive_or_missing_user', got: ${inactRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent for inactive user');
      console.log('   OK — Penerima nonaktif berhasil dilewati tanpa salah sasaran.\n');
    }

    // 8. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)
    console.log('7. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)...');
    {
      const insRes = await pool.query(
        `INSERT INTO bantuan_sosial (user_id, jenis_bantuan, bentuk_bantuan, sumber_bantuan, tanggal_bantuan, nominal, status, created_by)
         VALUES ($1, 'PKH', 'Tunai', 'Pemerintah Pusat', '2026-09-01', 750000, 'Aktif', $2)
         RETURNING *`,
        [recipientActive.id, adminPengurus.id]
      );
      const concBansos = insRes.rows[0];
      createdBansosIds.push(concBansos.id);

      interceptedMessages = [];
      const results = await Promise.all([
        sendBansosStatusPushNotification(concBansos),
        sendBansosStatusPushNotification(concBansos),
        sendBansosStatusPushNotification(concBansos),
        sendBansosStatusPushNotification(concBansos),
        sendBansosStatusPushNotification(concBansos),
      ]);

      const sentCount = results.filter((r) => r.success === true).length;
      const skippedCount = results.filter((r) => r.skipped === true).length;
      assert(sentCount === 1, `Expected exactly 1 success, got ${sentCount}`);
      assert(skippedCount === 4, `Expected 4 skipped, got ${skippedCount}`);
      assert(interceptedMessages.length === 1, `Expected 1 send call, got ${interceptedMessages.length}`);
      console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');
    }

    // 9. Menguji Keandalan & Fail-Safe: FCM Failure TIDAK Membatalkan Operasi Bansos
    console.log('8. Menguji keandalan: createBantuanSosial & update tetap sukses saat Firebase error...');
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
        user: adminPengurus,
        body: {
          user_id: recipientActive.id,
          jenis_bantuan: 'PBI-JK',
          bentuk_bantuan: 'Layanan',
          sumber_bantuan: 'Pemerintah Pusat',
          tanggal_bantuan: '2026-09-20',
          nominal: '',
          keterangan: 'Uji ketahanan FCM error',
        },
      });

      await createBantuanSosial(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      const failBansos = res.getBody().data;
      createdBansosIds.push(failBansos.id);

      // Verifikasi di database baris tetap tersimpan
      const dbCheck = await pool.query('SELECT id, jenis_bantuan FROM bantuan_sosial WHERE id = $1', [failBansos.id]);
      assert(dbCheck.rows.length === 1, 'Baris data bansos harus tetap tersimpan di database');

      console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak pencatatan bantuan sosial.\n');
    }

    console.log('================================================================');
    console.log('SEMUA 8 SKENARIO INTEGRASI FCM BANTUAN SOSIAL LULUS 100%!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('❌ PENGUJIAN FCM BANTUAN SOSIAL GAGAL:', err);
    process.exitCode = 1;
  } finally {
    setMockMessaging(null);
    console.log('Membersihkan database fixture pengujian bansos FCM...');
    for (const bId of createdBansosIds) {
      await pool.query('DELETE FROM bantuan_sosial_log WHERE bantuan_sosial_id = $1', [bId]).catch(() => {});
      await pool.query('DELETE FROM bantuan_sosial WHERE id = $1', [bId]).catch(() => {});
    }
    await pool.query(
      `DELETE FROM user_fcm_tokens WHERE fcm_token IN ($1, $2, $3)`,
      [tokenRecipientActive, tokenRecipientInactive, tokenOther]
    ).catch(() => {});
    const userIds = [adminPengurus?.id, recipientActive?.id, recipientInactive?.id, otherCitizen?.id].filter(Boolean);
    if (userIds.length > 0) {
      await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [userIds]).catch(() => {});
    }
    console.log('Database fixture berhasil dibersihkan.');
    await pool.end();
  }
}

if (require.main === module) {
  runBansosFcmTests();
}

module.exports = { runBansosFcmTests };
