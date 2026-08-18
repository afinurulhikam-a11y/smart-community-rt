require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-complaint-fcm');

const { pool } = require('./src/config/database');
const {
  createComplaint,
  updateComplaintStatus,
  sendNewComplaintPushNotification,
  sendComplaintResponsePushNotification,
} = require('./src/controllers/complaint.controller');
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

async function runComplaintFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL PENGADUAN (PHASE 2A.1)');
  console.log('================================================================\n');

  let adminPengurus = null;
  let ketuaRtPengurus = null;
  let pelaporWarga = null;
  let otherWarga = null;
  let inactivePengurus = null;
  const createdComplaintIds = [];

  const tokenAdmin = `fcm_cpl_admin_${Date.now()}`;
  const tokenKetuaRt = `fcm_cpl_ketuart_${Date.now()}`;
  const tokenPelapor = `fcm_cpl_pelapor_${Date.now()}`;
  const tokenOtherWarga = `fcm_cpl_other_${Date.now()}`;
  const tokenInactivePengurus = `fcm_cpl_inact_${Date.now()}`;

  try {
    // 1. Setup isolated database fixtures
    console.log('1. Menyiapkan database fixture (2 Pengurus Aktif, 1 Pengurus Nonaktif, 1 Pelapor, 1 Warga Lain)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin RT Pusat', `admin_cpl_${Date.now()}@test.local`, `adm_cpl_${Date.now()}`, `3221${Date.now()}`.slice(0, 16)]
    );
    adminPengurus = adminRes.rows[0];

    const krtRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'ketua_rt', true, $3, $4)
       RETURNING id, nama, role`,
      ['Pak Ketua RT', `krt_cpl_${Date.now()}@test.local`, `krt_cpl_${Date.now()}`, `3222${Date.now()}`.slice(0, 16)]
    );
    ketuaRtPengurus = krtRes.rows[0];

    const inactPengurusRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'sekretaris', false, $3, $4)
       RETURNING id, nama, role`,
      ['Sekretaris Nonaktif', `inact_pgr_${Date.now()}@test.local`, `inact_pgr_${Date.now()}`, `3223${Date.now()}`.slice(0, 16)]
    );
    inactivePengurus = inactPengurusRes.rows[0];

    const pelaporRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Ahmad Warga Pelapor', `pelapor_${Date.now()}@test.local`, `pelapor_${Date.now()}`, `3224${Date.now()}`.slice(0, 16)]
    );
    pelaporWarga = pelaporRes.rows[0];

    const otherRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Budi Warga Lain', `other_${Date.now()}@test.local`, `other_${Date.now()}`, `3225${Date.now()}`.slice(0, 16)]
    );
    otherWarga = otherRes.rows[0];

    // Daftarkan token FCM perangkat
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Admin Phone', true)`,
      [adminPengurus.id, tokenAdmin]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Ketua RT Tablet', true)`,
      [ketuaRtPengurus.id, tokenKetuaRt]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Inactive Device', true)`,
      [inactivePengurus.id, tokenInactivePengurus]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Pelapor Phone', true)`,
      [pelaporWarga.id, tokenPelapor]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Other Warga Phone', true)`,
      [otherWarga.id, tokenOtherWarga]
    );

    console.log(`   Admin Pengurus ID: ${adminPengurus.id}`);
    console.log(`   Ketua RT ID: ${ketuaRtPengurus.id}`);
    console.log(`   Pelapor Warga ID: ${pelaporWarga.id}`);
    console.log(`   Other Warga ID: ${otherWarga.id}`);
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Setup Mock Messaging
    const capturedMessages = [];
    const mockMessaging = {
      send: async (msg) => {
        capturedMessages.push(msg);
        return 'mock-complaint-msg-id';
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

    // 3. Test Event 1: New Complaint -> Push to Pengurus Active Only
    console.log('2. Menguji Event 1: Pengaduan Baru -> Push Notification ke Seluruh Pengurus Aktif...');
    const { req: reqCreate, res: resCreate } = mockReqRes({
      user: pelaporWarga,
      body: {
        judul: 'Lampu Jalan Gang Mawar Mati',
        deskripsi: 'Lampu PJU di depan rumah no 14 padam sejak kemarin malam.',
        kategori: 'Fasilitas Umum',
      },
    });

    await createComplaint(reqCreate, resCreate);
    assert(resCreate.getStatusCode() === 201, 'createComplaint harus HTTP 201');
    assert(resCreate.getBody().success === true, 'Response body success harus true');
    const createdComplaint = resCreate.getBody().data;
    createdComplaintIds.push(createdComplaint.id);

    // Tunggu background async non-blocking dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM ke pengurus harus terkirim');

    const newMsg = capturedMessages[0];
    assert(newMsg.notification.title.includes(createdComplaint.kode_tiket), 'Judul harus memuat kode tiket pengaduan');
    assert(newMsg.notification.body.includes('Lampu Jalan Gang Mawar Mati'), 'Body harus memuat judul pengaduan');
    assert(newMsg.data.entity_type === 'complaint', 'data.entity_type harus "complaint"');
    assert(newMsg.data.entity_id === String(createdComplaint.id), 'data.entity_id harus string ID');
    assert(newMsg.data.action === 'NEW_COMPLAINT', 'data.action harus NEW_COMPLAINT');
    assert(newMsg.tokens.includes(tokenAdmin), 'Harus menargetkan token Admin Pengurus');
    assert(newMsg.tokens.includes(tokenKetuaRt), 'Harus menargetkan token Ketua RT');
    assert(!newMsg.tokens.includes(tokenPelapor), 'TIDAK BOLEH menargetkan pelapor (pelapor adalah pembuat)');
    assert(!newMsg.tokens.includes(tokenOtherWarga), 'TIDAK BOLEH menargetkan warga biasa');
    assert(!newMsg.tokens.includes(tokenInactivePengurus), 'TIDAK BOLEH menargetkan pengurus nonaktif');
    console.log('   OK — Notifikasi pengaduan baru berhasil menargetkan pengurus aktif dengan payload akurat.\n');

    // 4. Test Duplicate Dispatch Prevention for New Complaint
    console.log('3. Menguji pencegahan duplikasi pengiriman untuk event Pengaduan Baru...');
    const duplicateNewRes = await sendNewComplaintPushNotification(createdComplaint, pelaporWarga);
    assert(duplicateNewRes.skipped === true, 'Pengiriman kedua untuk pengaduan baru yang sama harus diskip');
    assert(duplicateNewRes.reason === 'already_sent', 'Alasan penolakan harus already_sent');
    assert(capturedMessages.length === 1, 'Pesan FCM tidak boleh bertambah');
    console.log('   OK — Idempotency guard berhasil mencegah siaran ganda pada pengaduan baru.\n');

    // 5. Test Event 2: Complaint Responded / Status Update -> Push to Complainant Only
    console.log('4. Menguji Event 2: Pengurus Menanggapi Pengaduan -> Push Notification ke Pelapor...');
    capturedMessages.length = 0;

    const { req: reqUpdate, res: resUpdate } = mockReqRes({
      user: adminPengurus,
      params: { id: createdComplaint.id },
      body: {
        status: 'Diproses',
        response: 'Petugas PLN / PJU RT sudah dihubungi untuk perbaikan hari ini pukul 14.00 WIB.',
      },
    });

    await updateComplaintStatus(reqUpdate, resUpdate);
    assert(resUpdate.getStatusCode() === 200, 'updateComplaintStatus harus HTTP 200');
    assert(resUpdate.getBody().success === true, 'Response body success harus true');

    // Tunggu background async dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM ke pelapor harus terkirim');

    const replyMsg = capturedMessages[0];
    assert(replyMsg.notification.title.includes(createdComplaint.kode_tiket), 'Judul harus memuat kode tiket');
    assert(replyMsg.notification.title.includes('Diproses'), 'Judul harus memuat status "Diproses"');
    assert(replyMsg.notification.body.includes('Petugas PLN'), 'Body harus memuat teks tanggapan pengurus');
    assert(replyMsg.data.entity_type === 'complaint', 'data.entity_type harus "complaint"');
    assert(replyMsg.data.action === 'COMPLAINT_REPLIED', 'data.action harus COMPLAINT_REPLIED');
    assert(replyMsg.data.status === 'Diproses', 'data.status harus Diproses');
    assert(replyMsg.android.priority === 'high', 'Priority tanggapan harus high');
    const targetToken = replyMsg.token || replyMsg.tokens?.[0];
    assert(targetToken === tokenPelapor, 'Target harus token milik pelapor');
    assert(targetToken !== tokenAdmin, 'TIDAK BOLEH menargetkan admin');
    assert(targetToken !== tokenOtherWarga, 'TIDAK BOLEH menargetkan warga lain');
    console.log('   OK — Tanggapan pengaduan berhasil dikirim secara eksklusif ke perangkat pelapor.\n');

    // 6. Test No Push When Update Has No Change / Duplicate Status
    console.log('5. Menguji pemanggilan update tanpa perubahan data TIDAK memicu push notification...');
    const duplicateReplyRes = await sendComplaintResponsePushNotification({
      id: createdComplaint.id,
      user_id: pelaporWarga.id,
      kode_tiket: createdComplaint.kode_tiket,
      status: 'Diproses',
      response: 'Petugas PLN / PJU RT sudah dihubungi untuk perbaikan hari ini pukul 14.00 WIB.',
    });
    assert(duplicateReplyRes.skipped === true, 'Update tanpa perubahan status & tanggapan harus diskip');
    assert(duplicateReplyRes.reason === 'no_change_or_duplicate', 'Alasan penolakan harus no_change_or_duplicate');
    assert(capturedMessages.length === 1, 'Tidak boleh ada pesan FCM baru yang dikirim');
    console.log('   OK — Idempotency signature berhasil mendeteksi dan mencegah push berulang.\n');

    // 7. Test FCM Failure Non-Blocking Resilience (create & update remain successful)
    console.log('6. Menguji keandalan: createComplaint dan updateComplaintStatus tetap sukses saat Firebase error...');
    const brokenMockMessaging = {
      send: async () => {
        throw new Error('Firebase Service Unavailable');
      },
      sendEachForMulticast: async () => {
        throw new Error('Firebase Service Unavailable');
      },
    };
    setMockMessaging(brokenMockMessaging);

    const { req: reqCreateBroken, res: resCreateBroken } = mockReqRes({
      user: pelaporWarga,
      body: {
        judul: 'Saluran Air Mampet Saat Hujan',
        deskripsi: 'Air meluap ke jalan.',
      },
    });

    await createComplaint(reqCreateBroken, resCreateBroken);
    assert(resCreateBroken.getStatusCode() === 201, 'createComplaint WAJIB tetap HTTP 201 meski FCM error');
    assert(resCreateBroken.getBody().success === true, 'Response body WAJIB tetap success: true');
    const brokenComplaintId = resCreateBroken.getBody().data.id;
    createdComplaintIds.push(brokenComplaintId);

    // Verifikasi data tersimpan utuh di database PostgreSQL
    const dbCheck = await pool.query('SELECT id, judul FROM complaints WHERE id = $1', [brokenComplaintId]);
    assert(dbCheck.rows.length === 1, 'Data pengaduan harus tersimpan utuh di database');
    console.log(`   Pengaduan #${brokenComplaintId} berhasil dibuat dan tersimpan di DB.`);

    // Update status saat FCM error
    const { req: reqUpdateBroken, res: resUpdateBroken } = mockReqRes({
      user: adminPengurus,
      params: { id: brokenComplaintId },
      body: {
        status: 'Diproses',
        response: 'Sedang dibersihkan oleh petugas kebersihan.',
      },
    });

    await updateComplaintStatus(reqUpdateBroken, resUpdateBroken);
    assert(resUpdateBroken.getStatusCode() === 200, 'updateComplaintStatus WAJIB tetap HTTP 200 meski FCM error');
    assert(resUpdateBroken.getBody().success === true, 'Response body WAJIB tetap success: true');

    const dbCheckUpdated = await pool.query('SELECT status, response FROM complaints WHERE id = $1', [brokenComplaintId]);
    assert(dbCheckUpdated.rows[0].status === 'Diproses', 'Status di DB harus tetap berubah menjadi "Diproses"');
    console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak alur pengaduan utama.\n');

    console.log('================================================================');
    console.log('SEMUA 6 SKENARIO INTEGRASI FCM PENGADUAN LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);

    // Beri jeda kecil agar operasi background selesai
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Cleanup fixtures
    console.log('Membersihkan database fixture pengujian pengaduan FCM...');
    for (const cplId of createdComplaintIds) {
      await pool.query('DELETE FROM complaints WHERE id = $1', [cplId]);
    }
    if (adminPengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [adminPengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [adminPengurus.id]);
    }
    if (ketuaRtPengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [ketuaRtPengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [ketuaRtPengurus.id]);
    }
    if (inactivePengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [inactivePengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [inactivePengurus.id]);
    }
    if (pelaporWarga?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [pelaporWarga.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [pelaporWarga.id]);
    }
    if (otherWarga?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [otherWarga.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [otherWarga.id]);
    }
    console.log('Database fixture berhasil dibersihkan.\n');
    await pool.end();
  }
}

if (require.main === module) {
  runComplaintFcmTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST INTEGRASI PENGADUAN FCM GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runComplaintFcmTests };
