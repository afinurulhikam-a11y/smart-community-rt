require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-polling-vote');

const { pool } = require('../src/config/database');
const { getPolling, vote } = require('../src/controllers/polling.controller');

// Helper to simulate express req/res
function mockReqRes({ method = 'GET', params = {}, query = {}, body = {}, user = null } = {}) {
  const req = {
    method,
    params,
    query,
    body,
    user,
    headers: {},
    ip: '127.0.0.1',
    socket: { remoteAddress: '127.0.0.1' },
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

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
}

async function runTests() {
  console.log('================================================================');
  console.log('TEST POLLING WARGA (VOTE, CHANGE VOTE, CONCURRENCY, TIMEZONE)');
  console.log('================================================================\n');

  let testUser1 = null;
  let testUser2;
  let testPollingId = null;
  let expiredPollingId = null;
  let futurePollingId = null;
  let timezonePollingId = null;
  let optA = null;
  let optB;
  let optC = null;

  try {
    // 1. Setup isolated test users
    console.log('1. Setup isolated test users...');
    const existingUsers = await pool.query("SELECT id, email, role, nama, token_versi FROM users WHERE role = 'warga' LIMIT 2");
    if (existingUsers.rows.length >= 2) {
      testUser1 = existingUsers.rows[0];
      testUser2 = existingUsers.rows[1];
    } else {
      const u1 = await pool.query(
        `INSERT INTO users (email, role, nama, password_hash) VALUES ('test_warga1_${Date.now()}@test.local', 'warga', 'Warga Test 1', 'hash') RETURNING id, email, role, nama, token_versi`
      );
      const u2 = await pool.query(
        `INSERT INTO users (email, role, nama, password_hash) VALUES ('test_warga2_${Date.now()}@test.local', 'warga', 'Warga Test 2', 'hash') RETURNING id, email, role, nama, token_versi`
      );
      testUser1 = u1.rows[0];
      testUser2 = u2.rows[0];
    }
    console.log(`   User 1: ${testUser1.nama} (${testUser1.id})`);
    console.log(`   User 2: ${testUser2.nama} (${testUser2.id})`);
    console.log('   Setup user berhasil.\n');

    // 2. Setup isolated active polling
    console.log('2. Membuat fixture polling aktif baru...');
    const pollRes = await pool.query(
      `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
       VALUES ('Polling Uji Mandiri ${Date.now()}', 'Deskripsi uji otomatis', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date + INTERVAL '5 days', 'Aktif', $1)
       RETURNING *`,
      [testUser1.id]
    );
    testPollingId = pollRes.rows[0].id;

    // Add 3 options: Opsi A, Opsi B, Opsi C
    const optResA = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi A', 0) RETURNING id`, [testPollingId]);
    const optResB = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi B', 0) RETURNING id`, [testPollingId]);
    const optResC = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi C', 0) RETURNING id`, [testPollingId]);
    optA = optResA.rows[0].id;
    optB = optResB.rows[0].id;
    optC = optResC.rows[0].id;

    console.log(`   Polling ID: ${testPollingId} (Options: A=${optA}, B=${optB}, C=${optC})`);
    console.log('   Setup polling aktif berhasil.\n');

    // 3. Test Memilih Pertama Kali
    console.log('3. Menguji Memilih Pertama Kali (User 1 -> Opsi A)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optA },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}: ${JSON.stringify(res.getBody())}`);
      assert(res.getBody().success === true, 'Expected success === true');
      assert(res.getBody().data.is_change === false, 'Expected is_change === false');

      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected 1 vote row, got ${voteRows.rows.length}`);
      assert(voteRows.rows[0].option_id === optA, `Expected option_id to be ${optA}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      assert(optRows.rows[0].vote_count === 1, 'Opsi A count should be 1');
      assert(optRows.rows[1].vote_count === 0, 'Opsi B count should be 0');
      assert(optRows.rows[2].vote_count === 0, 'Opsi C count should be 0');
      console.log('   Memilih pertama kali berhasil (Record = 1, Opsi A = 1, B = 0, C = 0).\n');
    }

    // 4. Test Mengubah Pilihan (A -> B)
    console.log('4. Menguji Mengubah Pilihan A -> B (User 1 -> Opsi B)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optB },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}: ${JSON.stringify(res.getBody())}`);
      assert(res.getBody().success === true, 'Expected success === true');
      assert(res.getBody().data.is_change === true, 'Expected is_change === true');

      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected still exactly 1 vote row, got ${voteRows.rows.length}`);
      assert(voteRows.rows[0].option_id === optB, `Expected option_id to be updated to ${optB}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      assert(optRows.rows[0].vote_count === 0, 'Opsi A count should be decremented to 0');
      assert(optRows.rows[1].vote_count === 1, 'Opsi B count should be incremented to 1');
      assert(optRows.rows[2].vote_count === 0, 'Opsi C count should be 0');
      console.log('   Perubahan A -> B berhasil (Record tetap 1, Opsi A = 0, B = 1, C = 0).\n');
    }

    // 5. Test Mengubah Pilihan Lagi (B -> C)
    console.log('5. Menguji Mengubah Pilihan B -> C (User 1 -> Opsi C)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optC },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      assert(res.getBody().data.is_change === true, 'Expected is_change === true');

      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected still 1 vote row, got ${voteRows.rows.length}`);
      assert(voteRows.rows[0].option_id === optC, `Expected option_id to be updated to ${optC}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      assert(optRows.rows[0].vote_count === 0, 'Opsi A count should be 0');
      assert(optRows.rows[1].vote_count === 0, 'Opsi B count should be 0');
      assert(optRows.rows[2].vote_count === 1, 'Opsi C count should be 1');
      console.log('   Perubahan B -> C berhasil (Record tetap 1, Opsi A = 0, B = 0, C = 1).\n');
    }

    // 6. Test Memilih Pilihan yang Sama (C -> C / Idempoten)
    console.log('6. Menguji Memilih Opsi Yang Sama C -> C (A -> A)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optC },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);

      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, 'Still 1 row');
      assert(voteRows.rows[0].option_id === optC, 'Still option C');

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      assert(optRows.rows[2].vote_count === 1, 'Opsi C count must remain 1');
      console.log('   Transisi C -> C tidak menambah total suara (Opsi C tetap 1, total 1 suara).\n');
    }

    // 7. Test Multi-User Voting
    console.log('7. Menguji User 2 Memilih Opsi A...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optA },
        user: testUser2,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);

      const totalVotesInDb = await pool.query('SELECT COUNT(*) as total FROM polling_votes WHERE polling_id = $1', [testPollingId]);
      assert(parseInt(totalVotesInDb.rows[0].total, 10) === 2, 'Total votes in DB should be 2');

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      assert(optRows.rows[0].vote_count === 1, 'Opsi A = 1');
      assert(optRows.rows[1].vote_count === 0, 'Opsi B = 0');
      assert(optRows.rows[2].vote_count === 1, 'Opsi C = 1');
      console.log('   Multi-user konsisten (Total suara = 2: Opsi A = 1, Opsi C = 1).\n');
    }

    // 8. Test getPolling Output
    console.log('8. Menguji getPolling & Kalkulasi Persentase...');
    {
      const { req, res } = mockReqRes({
        method: 'GET',
        query: { status: 'Aktif' },
        user: testUser1,
      });
      await getPolling(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      const data = res.getBody().data;
      const thisPoll = data.find((p) => p.id === testPollingId);
      assert(thisPoll != null, 'Polling should be in getPolling response');
      assert(thisPoll.total_votes === 2, `Expected total_votes 2, got ${thisPoll.total_votes}`);
      assert(thisPoll.sudah_vote === true, 'User 1 sudah_vote should be true');
      assert(thisPoll.pilihan_saya === optC, `User 1 pilihan_saya should be ${optC}`);
      assert(thisPoll.belum_mulai === false, 'belum_mulai should be false');
      assert(thisPoll.lewat_deadline === false, 'lewat_deadline should be false');

      const optAData = thisPoll.options.find((o) => o.id === optA);
      const optCData = thisPoll.options.find((o) => o.id === optC);
      assert(optAData.percentage === 50, `Expected 50%, got ${optAData.percentage}%`);
      assert(optCData.percentage === 50, `Expected 50%, got ${optCData.percentage}%`);
      console.log('   getPolling mengembalikan persentase & pilihan_saya yang akurat.\n');
    }

    // 9. Concurrency & Race Condition Test (Simulasi vote cepat simultan)
    console.log('9. Menguji Concurrency / Race Condition...');
    {
      const targets = [optA, optB, optC, optA, optB, optC, optA, optB, optC, optA];
      const promises = targets.map((optId) => {
        const { req, res } = mockReqRes({
          method: 'POST',
          params: { id: testPollingId },
          body: { option_id: optId },
          user: testUser1,
        });
        return vote(req, res);
      });

      await Promise.all(promises);

      const user1Votes = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(user1Votes.rows.length === 1, `Concurrency violation: User 1 has ${user1Votes.rows.length} rows in polling_votes`);

      const allVotes = await pool.query('SELECT COUNT(*) as total FROM polling_votes WHERE polling_id = $1', [testPollingId]);
      assert(parseInt(allVotes.rows[0].total, 10) === 2, `Expected total 2 votes (User 1 and User 2), got ${allVotes.rows[0].total}`);

      const optRows = await pool.query('SELECT SUM(vote_count) as total FROM polling_options WHERE polling_id = $1', [testPollingId]);
      assert(parseInt(optRows.rows[0].total, 10) === 2, `Expected options sum = 2, got ${optRows.rows[0].total}`);
      console.log('   Concurrency test lulus: Tepat 1 record per user, tidak ada duplicate atau suara ganda.\n');
    }

    // 10. Test Penolakan Voting Saat Polling Ditutup
    console.log('10. Menguji Penolakan Setelah Status Polling Ditutup...');
    {
      await pool.query("UPDATE polling SET status = 'Ditutup' WHERE id = $1", [testPollingId]);

      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optA },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 400, `Expected 400 rejection when closed, got ${res.getStatusCode()}`);
      assert(res.getBody().success === false, 'Expected success === false');
      console.log(`   Pesan penolakan: "${res.getBody().message}"`);
      console.log('   Penolakan voting saat status ditutup berhasil diverifikasi (HTTP 400).\n');
    }

    // 11. Test Penolakan Setelah Melewati Deadline
    console.log('11. Menguji Penolakan Setelah Melewati Batas Waktu (Deadline)...');
    {
      const expRes = await pool.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
         VALUES ('Polling Kedaluwarsa ${Date.now()}', 'Uji deadline', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date - INTERVAL '10 days', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date - INTERVAL '1 day', 'Aktif', $1)
         RETURNING *`,
        [testUser1.id]
      );
      expiredPollingId = expRes.rows[0].id;
      const expOptRes = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi Exp', 0) RETURNING id`, [expiredPollingId]);
      const expOptId = expOptRes.rows[0].id;

      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: expiredPollingId },
        body: { option_id: expOptId },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 400, `Expected 400 rejection for expired deadline, got ${res.getStatusCode()}`);
      assert(res.getBody().success === false, 'Expected success === false');
      assert(res.getBody().message.includes('deadline') || res.getBody().message.includes('batas waktu'), `Expected deadline message, got: ${res.getBody().message}`);
      console.log(`   Pesan penolakan: "${res.getBody().message}"`);
      console.log('   Penolakan voting saat melewati deadline berhasil diverifikasi (HTTP 400).\n');
    }

    // 12. Regression Test: Polling Belum Dimulai (Future start date)
    console.log('12. Menguji Penolakan Saat Polling Belum Dimulai (Future start date)...');
    {
      const futRes = await pool.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
         VALUES ('Polling Belum Mulai ${Date.now()}', 'Uji belum mulai', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date + INTERVAL '1 day', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date + INTERVAL '5 days', 'Aktif', $1)
         RETURNING *`,
        [testUser1.id]
      );
      futurePollingId = futRes.rows[0].id;
      const futOptRes = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi Fut', 0) RETURNING id`, [futurePollingId]);
      const futOptId = futOptRes.rows[0].id;

      // Cek getPolling
      const { req: getReq, res: getRes } = mockReqRes({
        method: 'GET',
        query: { status: 'Aktif' },
        user: testUser1,
      });
      await getPolling(getReq, getRes);
      const pollObj = getRes.getBody().data.find((p) => p.id === futurePollingId);
      assert(pollObj != null, 'Future polling must be in getPolling list');
      assert(pollObj.belum_mulai === true, 'Expected belum_mulai === true for tomorrow start date');

      // Cek vote rejection
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: futurePollingId },
        body: { option_id: futOptId },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 400, `Expected 400 rejection for future polling, got ${res.getStatusCode()}`);
      assert(res.getBody().success === false, 'Expected success === false');
      assert(res.getBody().message.includes('belum dimulai'), `Expected message 'belum dimulai', got: ${res.getBody().message}`);
      console.log(`   Pesan penolakan: "${res.getBody().message}"`);
      console.log('   Penolakan voting saat belum mulai berhasil diverifikasi (HTTP 400).\n');
    }

    // 13. Regression Test: Simulasi Timezone UTC vs WIB
    console.log('13. Menguji Validasi Timezone UTC vs Asia/Jakarta (WIB)...');
    {
      // Set session timezone PostgreSQL ke UTC secara eksplisit untuk mensimulasikan lingkungan server UTC (misal Railway / Cloud)
      await pool.query("SET TIME ZONE 'UTC'");

      // Ambil tanggal hari ini dalam WIB (Asia/Jakarta) dan UTC
      const tzInfo = await pool.query(`
        SELECT
          (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date AS today_wib,
          TO_CHAR((CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta'), 'YYYY-MM-DD HH24:MI:SS') AS now_wib,
          CURRENT_DATE AS today_utc,
          TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') AS now_utc
      `);
      // `today_wib` sengaja tidak diambil: tanggal WIB diturunkan dari
      // `now_wib` beberapa baris di bawah, dan dua sumber untuk satu tanggal
      // adalah dua sumber yang bisa berbeda.
      const { now_wib, today_utc, now_utc } = tzInfo.rows[0];
      const todayWibStr = now_wib.slice(0, 10);
      console.log(`   [Simulasi Server UTC Aktif]`);
      console.log(`   Waktu Bisnis WIB (Asia/Jakarta): ${now_wib} (Tanggal: ${todayWibStr})`);
      console.log(`   Waktu Database UTC: ${now_utc} (Tanggal: ${today_utc.toISOString().slice(0, 10)})`);

      // Buat polling yang tanggal_mulai persis hari ini WIB (misal 16 Agustus)
      const tzRes = await pool.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, status, created_by)
         VALUES ('Polling WIB Test ${Date.now()}', 'Uji timezone WIB', (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date + INTERVAL '3 days', 'Aktif', $1)
         RETURNING id`,
        [testUser1.id]
      );
      timezonePollingId = tzRes.rows[0].id;
      const tzOpt1 = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi WIB 1', 0) RETURNING id`, [timezonePollingId]);
      const tzOpt2 = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi WIB 2', 0) RETURNING id`, [timezonePollingId]);
      const tzOpt3 = await pool.query(`INSERT INTO polling_options (polling_id, label, vote_count) VALUES ($1, 'Opsi WIB 3', 0) RETURNING id`, [timezonePollingId]);
      const tzOpt1Id = tzOpt1.rows[0].id;
      const tzOpt2Id = tzOpt2.rows[0].id;
      const tzOpt3Id = tzOpt3.rows[0].id;

      // 13.a getPolling harus menyatakan belum_mulai === false dan lewat_deadline === false
      const { req: getReq, res: getRes } = mockReqRes({
        method: 'GET',
        query: { status: 'Aktif' },
        user: testUser1,
      });
      await getPolling(getReq, getRes);
      const pollWib = getRes.getBody().data.find((p) => p.id === timezonePollingId);
      assert(pollWib != null, 'Timezone polling must be in list');
      assert(pollWib.belum_mulai === false, 'Polling yang dimulai hari ini WIB TIDAK boleh dianggap belum_mulai');
      assert(pollWib.lewat_deadline === false, 'Polling yang selesai 3 hari ke depan TIDAK boleh dianggap lewat_deadline');

      // 13.b Berikan suara pertama kali pada polling hari ini WIB -> Harus SUKSES (HTTP 200)
      const { req: voteReq1, res: voteRes1 } = mockReqRes({
        method: 'POST',
        params: { id: timezonePollingId },
        body: { option_id: tzOpt1Id },
        user: testUser1,
      });
      await vote(voteReq1, voteRes1);
      assert(voteRes1.getStatusCode() === 200, `Expected 200 for today WIB vote, got ${voteRes1.getStatusCode()}: ${JSON.stringify(voteRes1.getBody())}`);
      assert(voteRes1.getBody().success === true, 'Expected vote to succeed on today WIB');

      // 13.c Ubah pilihan 1 -> 2 pada polling hari ini WIB -> Harus SUKSES (HTTP 200)
      const { req: voteReq2, res: voteRes2 } = mockReqRes({
        method: 'POST',
        params: { id: timezonePollingId },
        body: { option_id: tzOpt2Id },
        user: testUser1,
      });
      await vote(voteReq2, voteRes2);
      assert(voteRes2.getStatusCode() === 200, `Expected 200 for today WIB vote change, got ${voteRes2.getStatusCode()}: ${JSON.stringify(voteRes2.getBody())}`);
      assert(voteRes2.getBody().success === true, 'Expected vote change to succeed on today WIB');

      // 13.d Ubah pilihan 2 -> 3 pada polling hari ini WIB -> Harus SUKSES (HTTP 200)
      const { req: voteReq3, res: voteRes3 } = mockReqRes({
        method: 'POST',
        params: { id: timezonePollingId },
        body: { option_id: tzOpt3Id },
        user: testUser1,
      });
      await vote(voteReq3, voteRes3);
      assert(voteRes3.getStatusCode() === 200, `Expected 200 for today WIB vote change 2->3, got ${voteRes3.getStatusCode()}`);
      assert(voteRes3.getBody().success === true, 'Expected vote change 2->3 to succeed');

      console.log('   Verifikasi Timezone WIB Berhasil: Polling aktif di WIB dapat divote & diubah (A->B->C) tanpa error "belum dimulai".\n');
    }

    // ================================================================
    // 14. Konsistensi penghitung terdenormalisasi
    // ================================================================
    //
    // `polling_options.vote_count` disimpan terpisah dari baris suara
    // sebenarnya, dan SELURUH persentase serta total_votes dihitung darinya —
    // bukan dari COUNT(*). Selama setiap perubahan lewat endpoint vote,
    // keduanya bergerak bersama.
    //
    // Yang berbahaya adalah ketika tidak: satu baris terhapus lewat reset,
    // koreksi manual, atau jalur baru yang lupa memperbarui penghitungnya — dan
    // hasil polling menjadi salah TANPA satu pun gejala. `GREATEST(0, ...)` di
    // controller menyembunyikan penyimpangan itu alih-alih mencegahnya.
    //
    // Diletakkan di AKHIR dengan sengaja: pada titik ini seluruh skenario sudah
    // berjalan — memilih, mengubah A->B->C, memilih ulang opsi yang sama, dua
    // pengguna, dan permintaan bersamaan. Bila salah satu di antaranya
    // meninggalkan penghitung yang melenceng, di sinilah ia terlihat.
    //
    // Cakupannya DIBATASI pada polling fixture uji ini, bukan seluruh tabel:
    // penyimpangan pada data lama yang sudah ada sebelumnya bukan kesalahan
    // skenario ini, dan membiarkannya menggagalkan uji hanya akan melatih orang
    // untuk mengabaikan kegagalan. Audit menyeluruh adalah pekerjaan
    // periksa-kesehatan.js.
    console.log('14. Menguji Konsistensi vote_count vs jumlah suara sebenarnya...');
    {
      const idsUji = [testPollingId, expiredPollingId, futurePollingId, timezonePollingId].filter(Boolean);

      const konsistensi = await pool.query(
        `SELECT
           COALESCE((SELECT SUM(o.vote_count) FROM polling_options o
                     WHERE o.polling_id = ANY($1::int[])), 0)::int AS total_counter,
           COALESCE((SELECT COUNT(*) FROM polling_votes v
                     WHERE v.polling_id = ANY($1::int[])), 0)::int AS total_suara`,
        [idsUji]
      );

      const totalCounter = konsistensi.rows[0].total_counter;
      const totalSuara = konsistensi.rows[0].total_suara;

      // Rincian per opsi hanya dicetak ketika melenceng: keluaran uji yang lulus
      // tetap ringkas, tetapi kegagalannya langsung bisa dilacak ke opsi mana.
      if (totalCounter !== totalSuara) {
        const rincian = await pool.query(
          `SELECT o.polling_id, o.id AS option_id, o.label, o.vote_count,
                  (SELECT COUNT(*) FROM polling_votes v WHERE v.option_id = o.id)::int AS suara_nyata
           FROM polling_options o
           WHERE o.polling_id = ANY($1::int[])
           ORDER BY o.polling_id, o.id`,
          [idsUji]
        );
        console.error('   Rincian penyimpangan per opsi:');
        rincian.rows
          .filter((r) => r.vote_count !== r.suara_nyata)
          .forEach((r) => console.error(
            `     polling ${r.polling_id} opsi ${r.option_id} "${r.label}": ` +
            `vote_count=${r.vote_count} tetapi suara nyata=${r.suara_nyata}`
          ));
      }

      assert(
        totalCounter === totalSuara,
        `vote_count melenceng dari jumlah suara sebenarnya: SUM(vote_count)=${totalCounter} ` +
        `tetapi COUNT(polling_votes)=${totalSuara}`
      );

      console.log(
        `   Penghitung konsisten (SUM(vote_count)=${totalCounter} = COUNT(polling_votes)=${totalSuara}).\n`
      );
    }

    console.log('================================================================');
    console.log('SEMUA 14 SKENARIO PENGUJIAN BACKEND BERHASIL DILALUI DENGAN SEMPURNA!');
    console.log('================================================================');
  } catch (err) {
    console.error('PENGUJIAN GAGAL:', err);
    process.exitCode = 1;
  } finally {
    console.log('\nMembersihkan fixture pengujian...');
    const idsToClean = [testPollingId, expiredPollingId, futurePollingId, timezonePollingId].filter(Boolean);
    for (const pollId of idsToClean) {
      await pool.query('DELETE FROM polling_votes WHERE polling_id = $1', [pollId]);
      await pool.query('DELETE FROM polling_options WHERE polling_id = $1', [pollId]);
      await pool.query('DELETE FROM polling WHERE id = $1', [pollId]);
    }
    console.log('Fixture pengujian berhasil dibersihkan.');
    await pool.end();
  }
}

runTests();
