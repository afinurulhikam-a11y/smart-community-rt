require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-bill-fcm');

const { pool } = require('./src/config/database');
const {
  createBill,
  payBill,
  sendNewBillPushNotification,
} = require('./src/controllers/bill.controller');
const {
  terapkanStatus,
  sendPaymentSuccessPushNotification,
} = require('./src/controllers/payment.controller');
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

async function runBillFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL IURAN & BAYAR (PHASE 2B.1)');
  console.log('================================================================\n');

  let adminUser = null;
  let keluargaA = null;
  let keluargaB = null;
  let userA1 = null;
  let userA2Inactive = null;
  let userB1 = null;
  let jenisIuran = null;

  const createdBillIds = [];
  const createdPaymentTrxIds = [];

  const tokenAdmin = `fcm_bill_admin_${Date.now()}`;
  const tokenA1 = `fcm_bill_a1_${Date.now()}`;
  const tokenA2Inact = `fcm_bill_a2inact_${Date.now()}`;
  const tokenB1 = `fcm_bill_b1_${Date.now()}`;

  try {
    // 1. Setup isolated database fixtures
    console.log('1. Menyiapkan database fixture (Admin, 2 Keluarga, Warga Aktif/Nonaktif, Jenis Iuran)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin RT Keuangan', `admin_bil_${Date.now()}@test.local`, `adm_bil_${Date.now()}`, `3241${Date.now()}`.slice(0, 16)]
    );
    adminUser = adminRes.rows[0];

    const noKkA = `3273${Date.now()}`.slice(0, 16);
    const kkARes = await pool.query(
      `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, langganan_sampah)
       VALUES ($1, 'Keluarga A Bpk Joko', 'Jl. Melati No. 1', '001', '002', true)
       RETURNING id, no_kk, kepala_keluarga`,
      [noKkA]
    );
    keluargaA = kkARes.rows[0];

    const noKkB = `3274${Date.now()}`.slice(0, 16);
    const kkBRes = await pool.query(
      `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, rt, rw, langganan_sampah)
       VALUES ($1, 'Keluarga B Bpk Rudi', 'Jl. Melati No. 2', '001', '002', false)
       RETURNING id, no_kk, kepala_keluarga`,
      [noKkB]
    );
    keluargaB = kkBRes.rows[0];

    const userA1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, no_kk)
       VALUES ($1, $2, 'warga', true, $3, $4, $5)
       RETURNING id, nama, role, no_kk`,
      ['Joko Warga A1', `joko_${Date.now()}@test.local`, `joko_${Date.now()}`, `3242${Date.now()}`.slice(0, 16), noKkA]
    );
    userA1 = userA1Res.rows[0];

    const userA2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, no_kk)
       VALUES ($1, $2, 'warga', false, $3, $4, $5)
       RETURNING id, nama, role, no_kk`,
      ['Ani Nonaktif A2', `ani_${Date.now()}@test.local`, `ani_${Date.now()}`, `3243${Date.now()}`.slice(0, 16), noKkA]
    );
    userA2Inactive = userA2Res.rows[0];

    const userB1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik, no_kk)
       VALUES ($1, $2, 'warga', true, $3, $4, $5)
       RETURNING id, nama, role, no_kk`,
      ['Rudi Warga B1', `rudi_${Date.now()}@test.local`, `rudi_${Date.now()}`, `3244${Date.now()}`.slice(0, 16), noKkB]
    );
    userB1 = userB1Res.rows[0];

    const jenisRes = await pool.query(
      `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, tipe_hitung, is_aktif)
       VALUES ($1, 50000, 'Bulanan', 'tetap', true)
       RETURNING id, nama_iuran, nominal_default`,
      [`Iuran Keamanan ${Date.now()}`.slice(0, 40)]
    );
    jenisIuran = jenisRes.rows[0];

    // Daftarkan token FCM perangkat
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Admin Phone', true)`,
      [adminUser.id, tokenAdmin]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'User A1 Phone', true)`,
      [userA1.id, tokenA1]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'Inactive Device', true)`,
      [userA2Inactive.id, tokenA2Inact]
    );
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, device_name, is_active)
       VALUES ($1, $2, 'android', 'User B1 Phone', true)`,
      [userB1.id, tokenB1]
    );

    console.log(`   Admin ID: ${adminUser.id}`);
    console.log(`   Keluarga A ID: ${keluargaA.id} (User A1: ${userA1.id})`);
    console.log(`   Keluarga B ID: ${keluargaB.id} (User B1: ${userB1.id})`);
    console.log(`   Jenis Iuran ID: ${jenisIuran.id}`);
    console.log('   OK — Setup database fixture berhasil.\n');

    // 2. Setup Mock Messaging
    const capturedMessages = [];
    const mockMessaging = {
      send: async (msg) => {
        capturedMessages.push(msg);
        return 'mock-bill-msg-id';
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

    // 3. Test Event 1: New Bill Creation -> Push to Family Recipient
    console.log('2. Menguji Event 1: Tagihan Iuran Baru Diterbitkan -> Push Notification ke Keluarga Penerima...');
    const bulanTagihan = '2026-08';
    const { req: reqCreateBill, res: resCreateBill } = mockReqRes({
      user: adminUser,
      body: {
        keluarga_id: keluargaA.id,
        jenis_iuran_id: jenisIuran.id,
        bulan: bulanTagihan,
        nominal: 50000,
        keterangan: 'Iuran wajib bulanan.',
      },
    });

    await createBill(reqCreateBill, resCreateBill);
    assert(resCreateBill.getStatusCode() === 201, 'createBill harus HTTP 201');
    assert(resCreateBill.getBody().success === true, 'Response body success harus true');
    const createdBillA = resCreateBill.getBody().data;
    createdBillIds.push(createdBillA.id);

    // Tunggu background async dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM tagihan harus terkirim');

    const billMsg = capturedMessages[0];
    assert(billMsg.notification.title.includes(bulanTagihan), 'Judul harus memuat periode bulan tagihan');
    assert(billMsg.notification.body.includes('50.000'), 'Body harus memuat nominal tagihan rupiah');
    assert(billMsg.data.entity_type === 'bill', 'data.entity_type harus "bill"');
    assert(billMsg.data.entity_id === String(createdBillA.id), 'data.entity_id harus ID tagihan');
    assert(billMsg.data.action === 'NEW_BILL', 'data.action harus NEW_BILL');
    const targetTokenBill = billMsg.token || billMsg.tokens?.[0];
    assert(targetTokenBill === tokenA1, 'Target harus token milik User A1 (Keluarga A)');
    assert(targetTokenBill !== tokenB1, 'TIDAK BOLEH menargetkan Keluarga B');
    assert(targetTokenBill !== tokenAdmin, 'TIDAK BOLEH menargetkan admin pembuat');
    console.log('   OK — Notifikasi tagihan baru berhasil menargetkan keluarga penerima dengan payload akurat.\n');

    // 4. Test Duplicate Dispatch Prevention for New Bill
    console.log('3. Menguji pencegahan duplikasi pengiriman untuk event Tagihan Baru...');
    const duplicateBillRes = await sendNewBillPushNotification(createdBillA);
    assert(duplicateBillRes.skipped === true, 'Pengiriman kedua untuk tagihan yang sama harus diskip');
    assert(duplicateBillRes.reason === 'already_sent', 'Alasan penolakan harus already_sent');
    assert(capturedMessages.length === 1, 'Pesan FCM tidak boleh bertambah');
    console.log('   OK — Idempotency guard berhasil mencegah siaran ganda pada tagihan baru.\n');

    // 5. Test Event 2a: Midtrans Webhook Settlement -> Push to Payer
    console.log('4. Menguji Event 2a: Pembayaran Berhasil (Midtrans Webhook Settlement) -> Push ke Pembayar...');
    capturedMessages.length = 0;

    const orderIdMidtrans = `ORDER-TEST-${Date.now()}`;
    const trxRes = await pool.query(
      `INSERT INTO payment_transactions (order_id, user_id, keluarga_id, gross_amount, status)
       VALUES ($1, $2, $3, 50000, 'pending')
       RETURNING *`,
      [orderIdMidtrans, userA1.id, keluargaA.id]
    );
    const trx = trxRes.rows[0];
    createdPaymentTrxIds.push(trx.id);

    await pool.query(
      `INSERT INTO payment_transaction_bills (transaction_id, bill_id, nominal, is_pending)
       VALUES ($1, $2, 50000, true)`,
      [trx.id, createdBillA.id]
    );

    const midtransResmi = {
      order_id: orderIdMidtrans,
      status_code: '200',
      gross_amount: '50000.00',
      transaction_status: 'settlement',
      payment_type: 'qris',
      transaction_time: '2026-08-18 12:00:00',
    };

    const hasilTerapkan = await terapkanStatus(orderIdMidtrans, midtransResmi);
    assert(hasilTerapkan.ok === true, 'terapkanStatus harus sukses');
    assert(hasilTerapkan.status === 'settlement', 'Status harus settlement');

    // Tunggu background async dispatch selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM pembayaran sukses harus terkirim');

    const payMsg = capturedMessages[0];
    assert(payMsg.notification.title.includes('Berhasil'), 'Judul harus memuat "Berhasil"');
    assert(payMsg.notification.body.includes('50.000'), 'Body harus memuat nominal pembayaran');
    assert(payMsg.data.entity_type === 'payment', 'data.entity_type harus "payment"');
    assert(payMsg.data.action === 'PAYMENT_SUCCESS', 'data.action harus PAYMENT_SUCCESS');
    assert(payMsg.data.status === 'settlement', 'data.status harus settlement');
    assert(payMsg.android.priority === 'high', 'Priority pembayaran harus high');
    const targetTokenPay = payMsg.token || payMsg.tokens?.[0];
    assert(targetTokenPay === tokenA1, 'Target harus token pembayar (User A1)');
    console.log('   OK — Notifikasi pembayaran sukses Midtrans berhasil dikirim ke pembayar.\n');

    // 6. Test Webhook Duplicate Call Suppression (Idempotency)
    console.log('5. Menguji webhook duplikat/berulang TIDAK mengirim push ganda...');
    const duplicateWebhookRes = await sendPaymentSuccessPushNotification({
      id: trx.id,
      order_id: orderIdMidtrans,
      user_id: userA1.id,
      gross_amount: 50000,
    }, [createdBillA]);
    assert(duplicateWebhookRes.skipped === true, 'Panggilan webhook kedua harus diskip');
    assert(duplicateWebhookRes.reason === 'already_sent_or_processing', 'Alasan penolakan harus already_sent_or_processing');
    assert(capturedMessages.length === 1, 'Tidak boleh ada pesan FCM baru');
    console.log('   OK — Idempotency database berhasil menahan pemanggilan webhook berulang.\n');

    // 7. Test Concurrent Webhook Race Condition Guard
    console.log('6. Menguji Race Condition Guard pada pemanggilan webhook/dispatch serentak...');
    const orderIdConcurrent = `ORDER-CONC-${Date.now()}`;
    const trxConcRes = await pool.query(
      `INSERT INTO payment_transactions (order_id, user_id, keluarga_id, gross_amount, status)
       VALUES ($1, $2, $3, 50000, 'pending')
       RETURNING *`,
      [orderIdConcurrent, userA1.id, keluargaA.id]
    );
    const trxConc = trxConcRes.rows[0];
    createdPaymentTrxIds.push(trxConc.id);

    capturedMessages.length = 0;
    const concurrentResults = await Promise.all([
      sendPaymentSuccessPushNotification(trxConc, [createdBillA]),
      sendPaymentSuccessPushNotification(trxConc, [createdBillA]),
      sendPaymentSuccessPushNotification(trxConc, [createdBillA]),
      sendPaymentSuccessPushNotification(trxConc, [createdBillA]),
      sendPaymentSuccessPushNotification(trxConc, [createdBillA]),
    ]);

    const successfulDispatches = concurrentResults.filter((r) => !r.skipped && r.success !== false);
    const skippedDispatches = concurrentResults.filter((r) => r.skipped);

    assert(successfulDispatches.length === 1, 'HANYA 1 dispatch yang boleh menang saat dieksekusi bersamaan');
    assert(skippedDispatches.length === 4, '4 pemanggilan lain WAJIB di-skip');
    assert(capturedMessages.length === 1, 'Hanya 1 pesan FCM yang terkirim');
    console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');

    // 8. Test Event 2b: Manual / Cash Payment -> Push to Payer
    console.log('7. Menguji Event 2b: Pembayaran Manual/Tunai -> Push ke Pembayar...');
    capturedMessages.length = 0;

    const { req: reqCreateBillB, res: resCreateBillB } = mockReqRes({
      user: adminUser,
      body: {
        keluarga_id: keluargaB.id,
        jenis_iuran_id: jenisIuran.id,
        bulan: '2026-09',
        nominal: 50000,
      },
    });

    await createBill(reqCreateBillB, resCreateBillB);
    const billB = resCreateBillB.getBody().data;
    createdBillIds.push(billB.id);

    // Tunggu background async dispatch createBill selesai
    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    // Bersihkan buffer pesan sebelum pembayaran
    capturedMessages.length = 0;

    const { req: reqPayManual, res: resPayManual } = mockReqRes({
      user: userB1,
      params: { id: billB.id },
      body: { metode_bayar: 'tunai' },
    });

    await payBill(reqPayManual, resPayManual);
    assert(resPayManual.getStatusCode() === 200, 'payBill harus HTTP 200');

    for (let i = 0; i < 15 && capturedMessages.length === 0; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert(capturedMessages.length === 1, 'Pesan FCM pembayaran tunai harus terkirim');
    const manualPayMsg = capturedMessages[0];
    const targetTokenManual = manualPayMsg.token || manualPayMsg.tokens?.[0];
    assert(targetTokenManual === tokenB1, 'Target harus token User B1');
    assert(manualPayMsg.data.entity_type === 'payment', 'entity_type harus "payment"');
    console.log('   OK — Notifikasi pembayaran manual/tunai berhasil dikirim ke pembayar.\n');

    // 9. Test FCM Failure Non-Blocking Resilience
    console.log('8. Menguji keandalan: createBill dan terapkanStatus tetap sukses saat Firebase error...');
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
      user: adminUser,
      body: {
        keluarga_id: keluargaA.id,
        jenis_iuran_id: jenisIuran.id,
        bulan: '2026-10',
        nominal: 50000,
      },
    });

    await createBill(reqCreateBroken, resCreateBroken);
    assert(resCreateBroken.getStatusCode() === 201, 'createBill WAJIB tetap HTTP 201 meski FCM error');
    assert(resCreateBroken.getBody().success === true, 'Response body success WAJIB true');
    const brokenBillId = resCreateBroken.getBody().data.id;
    createdBillIds.push(brokenBillId);

    const dbBillCheck = await pool.query('SELECT id, status FROM bills WHERE id = $1', [brokenBillId]);
    assert(dbBillCheck.rows.length === 1, 'Data tagihan harus tersimpan utuh di database');
    console.log(`   Tagihan #${brokenBillId} berhasil dibuat dan tersimpan di DB.`);

    const orderIdBroken = `ORDER-BRK-${Date.now()}`;
    const trxBrkRes = await pool.query(
      `INSERT INTO payment_transactions (order_id, user_id, keluarga_id, gross_amount, status)
       VALUES ($1, $2, $3, 50000, 'pending')
       RETURNING *`,
      [orderIdBroken, userA1.id, keluargaA.id]
    );
    const trxBrk = trxBrkRes.rows[0];
    createdPaymentTrxIds.push(trxBrk.id);

    await pool.query(
      `INSERT INTO payment_transaction_bills (transaction_id, bill_id, nominal, is_pending)
       VALUES ($1, $2, 50000, true)`,
      [trxBrk.id, brokenBillId]
    );

    const hasilTerapkanBroken = await terapkanStatus(orderIdBroken, {
      order_id: orderIdBroken,
      status_code: '200',
      gross_amount: '50000.00',
      transaction_status: 'settlement',
      payment_type: 'bank_transfer',
      transaction_time: '2026-08-18 12:00:00',
    });
    assert(hasilTerapkanBroken.ok === true, 'terapkanStatus WAJIB tetap sukses meski FCM error');

    const dbBillUpdated = await pool.query('SELECT status FROM bills WHERE id = $1', [brokenBillId]);
    assert(dbBillUpdated.rows[0].status === 'lunas', 'Status tagihan harus tetap lunas di DB');
    console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak alur transaksi keuangan.\n');

    console.log('================================================================');
    console.log('SEMUA 8 SKENARIO INTEGRASI FCM IURAN & BAYAR LULUS 100%!');
    console.log('================================================================\n');
  } finally {
    // Reset mock
    setMockMessaging(null);

    // Beri jeda kecil agar operasi background selesai
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Cleanup fixtures
    console.log('Membersihkan database fixture pengujian iuran & bayar FCM...');
    for (const trxId of createdPaymentTrxIds) {
      await pool.query('DELETE FROM payment_transaction_bills WHERE transaction_id = $1', [trxId]);
      await pool.query('DELETE FROM payment_transactions WHERE id = $1', [trxId]);
    }
    for (const billId of createdBillIds) {
      await pool.query('DELETE FROM finances WHERE ref_id IN (SELECT id FROM bill_payments WHERE bill_id = $1)', [billId]);
      await pool.query('DELETE FROM bill_payments WHERE bill_id = $1', [billId]);
      await pool.query('DELETE FROM bills WHERE id = $1', [billId]);
    }
    if (jenisIuran?.id) {
      await pool.query('DELETE FROM jenis_iuran WHERE id = $1', [jenisIuran.id]);
    }
    if (adminUser?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [adminUser.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [adminUser.id]);
    }
    if (userA1?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [userA1.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [userA1.id]);
    }
    if (userA2Inactive?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [userA2Inactive.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [userA2Inactive.id]);
    }
    if (userB1?.id) {
      await pool.query('DELETE FROM user_fcm_tokens WHERE user_id = $1', [userB1.id]);
      await pool.query('DELETE FROM users WHERE id = $1', [userB1.id]);
    }
    if (keluargaA?.id) {
      await pool.query('DELETE FROM keluarga WHERE id = $1', [keluargaA.id]);
    }
    if (keluargaB?.id) {
      await pool.query('DELETE FROM keluarga WHERE id = $1', [keluargaB.id]);
    }
    console.log('Database fixture berhasil dibersihkan.\n');
    await pool.end();
  }
}

if (require.main === module) {
  runBillFcmTests()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\n❌ TEST INTEGRASI IURAN & BAYAR FCM GAGAL:', err);
      process.exit(1);
    });
}

module.exports = { runBillFcmTests };
