require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-inventory-fcm');

const { pool } = require('../src/config/database');
const {
  createBorrowing,
  approveBorrowing,
  rejectBorrowing,
  returnBorrowing,
  sendBorrowingStatusPushNotification,
} = require('../src/controllers/inventory.controller');
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

async function waitForMessages(capturedArray, expectedCount = 1, maxAttempts = 20, delayMs = 25) {
  for (let i = 0; i < maxAttempts; i++) {
    if (capturedArray.length >= expectedCount) return;
    await new Promise((r) => setTimeout(r, delayMs));
  }
}

async function runInventoryFcmTests() {
  console.log('================================================================');
  console.log('TEST INTEGRASI FCM PUSH NOTIFIKASI MODUL INVENTARIS (PHASE 2E)');
  console.log('================================================================\n');

  let adminUser = null;
  let borrowerUser1 = null;
  let borrowerUser2 = null;
  let testItem = null;
  const createdBorrowingIds = [];

  const tokenBorrower1 = `fcm_token_borrower1_${Date.now()}`;
  const tokenBorrower1Inactive = `fcm_token_borrower1_inact_${Date.now()}`;
  const tokenBorrower2 = `fcm_token_borrower2_${Date.now()}`;

  try {
    // 1. Setup fixture (Admin, 2 Warga Peminjam, 1 Item Inventaris, Tokens)
    console.log('1. Menyiapkan database fixture (Admin, Peminjam, Item Inventaris, FCM Tokens)...');
    const adminRes = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'admin', true, $3, $4)
       RETURNING id, nama, role`,
      ['Admin Inventaris FCM', `admin_inv_${Date.now()}@test.local`, `adm_inv_${Date.now()}`, `3207${Date.now()}`.slice(0, 16)]
    );
    adminUser = adminRes.rows[0];

    const u1Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Budi Peminjam 1', `budi_inv_${Date.now()}@test.local`, `budi_inv_${Date.now()}`, `3208${Date.now()}`.slice(0, 16)]
    );
    borrowerUser1 = u1Res.rows[0];

    const u2Res = await pool.query(
      `INSERT INTO users (nama, email, role, is_active, username, nik)
       VALUES ($1, $2, 'warga', true, $3, $4)
       RETURNING id, nama, role`,
      ['Ani Peminjam 2', `ani_inv_${Date.now()}@test.local`, `ani_inv_${Date.now()}`, `3209${Date.now()}`.slice(0, 16)]
    );
    borrowerUser2 = u2Res.rows[0];

    // Buat item inventaris uji
    const itemRes = await pool.query(
      `INSERT INTO inventory (nama_barang, kategori, jumlah, kondisi, lokasi, nilai_barang, created_by)
       VALUES ($1, 'Peralatan', 10, 'Baik', 'Gudang RT', 500000, $2)
       RETURNING id, nama_barang, jumlah`,
      [`Tenda Komunitas RT ${Date.now()}`, adminUser.id]
    );
    testItem = itemRes.rows[0];

    // Daftarkan token FCM (2 token untuk borrower 1: 1 aktif, 1 nonaktif; 1 token untuk borrower 2)
    await pool.query(
      `INSERT INTO user_fcm_tokens (user_id, fcm_token, device_type, is_active)
       VALUES ($1, $2, 'android', true),
              ($3, $4, 'android', false),
              ($5, $6, 'android', true)`,
      [
        borrowerUser1.id, tokenBorrower1,
        borrowerUser1.id, tokenBorrower1Inactive,
        borrowerUser2.id, tokenBorrower2,
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

    // 3. Menguji Event 1: Status Awal Warga ("Menunggu Persetujuan") TIDAK Mengirim Push
    console.log('2. Menguji Status Awal Permohonan Warga ("Menunggu Persetujuan") TIDAK mengirim push...');
    interceptedMessages = [];
    let borrowing1 = null;

    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: borrowerUser1,
        body: {
          inventory_id: testItem.id,
          jumlah: 2,
          keterangan: 'Untuk acara arisan warga',
          tanggal_pinjam: '2026-08-22',
          tanggal_rencana_kembali: '2026-08-24',
        },
      });

      await createBorrowing(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      borrowing1 = res.getBody().data;
      createdBorrowingIds.push(borrowing1.id);
      assert(borrowing1.status === 'Menunggu Persetujuan', `Expected 'Menunggu Persetujuan', got ${borrowing1.status}`);

      const pushRes = await sendBorrowingStatusPushNotification(borrowing1);
      assert(pushRes.skipped === true, 'Initial pending status must be skipped');
      assert(pushRes.reason === 'status_not_relevant', `Expected reason 'status_not_relevant', got: ${pushRes.reason}`);
      assert(interceptedMessages.length === 0, 'No push notification should be sent for initial pending status');
      console.log('   OK — Status awal permohonan berhasil dilewati tanpa push notification.\n');
    }

    // 4. Menguji Event 2: Admin Menyetujui Peminjaman (Approve -> "Dipinjam") -> Push ke Peminjam
    console.log('3. Menguji Event Approve ("Dipinjam") -> Push Notification ke Peminjam...');
    interceptedMessages = [];
    let approvedBorrowing = null;
    {
      const { req, res } = mockReqRes({
        method: 'PUT',
        user: adminUser,
        params: { id: borrowing1.id },
      });

      await approveBorrowing(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      approvedBorrowing = res.getBody().data;
      assert(approvedBorrowing.status === 'Dipinjam', `Expected 'Dipinjam', got ${approvedBorrowing.status}`);

      // Tunggu background async dispatch selesai
      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];
      assert(msg.notification.title.includes('Peminjaman Disetujui'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.data.entity_type === 'inventory', `entity_type mismatch: ${msg.data.entity_type}`);
      assert(msg.data.entity_id === String(borrowing1.id), `entity_id mismatch: ${msg.data.entity_id}`);
      assert(msg.data.action === 'BORROWING_STATUS_CHANGED', `action mismatch: ${msg.data.action}`);
      assert(msg.data.status === 'Dipinjam', `status mismatch: ${msg.data.status}`);
      assert(msg.data.nama_barang === testItem.nama_barang, `nama_barang mismatch: ${msg.data.nama_barang}`);
      assert(msg.data.jumlah === '2', `jumlah mismatch: ${msg.data.jumlah}`);
      assert(msg.android.priority === 'normal', `priority mismatch: ${msg.android.priority}`);
      assert(msg.android.collapseKey === `inventory_borrowing_${borrowing1.id}`, `collapseKey mismatch: ${msg.android.collapseKey}`);

      // Token target validasi
      const targetToken = msg.token || msg.tokens?.[0];
      assert(targetToken === tokenBorrower1, 'Harus memuat token aktif peminjam 1');
      assert(targetToken !== tokenBorrower1Inactive, 'Token nonaktif TIDAK boleh termuat');
      assert(targetToken !== tokenBorrower2, 'Token peminjam lain TIDAK boleh termuat');

      // Verifikasi status database
      const dbCheck = await pool.query('SELECT fcm_last_status_dispatch FROM borrowings WHERE id = $1', [borrowing1.id]);
      assert(dbCheck.rows[0].fcm_last_status_dispatch === 'Dipinjam', `Expected 'Dipinjam', got: ${dbCheck.rows[0].fcm_last_status_dispatch}`);

      console.log('   OK — Notifikasi peminjaman disetujui berhasil dikirim ke peminjam dengan payload akurat.\n');
    }

    // 5. Menguji Durable Database Idempotency (Pencegahan siaran ganda pada status yang sama)
    console.log('4. Menguji Durable Database Idempotency (mencegah pengiriman push ganda)...');
    {
      interceptedMessages = [];
      const dupRes = await sendBorrowingStatusPushNotification(approvedBorrowing);
      assert(dupRes.skipped === true, 'Duplicate push must be skipped');
      assert(dupRes.reason === 'no_change_or_duplicate', `Expected reason 'no_change_or_duplicate', got: ${dupRes.reason}`);
      assert(interceptedMessages.length === 0, 'No FCM message should be sent on duplicate trigger');
      console.log('   OK — Idempotency guard berhasil menahan siaran ganda pada peminjaman yang statusnya tidak berubah.\n');
    }

    // 6. Menguji Event 3: Admin Menolak Peminjaman (Reject -> "Ditolak") -> Push ke Peminjam
    console.log('5. Menguji Event Reject ("Ditolak") -> Push Notification ke Peminjam...');
    interceptedMessages = [];
    let borrowing2 = null;
    {
      // Buat peminjaman kedua oleh Ani
      const { req: reqCreate, res: resCreate } = mockReqRes({
        method: 'POST',
        user: borrowerUser2,
        body: {
          inventory_id: testItem.id,
          jumlah: 1,
          keterangan: 'Peminjaman sound system',
          tanggal_pinjam: '2026-08-26',
        },
      });
      await createBorrowing(reqCreate, resCreate);
      borrowing2 = resCreate.getBody().data;
      createdBorrowingIds.push(borrowing2.id);

      // Tolak peminjaman
      const { req: reqRej, res: resRej } = mockReqRes({
        method: 'PUT',
        user: adminUser,
        params: { id: borrowing2.id },
      });
      await rejectBorrowing(reqRej, resRej);
      assert(resRej.getStatusCode() === 200, `Expected 200, got ${resRej.getStatusCode()}`);
      const rejectedBorrowing = resRej.getBody().data;
      assert(rejectedBorrowing.status === 'Ditolak', `Expected 'Ditolak', got ${rejectedBorrowing.status}`);

      // Tunggu background async dispatch selesai
      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];
      assert(msg.notification.title.includes('Peminjaman Ditolak'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.data.status === 'Ditolak', `status mismatch: ${msg.data.status}`);
      const targetToken = msg.token || msg.tokens?.[0];
      assert(targetToken === tokenBorrower2, 'Harus menargetkan token peminjam 2');
      console.log('   OK — Notifikasi peminjaman ditolak berhasil dikirim ke peminjam 2.\n');
    }

    // 7. Menguji Event 4: Pengembalian Barang (Return -> "Dikembalikan") -> Push ke Peminjam
    console.log('6. Menguji Event Return ("Dikembalikan") -> Push Notification ke Peminjam...');
    interceptedMessages = [];
    {
      const { req, res } = mockReqRes({
        method: 'PUT',
        user: adminUser,
        params: { id: borrowing1.id },
        body: { tanggal_kembali: '2026-08-24' },
      });

      await returnBorrowing(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      const returnedBorrowing = res.getBody().data;
      assert(returnedBorrowing.status === 'Dikembalikan', `Expected 'Dikembalikan', got ${returnedBorrowing.status}`);

      // Tunggu background async dispatch selesai
      await waitForMessages(interceptedMessages, 1);
      assert(interceptedMessages.length === 1, `Expected 1 message, got ${interceptedMessages.length}`);
      const msg = interceptedMessages[0];
      assert(msg.notification.title.includes('Pengembalian Diterima'), `Title mismatch: ${msg.notification.title}`);
      assert(msg.data.status === 'Dikembalikan', `status mismatch: ${msg.data.status}`);
      const targetToken = msg.token || msg.tokens?.[0];
      assert(targetToken === tokenBorrower1, 'Harus menargetkan peminjam 1');
      console.log('   OK — Notifikasi pengembalian barang berhasil dikirim ke peminjam.\n');
    }

    // 8. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)
    console.log('7. Menguji Race Condition Guard pada pemanggilan serentak (5 concurrent requests)...');
    {
      const insRes = await pool.query(
        `INSERT INTO borrowings (inventory_id, user_id, nama_peminjam, jumlah, status, fcm_last_status_dispatch)
         VALUES ($1, $2, $3, 1, 'Dipinjam', NULL)
         RETURNING *`,
        [testItem.id, borrowerUser1.id, borrowerUser1.nama]
      );
      const concBorrowing = insRes.rows[0];
      createdBorrowingIds.push(concBorrowing.id);

      interceptedMessages = [];
      const results = await Promise.all([
        sendBorrowingStatusPushNotification(concBorrowing),
        sendBorrowingStatusPushNotification(concBorrowing),
        sendBorrowingStatusPushNotification(concBorrowing),
        sendBorrowingStatusPushNotification(concBorrowing),
        sendBorrowingStatusPushNotification(concBorrowing),
      ]);

      const sentCount = results.filter((r) => r.success === true).length;
      const skippedCount = results.filter((r) => r.skipped === true).length;
      assert(sentCount === 1, `Expected exactly 1 success, got ${sentCount}`);
      assert(skippedCount === 4, `Expected 4 skipped, got ${skippedCount}`);
      assert(interceptedMessages.length === 1, `Expected 1 multicast call, got ${interceptedMessages.length}`);
      console.log('   OK — Operasi database atomik berhasil mengunci race condition pada 5 panggilan concurrent.\n');
    }

    // 9. Menguji Keandalan & Fail-Safe: FCM Failure TIDAK Membatalkan Transaksi Status
    console.log('8. Menguji keandalan: status update tetap sukses saat Firebase error...');
    {
      setMockMessaging({
        send: async () => {
          throw new Error('Firebase Unavailable (Simulated Error)');
        },
        sendEachForMulticast: async () => {
          throw new Error('Firebase Unavailable (Simulated Error)');
        },
      });

      const insRes = await pool.query(
        `INSERT INTO borrowings (inventory_id, user_id, nama_peminjam, jumlah, status)
         VALUES ($1, $2, $3, 1, 'Menunggu Persetujuan')
         RETURNING *`,
        [testItem.id, borrowerUser1.id, borrowerUser1.nama]
      );
      const failBorrowing = insRes.rows[0];
      createdBorrowingIds.push(failBorrowing.id);

      const { req, res } = mockReqRes({
        method: 'PUT',
        user: adminUser,
        params: { id: failBorrowing.id },
      });

      await approveBorrowing(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      assert(res.getBody().data.status === 'Dipinjam', 'Status must be updated to Dipinjam in database');

      // Dispatch manual failure
      const pushRes = await sendBorrowingStatusPushNotification(res.getBody().data);
      assert(pushRes.success === false || pushRes.error != null, 'FCM dispatch should report error');

      console.log('   OK — Kegagalan FCM tidak pernah membatalkan atau merusak alur transaksi peminjaman.\n');
    }

    console.log('================================================================');
    console.log('SEMUA 8 SKENARIO INTEGRASI FCM PEMINJAMAN INVENTARIS LULUS 100%!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('❌ PENGUJIAN FCM INVENTARIS GAGAL:', err);
    process.exitCode = 1;
  } finally {
    setMockMessaging(null);
    console.log('Membersihkan database fixture pengujian inventaris FCM...');
    for (const bId of createdBorrowingIds) {
      await pool.query('DELETE FROM borrowings WHERE id = $1', [bId]).catch(() => {});
    }
    if (testItem?.id) {
      await pool.query('DELETE FROM inventory WHERE id = $1', [testItem.id]).catch(() => {});
    }
    await pool.query(
      `DELETE FROM user_fcm_tokens WHERE fcm_token IN ($1, $2, $3)`,
      [tokenBorrower1, tokenBorrower1Inactive, tokenBorrower2]
    ).catch(() => {});
    const userIds = [adminUser?.id, borrowerUser1?.id, borrowerUser2?.id].filter(Boolean);
    if (userIds.length > 0) {
      await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [userIds]).catch(() => {});
    }
    console.log('Database fixture berhasil dibersihkan.');
    await pool.end();
  }
}

if (require.main === module) {
  runInventoryFcmTests();
}

module.exports = { runInventoryFcmTests };
