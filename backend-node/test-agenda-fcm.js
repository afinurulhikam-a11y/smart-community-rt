require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-agenda-fcm');

const { pool } = require('./src/config/database');
const {
  createAgenda,
  sendNewAgendaPushNotification,
} = require('./src/controllers/agenda.controller');
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

async function runAgendaFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL AGENDA (PHASE 2D)');
  console.log('================================================================\n');

  let adminUser = null;
  let activeWarga1 = null;
  let activeWarga2 = null;
  let inactiveWarga = null;
  const createdAgendaIds = [];

  const tokenActiveWarga1 = `fcm_token_agenda_w1_${Date.now()}`;
  const tokenActiveWarga2 = `fcm_token_agenda_w2_${Date.now()}`;
  const tokenInactiveWarga = `fcm_token_agenda_inact_${Date.now()}`;

  try {
    // 1. Setup isolated test users & tokens in database
    console.log('1. Menyiapkan database fixture (Admin, 2 Warga Aktif, 1 Warga Nonaktif, Tokens)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin Agenda FCM', `admin_agenda_${Date.now()}@test.local`, `adm_ag_${Date.now()}`, `3207${Date.now()}`.slice(0, 16)]
    );
    adminUser = adminRes.rows[0];

    const w1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Aktif 1', `warga1_agenda_${Date.now()}@test.local`, `w1_ag_${Date.now()}`, `3208${Date.now()}`.slice(0, 16)]
    );
    activeWarga1 = w1Res.rows[0];

    const w2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Aktif 2', `warga2_agenda_${Date.now()}@test.local`, `w2_ag_${Date.now()}`, `3209${Date.now()}`.slice(0, 16)]
    );
    activeWarga2 = w2Res.rows[0];

    const inactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', false, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Nonaktif', `inact_agenda_${Date.now()}@test.local`, `inact_ag_${Date.now()}`, `3210${Date.now()}`.slice(0, 16)]
    );
    inactiveWarga = inactRes.rows[0];

    // Daftarkan token FCM (2 aktif, 1 nonaktif)
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, is_active)
       VALUES ($1, $2, 'android', true),
              ($3, $4, 'android', true),
              ($5, $6, 'android', false)`,
      [
        activeWarga1.id, tokenActiveWarga1,
        activeWarga2.id, tokenActiveWarga2,
        inactiveWarga.id, tokenInactiveWarga,
      ]
    );
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Setup Mock Firebase Messaging
    let interceptedMessages = [];
    const mockMessaging = {
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

    // 3. Menguji Event Agenda Aktif Baru -> Push Notification ke seluruh user aktif
    console.log('2. Menguji Agenda Aktif Baru ("Akan Datang") -> Push Notification ke seluruh user aktif...');
    interceptedMessages = [];
    let activeAgenda = null;

    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminUser,
        body: {
          judul: 'Musyawarah Warga RT 01',
          deskripsi: 'Membahas persiapan HUT RI ke-81',
          tipe: 'Rapat',
          tanggal: '2026-08-25',
          waktu_mulai: '19:30',
          waktu_selesai: '21:30',
          lokasi: 'Balai Warga',
          status: 'Akan Datang',
        },
      });

      await createAgenda(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      activeAgenda = res.getBody().data;
      createdAgendaIds.push(activeAgenda.id);

      // Jalankan helper dispatch push secara langsung untuk memverifikasi payload
      const pushRes = await sendNewAgendaPushNotification(activeAgenda);
      assert(pushRes.success === true, `Expected push success, got: ${JSON.stringify(pushRes)}`);

      // Verifikasi pesan FCM yang terkirim
      assert(interceptedMessages.length === 1, `Expected 1 multicast, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];
      assert(msg.notification.title.includes('Musyawarah Warga RT 01'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.data.entity_type === 'agenda', `entity_type mismatch: ${msg.data.entity_type}`);
      assert(msg.data.entity_id === String(activeAgenda.id), `entity_id mismatch: ${msg.data.entity_id}`);
      assert(msg.data.action === 'NEW_AGENDA', `action mismatch: ${msg.data.action}`);
      assert(msg.data.tanggal === '2026-08-25', `tanggal mismatch: ${msg.data.tanggal}`);
      assert(msg.data.waktu_mulai === '19:30', `waktu_mulai mismatch: ${msg.data.waktu_mulai}`);
      assert(msg.data.lokasi === 'Balai Warga', `lokasi mismatch: ${msg.data.lokasi}`);
      assert(msg.android.priority === 'normal', `priority mismatch: ${msg.android.priority}`);
      assert(msg.android.collapseKey === 'agenda_broadcast', `collapseKey mismatch: ${msg.android.collapseKey}`);

      // Token nonaktif harus dikecualikan
      assert(msg.tokens.includes(tokenActiveWarga1), 'Harus memuat token warga aktif 1');
      assert(msg.tokens.includes(tokenActiveWarga2), 'Harus memuat token warga aktif 2');
      assert(!msg.tokens.includes(tokenInactiveWarga), 'Token user nonaktif / token inactive TIDAK boleh termuat');

      // Verifikasi status database
      const dbCheck = await pool.query('SELECT fcm_dispatch_status FROM agenda WHERE id = $1', [activeAgenda.id]);
      assert(dbCheck.rows[0].fcm_dispatch_status === 'sent', `Expected 'sent', got: ${dbCheck.rows[0].fcm_dispatch_status}`);

      console.log('   OK — Push notification agenda aktif berhasil dikirim ke seluruh warga aktif dengan payload valid.\n');
    }

    // 4. Menguji Agenda Draft / Batal TIDAK Mengirim Push Notification
    console.log('3. Menguji Agenda Draft / Tidak Aktif ("Batal" / "draft") TIDAK mengirim push...');
    interceptedMessages = [];
    let draftAgenda = null;

    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminUser,
        body: {
          judul: 'Lomba Catur Warga (Draf/Batal)',
          deskripsi: 'Masih dalam perencanaan pengurus',
          tipe: 'Kegiatan',
          tanggal: '2026-08-30',
          waktu_mulai: '09:00',
          lokasi: 'Pos Ronda',
          status: 'Batal',
        },
      });

      await createAgenda(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      draftAgenda = res.getBody().data;
      createdAgendaIds.push(draftAgenda.id);

      const pushRes = await sendNewAgendaPushNotification(draftAgenda);
      assert(pushRes.skipped === true, 'Draft/batal agenda must be skipped');
      assert(pushRes.reason === 'agenda_not_active', `Expected reason 'agenda_not_active', got: ${pushRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent for inactive agenda');

      const dbCheck = await pool.query('SELECT fcm_dispatch_status FROM agenda WHERE id = $1', [draftAgenda.id]);
      assert(dbCheck.rows[0].fcm_dispatch_status === 'unsent', `Expected 'unsent', got: ${dbCheck.rows[0].fcm_dispatch_status}`);

      console.log('   OK — Agenda tidak aktif berhasil dilewati tanpa siaran push.\n');
    }

    // 5. Menguji Durable Database Idempotency (Pencegahan siaran ganda)
    console.log('4. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)...');
    {
      interceptedMessages = [];
      const dupRes = await sendNewAgendaPushNotification(activeAgenda);
      assert(dupRes.skipped === true, 'Duplicate push must be skipped');
      assert(dupRes.reason === 'already_sent', `Expected reason 'already_sent', got: ${dupRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent on duplicate trigger');
      console.log('   OK — Idempotency guard berhasil menahan siaran ganda pada agenda yang sudah sent.\n');
    }

    // 6. Menguji Race Condition Guard pada eksekusi konkuren
    console.log('5. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)...');
    {
      // Buat agenda baru yang unsent
      const insRes = await pool.query(
        `INSERT INTO agenda (judul, tanggal, status, fcm_dispatch_status, created_by)
         VALUES ($1, '2026-09-01', 'Akan Datang', 'unsent', $2)
         RETURNING *, tanggal::text AS tanggal`,
        ['Senam Pagi Bersama', adminUser.id]
      );
      const concAgenda = insRes.rows[0];
      createdAgendaIds.push(concAgenda.id);

      interceptedMessages = [];
      const results = await Promise.all([
        sendNewAgendaPushNotification(concAgenda),
        sendNewAgendaPushNotification(concAgenda),
        sendNewAgendaPushNotification(concAgenda),
        sendNewAgendaPushNotification(concAgenda),
        sendNewAgendaPushNotification(concAgenda),
      ]);

      const sentCount = results.filter((r) => r.success === true).length;
      const skippedCount = results.filter((r) => r.skipped === true).length;
      assert(sentCount === 1, `Expected exactly 1 success, got ${sentCount}`);
      assert(skippedCount === 4, `Expected 4 skipped, got ${skippedCount}`);
      assert(interceptedMessages.length === 1, `Expected 1 multicast call, got ${interceptedMessages.length}`);
      console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');
    }

    // 7. Menguji Keandalan & Fail-Safe: createAgenda tetap sukses saat Firebase Error
    console.log('6. Menguji keandalan: createAgenda tetap sukses saat Firebase error...');
    {
      setMockMessaging({
        sendEachForMulticast: async () => {
          throw new Error('Firebase Unavailable (Simulated Error)');
        },
      });

      const { req, res } = mockReqRes({
        method: 'POST',
        user: adminUser,
        body: {
          judul: 'Kerja Bakti Pasca Badai',
          deskripsi: 'Pembersihan ranting pohon di jalan utama',
          tipe: 'Kegiatan',
          tanggal: '2026-09-05',
          status: 'Akan Datang',
        },
      });

      await createAgenda(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      const failAgenda = res.getBody().data;
      createdAgendaIds.push(failAgenda.id);

      // Tunggu background async dispatch selesai memproses error
      await new Promise((resolve) => setTimeout(resolve, 60));

      const dbCheck = await pool.query('SELECT fcm_dispatch_status FROM agenda WHERE id = $1', [failAgenda.id]);
      assert(dbCheck.rows[0].fcm_dispatch_status === 'failed', `Expected 'failed', got: ${dbCheck.rows[0].fcm_dispatch_status}`);

      console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak pembuatan agenda.\n');
    }

    console.log('================================================================');
    console.log('SEMUA 6 SKENARIO INTEGRASI FCM AGENDA LULUS 100%!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('❌ PENGUJIAN FCM AGENDA GAGAL:', err);
    process.exitCode = 1;
  } finally {
    setMockMessaging(null);
    console.log('Membersihkan database fixture pengujian agenda FCM...');
    for (const agId of createdAgendaIds) {
      await pool.query('DELETE FROM agenda WHERE id = $1', [agId]).catch(() => {});
    }
    await pool.query(
      `DELETE FROM user_fcm_tokens WHERE fcm_token IN ($1, $2, $3)`,
      [tokenActiveWarga1, tokenActiveWarga2, tokenInactiveWarga]
    ).catch(() => {});
    const userIds = [adminUser?.id, activeWarga1?.id, activeWarga2?.id, inactiveWarga?.id].filter(Boolean);
    if (userIds.length > 0) {
      await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [userIds]).catch(() => {});
    }
    console.log('Database fixture berhasil dibersihkan.');
    await pool.end();
  }
}

if (require.main === module) {
  runAgendaFcmTests();
}

module.exports = { runAgendaFcmTests };
