require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-letter-fcm');

const { pool } = require('../src/config/database');
const {
  createLetter,
  updateLetterStatus,
  sendNewLetterPushNotification,
  sendLetterStatusPushNotification,
} = require('../src/controllers/letter.controller');
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

async function runLetterFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL SURAT (PHASE 2A.2)');
  console.log('================================================================\n');

  let adminPengurus = null;
  let sekretarisPengurus = null;
  let pemohonWarga = null;
  let otherWarga = null;
  let inactivePengurus = null;
  const createdLetterIds = [];

  const tokenAdmin = `fcm_ltr_admin_${Date.now()}`;
  const tokenSekretaris = `fcm_ltr_sekre_${Date.now()}`;
  const tokenPemohon = `fcm_ltr_pemohon_${Date.now()}`;
  const tokenOtherWarga = `fcm_ltr_other_${Date.now()}`;
  const tokenInactivePengurus = `fcm_ltr_inact_${Date.now()}`;

  try {
    // 1. Setup isolated database fixtures
    console.log('1. Menyiapkan database fixture (2 Pengurus Aktif, 1 Pengurus Nonaktif, 1 Pemohon, 1 Warga Lain)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin RT Surat', `admin_ltr_${Date.now()}@test.local`, `adm_ltr_${Date.now()}`, `3231${Date.now()}`.slice(0, 16)]
    );
    adminPengurus = adminRes.rows[0];

    const sekreRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'sekretaris', true, $3, $4)
       RETURNING id, nama, role`,
      ['Sekretaris RT', `sekre_ltr_${Date.now()}@test.local`, `sekre_ltr_${Date.now()}`, `3232${Date.now()}`.slice(0, 16)]
    );
    sekretarisPengurus = sekreRes.rows[0];

    const inactPengurusRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'bendahara', false, $3, $4)
       RETURNING id, nama, role`,
      ['Bendahara Nonaktif', `inact_ltr_${Date.now()}@test.local`, `inact_ltr_${Date.now()}`, `3233${Date.now()}`.slice(0, 16)]
    );
    inactivePengurus = inactPengurusRes.rows[0];

    const pemohonRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Siti Warga Pemohon', `pemohon_${Date.now()}@test.local`, `pemohon_${Date.now()}`, `3234${Date.now()}`.slice(0, 16)]
    );
    pemohonWarga = pemohonRes.rows[0];

    const otherRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Dedi Warga Lain', `other_ltr_${Date.now()}@test.local`, `other_ltr_${Date.now()}`, `3235${Date.now()}`.slice(0, 16)]
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
       VALUES ($1, $2, 'android', 'Sekretaris Tablet', true)`,
      [sekretarisPengurus.id, tokenSekretaris]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Inactive Device', true)`,
      [inactivePengurus.id, tokenInactivePengurus]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Pemohon Phone', true)`,
      [pemohonWarga.id, tokenPemohon]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Other Warga Phone', true)`,
      [otherWarga.id, tokenOtherWarga]
    );

    console.log(`   Admin Pengurus ID: ${adminPengurus.id}`);
    console.log(`   Sekretaris RT ID: ${sekretarisPengurus.id}`);
    console.log(`   Pemohon Warga ID: ${pemohonWarga.id}`);
    console.log(`   Other Warga ID: ${otherWarga.id}`);
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Setup Mock Messaging
    const capturedMessages = [];
    const mockMessaging = {
      send: async (msg) => {
        capturedMessages.push(msg);
        return 'mock-letter-msg-id';
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

    // 3. Test Event 1: New Letter Request -> Push to Pengurus Active Only
    console.log('2. Menguji Event 1: Permohonan Surat Baru -> Push Notification ke Seluruh Pengurus Aktif...');
    const { req: reqCreate, res: resCreate } = mockReqRes({
      user: pemohonWarga,
      body: {
        jenis_surat: 'Surat Keterangan Domisili',
        keperluan: 'Pembuatan rekening bank baru di kantor cabang.',
      },
    });

    await createLetter(reqCreate, resCreate);
    assert(resCreate.getStatusCode() === 201, 'createLetter harus HTTP 201');
    assert(resCreate.getBody().success === true, 'Response body success harus true');
    const createdLetter = resCreate.getBody().data;
    createdLetterIds.push(createdLetter.id);

    // Tunggu background async non-blocking dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM ke pengurus harus terkirim');

    const newMsg = capturedMessages[0];
    assert(newMsg.notification.title.includes('Permohonan Surat Baru'), 'Judul harus memuat "Permohonan Surat Baru"');
    assert(newMsg.notification.body.includes('Surat Keterangan Domisili'), 'Body harus memuat jenis surat');
    assert(newMsg.data.entity_type === 'letter', 'data.entity_type harus "letter"');
    assert(newMsg.data.entity_id === String(createdLetter.id), 'data.entity_id harus string ID');
    assert(newMsg.data.action === 'NEW_LETTER_REQUEST', 'data.action harus NEW_LETTER_REQUEST');
    assert(newMsg.tokens.includes(tokenAdmin), 'Harus menargetkan token Admin Pengurus');
    assert(newMsg.tokens.includes(tokenSekretaris), 'Harus menargetkan token Sekretaris');
    assert(!newMsg.tokens.includes(tokenPemohon), 'TIDAK BOLEH menargetkan pemohon');
    assert(!newMsg.tokens.includes(tokenOtherWarga), 'TIDAK BOLEH menargetkan warga lain');
    assert(!newMsg.tokens.includes(tokenInactivePengurus), 'TIDAK BOLEH menargetkan pengurus nonaktif');
    console.log('   OK — Notifikasi permohonan surat baru berhasil menargetkan pengurus aktif dengan payload akurat.\n');

    // 4. Test Duplicate Dispatch Prevention for New Letter
    console.log('3. Menguji pencegahan duplikasi pengiriman untuk event Permohonan Surat Baru...');
    const duplicateNewRes = await sendNewLetterPushNotification(createdLetter, pemohonWarga);
    assert(duplicateNewRes.skipped === true, 'Pengiriman kedua untuk permohonan surat yang sama harus diskip');
    assert(duplicateNewRes.reason === 'already_sent', 'Alasan penolakan harus already_sent');
    assert(capturedMessages.length === 1, 'Pesan FCM tidak boleh bertambah');
    console.log('   OK — Idempotency guard berhasil mencegah siaran ganda pada permohonan surat baru.\n');

    // 5. Test Event 2a: Letter Approved -> Push to Applicant Only
    console.log('4. Menguji Event 2a: Surat Disetujui -> Push Notification ke Pemohon...');
    capturedMessages.length = 0;

    const { req: reqApprove, res: resApprove } = mockReqRes({
      user: adminPengurus,
      params: { id: createdLetter.id },
      body: {
        status: 'disetujui',
        response_note: 'Surat sudah ditandatangani dan siap diambil.',
      },
    });

    await updateLetterStatus(reqApprove, resApprove);
    assert(resApprove.getStatusCode() === 200, 'updateLetterStatus harus HTTP 200');
    assert(resApprove.getBody().success === true, 'Response body success harus true');

    // Tunggu background async dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM ke pemohon harus terkirim');

    const approveMsg = capturedMessages[0];
    assert(approveMsg.notification.title.includes('Disetujui'), 'Judul harus memuat status "Disetujui"');
    assert(approveMsg.notification.body.includes('disetujui'), 'Body harus memuat informasi persetujuan');
    assert(approveMsg.data.entity_type === 'letter', 'data.entity_type harus "letter"');
    assert(approveMsg.data.action === 'LETTER_STATUS_CHANGED', 'data.action harus LETTER_STATUS_CHANGED');
    assert(approveMsg.data.status === 'disetujui', 'data.status harus disetujui');
    assert(approveMsg.android.priority === 'high', 'Priority status surat harus high');
    const targetTokenApprove = approveMsg.token || approveMsg.tokens?.[0];
    assert(targetTokenApprove === tokenPemohon, 'Target harus token milik pemohon');
    assert(targetTokenApprove !== tokenAdmin, 'TIDAK BOLEH menargetkan admin');
    assert(targetTokenApprove !== tokenOtherWarga, 'TIDAK BOLEH menargetkan warga lain');
    console.log('   OK — Notifikasi persetujuan surat berhasil dikirim ke perangkat pemohon.\n');

    // 6. Test No Push When Update Has No Change
    console.log('5. Menguji update tanpa perubahan status TIDAK memicu push notification...');
    const duplicateApproveRes = await sendLetterStatusPushNotification({
      id: createdLetter.id,
      user_id: pemohonWarga.id,
      jenis_surat: createdLetter.jenis_surat,
      status: 'disetujui',
      response_note: 'Surat sudah ditandatangani dan siap diambil.',
    });
    assert(duplicateApproveRes.skipped === true, 'Update tanpa perubahan status & note harus diskip');
    assert(duplicateApproveRes.reason === 'no_change_or_duplicate', 'Alasan penolakan harus no_change_or_duplicate');
    assert(capturedMessages.length === 1, 'Tidak boleh ada pesan FCM baru yang dikirim');
    console.log('   OK — Idempotency signature berhasil mendeteksi dan mencegah push berulang.\n');

    // 7. Test Event 2b: Letter Rejected -> Push to Applicant with Rejection Note
    console.log('6. Menguji Event 2b: Surat Ditolak -> Push Notification ke Pemohon dengan Catatan Penolakan...');
    capturedMessages.length = 0;

    const { req: reqReject, res: resReject } = mockReqRes({
      user: adminPengurus,
      params: { id: createdLetter.id },
      body: {
        status: 'ditolak',
        response_note: 'Kartu Keluarga belum diperbarui.',
      },
    });

    await updateLetterStatus(reqReject, resReject);
    assert(resReject.getStatusCode() === 200, 'updateLetterStatus harus HTTP 200');

    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM penolakan harus terkirim');

    const rejectMsg = capturedMessages[0];
    assert(rejectMsg.notification.title.includes('Ditolak'), 'Judul harus memuat "Ditolak"');
    assert(rejectMsg.notification.body.includes('Kartu Keluarga belum diperbarui'), 'Body harus memuat catatan penolakan');
    assert(rejectMsg.data.status === 'ditolak', 'data.status harus ditolak');
    const targetTokenReject = rejectMsg.token || rejectMsg.tokens?.[0];
    assert(targetTokenReject === tokenPemohon, 'Target harus token milik pemohon');
    console.log('   OK — Notifikasi penolakan surat berhasil memuat alasan penolakan ke pemohon.\n');

    // 8. Test FCM Failure Non-Blocking Resilience (create & update remain successful)
    console.log('7. Menguji keandalan: createLetter dan updateLetterStatus tetap sukses saat Firebase error...');
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
      user: pemohonWarga,
      body: {
        jenis_surat: 'Surat Pengantar SKCK',
        keperluan: 'Melamar pekerjaan.',
      },
    });

    await createLetter(reqCreateBroken, resCreateBroken);
    assert(resCreateBroken.getStatusCode() === 201, 'createLetter WAJIB tetap HTTP 201 meski FCM error');
    assert(resCreateBroken.getBody().success === true, 'Response body WAJIB tetap success: true');
    const brokenLetterId = resCreateBroken.getBody().data.id;
    createdLetterIds.push(brokenLetterId);

    // Verifikasi data tersimpan utuh di database PostgreSQL
    const dbCheck = await pool.query('SELECT id, jenis_surat FROM letters WHERE id = $1', [brokenLetterId]);
    assert(dbCheck.rows.length === 1, 'Data surat harus tersimpan utuh di database');
    console.log(`   Surat #${brokenLetterId} berhasil dibuat dan tersimpan di DB.`);

    // Update status saat FCM error
    const { req: reqUpdateBroken, res: resUpdateBroken } = mockReqRes({
      user: adminPengurus,
      params: { id: brokenLetterId },
      body: {
        status: 'disetujui',
        response_note: 'Disetujui.',
      },
    });

    await updateLetterStatus(reqUpdateBroken, resUpdateBroken);
    assert(resUpdateBroken.getStatusCode() === 200, 'updateLetterStatus WAJIB tetap HTTP 200 meski FCM error');
    assert(resUpdateBroken.getBody().success === true, 'Response body WAJIB tetap success: true');

    const dbCheckUpdated = await pool.query('SELECT status FROM letters WHERE id = $1', [brokenLetterId]);
    assert(dbCheckUpdated.rows[0].status === 'disetujui', 'Status di DB harus tetap berubah menjadi "disetujui"');
    console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak alur surat utama.\n');

    console.log('================================================================');
    console.log('SEMUA 7 SKENARIO INTEGRASI FCM SURAT MENYURAT LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);

    // Beri jeda kecil agar operasi background selesai
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Cleanup fixtures
    console.log('Membersihkan database fixture pengujian surat FCM...');
    for (const ltrId of createdLetterIds) {
      await pool.query('DELETE FROM letters WHERE id = $1', [ltrId]);
    }
    if (adminPengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [adminPengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [adminPengurus.id]);
    }
    if (sekretarisPengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [sekretarisPengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [sekretarisPengurus.id]);
    }
    if (inactivePengurus?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [inactivePengurus.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [inactivePengurus.id]);
    }
    if (pemohonWarga?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [pemohonWarga.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [pemohonWarga.id]);
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
  runLetterFcmTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST INTEGRASI SURAT FCM GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runLetterFcmTests };
