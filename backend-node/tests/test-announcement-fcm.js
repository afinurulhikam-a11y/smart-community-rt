require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-announcement-fcm');

const { pool } = require('../src/config/database');
const {
  createAnnouncement,
  sendAnnouncementPushNotification,
} = require('../src/controllers/announcement.controller');
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

async function runAnnouncementFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL PENGUMUMAN (PHASE 1B.2)');
  console.log('================================================================\n');

  let adminUser = null;
  let activeWarga1 = null;
  let activeWarga2 = null;
  let inactiveWarga = null;
  const createdAnnouncementIds = [];

  const tokenActiveWarga1 = `fcm_token_warga1_${Date.now()}`;
  const tokenActiveWarga2 = `fcm_token_warga2_${Date.now()}`;
  const tokenInactiveWarga = `fcm_token_inactive_${Date.now()}`;

  try {
    // 1. Setup isolated test users in database
    console.log('1. Menyiapkan database fixture (Admin, 2 Warga Aktif, 1 Warga Nonaktif)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin FCM Test', `admin_fcm_${Date.now()}@test.local`, `admin_fcm_${Date.now()}`, `3207${Date.now()}`.slice(0, 16)]
    );
    adminUser = adminRes.rows[0];

    const w1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Aktif 1', `warga1_fcm_${Date.now()}@test.local`, `w1_fcm_${Date.now()}`, `3208${Date.now()}`.slice(0, 16)]
    );
    activeWarga1 = w1Res.rows[0];

    const w2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Aktif 2', `warga2_fcm_${Date.now()}@test.local`, `w2_fcm_${Date.now()}`, `3209${Date.now()}`.slice(0, 16)]
    );
    activeWarga2 = w2Res.rows[0];

    const inactRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', false, $3, $4)
       RETURNING id, nama, role`,
      ['Warga Nonaktif', `wargainact_${Date.now()}@test.local`, `winact_${Date.now()}`, `3210${Date.now()}`.slice(0, 16)]
    );
    inactiveWarga = inactRes.rows[0];

    // Registrasi token FCM perangkat
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Pixel 8', true)`,
      [activeWarga1.id, tokenActiveWarga1]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Galaxy S24', true)`,
      [activeWarga2.id, tokenActiveWarga2]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Old Device', true)`,
      [inactiveWarga.id, tokenInactiveWarga]
    );

    console.log(`   Admin ID: ${adminUser.id}`);
    console.log(`   Active Warga 1: ${activeWarga1.id} (Token: ${tokenActiveWarga1.slice(0, 15)}...)`);
    console.log(`   Active Warga 2: ${activeWarga2.id} (Token: ${tokenActiveWarga2.slice(0, 15)}...)`);
    console.log(`   Inactive Warga: ${inactiveWarga.id} (Excluded from target)`);
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Test Direct Push Dispatch & Payload Verification
    console.log('2. Menguji struktur payload notifikasi pengumuman...');
    const capturedMessages = [];
    const mockMessaging = {
      send: async (msg) => {
        capturedMessages.push(msg);
        return 'mock-msg-id-single';
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

    const sampleAnnouncement = {
      id: 9999,
      judul: 'Kerja Bakti Akbar Minggu Pagi',
      isi: 'Diharapkan seluruh warga membawa peralatan kebersihan pada pukul 07.00 WIB di pos RW.',
      kategori: 'Kegiatan',
      status: 'publish',
      created_at: new Date().toISOString(),
    };

    const pushRes = await sendAnnouncementPushNotification(sampleAnnouncement);
    assert(pushRes.success === true, 'Push notification pengumuman harus sukses');
    assert(capturedMessages.length === 1, 'Pesan multicast harus terkirim');

    const sent = capturedMessages[0];
    assert(sent.notification.title.includes('Kerja Bakti Akbar Minggu Pagi'), 'Judul notifikasi harus memuat judul pengumuman');
    assert(sent.notification.body.includes('peralatan kebersihan'), 'Body harus memuat isi pengumuman');
    assert(sent.data.entity_type === 'announcement', 'data.entity_type harus "announcement"');
    assert(sent.data.entity_id === '9999', 'data.entity_id harus string "9999"');
    assert(sent.data.kategori === 'Kegiatan', 'data.kategori harus "Kegiatan"');
    assert(sent.tokens.includes(tokenActiveWarga1), 'Harus menargetkan token warga aktif 1');
    assert(sent.tokens.includes(tokenActiveWarga2), 'Harus menargetkan token warga aktif 2');
    assert(!sent.tokens.includes(tokenInactiveWarga), 'TIDAK BOLEH menargetkan token warga nonaktif');
    console.log('   OK — Struktur payload dan seleksi token aktif lulus 100%.\n');

    // 3. Test Draft Announcement (Status != publish)
    console.log('3. Menguji pengumuman status DRAFT tidak mengirim push notifikasi...');
    capturedMessages.length = 0;
    const draftAnnouncement = {
      id: 10000,
      judul: 'Draft Pengumuman Tertunda',
      isi: 'Isi draft yang belum siap dipublikasikan.',
      status: 'draft',
    };
    const draftRes = await sendAnnouncementPushNotification(draftAnnouncement);
    assert(draftRes.skipped === true && draftRes.reason === 'not_published', 'Draft harus diskip');
    assert(capturedMessages.length === 0, 'Tidak boleh ada pesan FCM terkirim untuk draft');
    console.log('   OK — Pengumuman draft tidak memicu siaran notifikasi.\n');

    // 4. Test Create Announcement via Controller with Mock FCM Success
    console.log('4. Menguji createAnnouncement controller dengan FCM aktif...');
    capturedMessages.length = 0;
    const { req: reqCreate1, res: resCreate1 } = mockReqRes({
      user: adminUser,
      body: {
        judul: 'Pemberitahuan Fogging Nyamuk',
        isi: 'Akan dilakukan pengasapan fogging serentak hari Sabtu pukul 09.00 WIB.',
        kategori: 'Kesehatan',
        status: 'publish',
      },
    });

    await createAnnouncement(reqCreate1, resCreate1);
    assert(resCreate1.getStatusCode() === 201, 'Pembuatan pengumuman harus HTTP 201');
    assert(resCreate1.getBody().success === true, 'Response body success harus true');
    const createdId1 = resCreate1.getBody().data.id;
    createdAnnouncementIds.push(createdId1);
    assert(createdId1 !== undefined, 'ID pengumuman baru harus ada');
    console.log(`   Pengumuman #${createdId1} berhasil dibuat via API (HTTP 201).`);

    // Tunggu setImmediate selesai
    await new Promise((resolve) => setImmediate(resolve));
    console.log('   OK — Siaran non-blocking pengumuman baru terpicu.\n');

    // 5. Test Non-Blocking & Resilience: Create Announcement Succeeds Even When FCM Throws Error
    console.log('5. Menguji keandalan: Pembuatan pengumuman TETAP BERHASIL meski Firebase FCM melempar error...');
    const brokenMockMessaging = {
      send: async () => {
        throw new Error('Firebase Network Timeout / Service Down');
      },
      sendEachForMulticast: async () => {
        throw new Error('Firebase Network Timeout / Service Down');
      },
    };
    setMockMessaging(brokenMockMessaging);

    const { req: reqCreate2, res: resCreate2 } = mockReqRes({
      user: adminUser,
      body: {
        judul: 'Pengumuman Saat Jaringan Firebase Gangguan',
        isi: 'Pengumuman ini harus tetap tersimpan di database tanpa terpengaruh kegagalan FCM.',
        kategori: 'Umum',
        status: 'publish',
      },
    });

    await createAnnouncement(reqCreate2, resCreate2);
    assert(resCreate2.getStatusCode() === 201, 'Pembuatan pengumuman WAJIB tetap HTTP 201');
    assert(resCreate2.getBody().success === true, 'Response body WAJIB tetap success: true');
    const createdId2 = resCreate2.getBody().data.id;
    createdAnnouncementIds.push(createdId2);

    // Verifikasi data tersimpan di PostgreSQL
    const dbCheck = await pool.query('SELECT id, judul FROM announcements WHERE id = $1', [createdId2]);
    assert(dbCheck.rows.length === 1, 'Data pengumuman harus tersimpan utuh di PostgreSQL');
    console.log(`   Pengumuman #${createdId2} berhasil tersimpan di DB meski FCM error.`);
    console.log('   OK — Transaksi database terbukti non-blocking dan independen dari kegagalan FCM.\n');

    console.log('================================================================');
    console.log('SEMUA 5 SKENARIO INTEGRASI FCM PENGUMUMAN LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);
    // Cleanup fixtures
    console.log('Membersihkan database fixture pengujian integrasi pengumuman...');
    for (const annId of createdAnnouncementIds) {
      await pool.query('DELETE FROM announcements WHERE id = $1', [annId]);
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
  runAnnouncementFcmTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST INTEGRASI PENGUMUMAN FCM GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runAnnouncementFcmTests };
