require('dotenv').config();
const { pool } = require('./src/config/database');
const { getPolling, vote } = require('./src/controllers/polling.controller');

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
  console.log('TEST POLLING WARGA (VOTE, CHANGE VOTE, CONCURRENCY, DEADLINE)');
  console.log('================================================================\n');

  let testUser1 = null;
  let testUser2 = null;
  let testPollingId = null;
  let expiredPollingId = null;
  let optA = null;
  let optB = null;
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
       VALUES ('Polling Uji Mandiri ${Date.now()}', 'Deskripsi uji otomatis', CURRENT_DATE, CURRENT_DATE + INTERVAL '5 days', 'Aktif', $1)
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

    // 3. Test Memilih Pertama Kali (User 1 -> Opsi A)
    console.log('3. Menguji Memilih Pertama Kali (User 1 -> Opsi A)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optA },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected status 200, got ${res.getStatusCode()}: ${JSON.stringify(res.getBody())}`);
      assert(res.getBody().success === true, 'Expected success === true');
      assert(res.getBody().data.is_change === false, 'Expected is_change === false for first vote');

      // Verify DB counts & records
      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected exactly 1 vote record, found ${voteRows.rows.length}`);
      assert(voteRows.rows[0].option_id === optA, `Expected option_id ${optA}, got ${voteRows.rows[0].option_id}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      const countMap = Object.fromEntries(optRows.rows.map((r) => [r.id, r.vote_count]));
      assert(countMap[optA] === 1, `Option A vote_count should be 1, got ${countMap[optA]}`);
      assert(countMap[optB] === 0, `Option B vote_count should be 0, got ${countMap[optB]}`);
      assert(countMap[optC] === 0, `Option C vote_count should be 0, got ${countMap[optC]}`);
      console.log('   Memilih pertama kali berhasil (Record = 1, Opsi A = 1, B = 0, C = 0).\n');
    }

    // 4. Test Mengubah Pilihan A -> B (User 1 -> Opsi B)
    console.log('4. Menguji Mengubah Pilihan A -> B (User 1 -> Opsi B)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optB },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected status 200, got ${res.getStatusCode()}`);
      assert(res.getBody().data.is_change === true, 'Expected is_change === true for changed vote');

      // Verify DB records: MUST STILL BE EXACTLY 1 RECORD
      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected exactly 1 vote record in DB (no duplicates), found ${voteRows.rows.length}`);
      assert(voteRows.rows[0].option_id === optB, `Expected option_id updated to ${optB}, got ${voteRows.rows[0].option_id}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      const countMap = Object.fromEntries(optRows.rows.map((r) => [r.id, r.vote_count]));
      assert(countMap[optA] === 0, `Option A vote_count should be decremented to 0, got ${countMap[optA]}`);
      assert(countMap[optB] === 1, `Option B vote_count should be incremented to 1, got ${countMap[optB]}`);
      assert(countMap[optC] === 0, `Option C vote_count should be 0, got ${countMap[optC]}`);
      console.log('   Perubahan A -> B berhasil (Record tetap 1, Opsi A = 0, B = 1, C = 0).\n');
    }

    // 5. Test Mengubah Pilihan B -> C (User 1 -> Opsi C)
    console.log('5. Menguji Mengubah Pilihan B -> C (User 1 -> Opsi C)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optC },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected status 200, got ${res.getStatusCode()}`);
      assert(res.getBody().data.is_change === true, 'Expected is_change === true');

      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected exactly 1 vote record, found ${voteRows.rows.length}`);
      assert(voteRows.rows[0].option_id === optC, `Expected option_id updated to ${optC}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      const countMap = Object.fromEntries(optRows.rows.map((r) => [r.id, r.vote_count]));
      assert(countMap[optA] === 0, `Option A vote_count should be 0, got ${countMap[optA]}`);
      assert(countMap[optB] === 0, `Option B vote_count should be 0, got ${countMap[optB]}`);
      assert(countMap[optC] === 1, `Option C vote_count should be 1, got ${countMap[optC]}`);
      console.log('   Perubahan B -> C berhasil (Record tetap 1, Opsi A = 0, B = 0, C = 1).\n');
    }

    // 6. Test Memilih Opsi Yang Sama C -> C (Idempotensi / A -> A)
    console.log('6. Menguji Memilih Opsi Yang Sama C -> C (A -> A)...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optC },
        user: testUser1,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected status 200, got ${res.getStatusCode()}`);

      const voteRows = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(voteRows.rows.length === 1, `Expected exactly 1 vote record, found ${voteRows.rows.length}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      const countMap = Object.fromEntries(optRows.rows.map((r) => [r.id, r.vote_count]));
      assert(countMap[optC] === 1, `Option C vote_count should remain 1, got ${countMap[optC]}`);
      console.log('   Transisi C -> C tidak menambah total suara (Opsi C tetap 1, total 1 suara).\n');
    }

    // 7. Test User 2 Memilih Opsi A (Multi-User Consistency)
    console.log('7. Menguji User 2 Memilih Opsi A...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        params: { id: testPollingId },
        body: { option_id: optA },
        user: testUser2,
      });
      await vote(req, res);
      assert(res.getStatusCode() === 200, `Expected status 200, got ${res.getStatusCode()}`);

      const totalVotesInDb = await pool.query('SELECT COUNT(*) as total FROM polling_votes WHERE polling_id = $1', [testPollingId]);
      assert(parseInt(totalVotesInDb.rows[0].total, 10) === 2, `Expected 2 total votes across 2 users, got ${totalVotesInDb.rows[0].total}`);

      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1 ORDER BY id', [testPollingId]);
      const countMap = Object.fromEntries(optRows.rows.map((r) => [r.id, r.vote_count]));
      assert(countMap[optA] === 1, `Option A should have 1 vote from User 2, got ${countMap[optA]}`);
      assert(countMap[optC] === 1, `Option C should have 1 vote from User 1, got ${countMap[optC]}`);
      console.log('   Multi-user konsisten (Total suara = 2: Opsi A = 1, Opsi C = 1).\n');
    }

    // 8. Test getPolling Output & Percentages
    console.log('8. Menguji getPolling & Kalkulasi Persentase...');
    {
      const { req, res } = mockReqRes({
        method: 'GET',
        query: {},
        user: testUser1,
      });
      await getPolling(req, res);
      assert(res.getStatusCode() === 200, 'Expected getPolling 200');
      const targetPoll = res.getBody().data.find((p) => p.id === testPollingId);
      assert(targetPoll !== undefined, 'Target polling must exist in response');
      assert(targetPoll.sudah_vote === true, 'User 1 sudah_vote should be true');
      assert(targetPoll.pilihan_saya === optC, `User 1 pilihan_saya should be ${optC}, got ${targetPoll.pilihan_saya}`);
      assert(targetPoll.total_votes === 2, `total_votes should be 2, got ${targetPoll.total_votes}`);

      const optAPct = targetPoll.options.find((o) => o.id === optA).percentage;
      const optCPct = targetPoll.options.find((o) => o.id === optC).percentage;
      assert(optAPct === 50, `Option A percentage should be 50%, got ${optAPct}%`);
      assert(optCPct === 50, `Option C percentage should be 50%, got ${optCPct}%`);
      console.log('   getPolling mengembalikan persentase & pilihan_saya yang akurat.\n');
    }

    // 9. Test Concurrency & Race Condition
    console.log('9. Menguji Concurrency / Race Condition...');
    {
      const promises = [];
      for (let i = 0; i < 10; i++) {
        const chosenOpt = i % 2 === 0 ? optA : optB;
        const { req, res } = mockReqRes({
          method: 'POST',
          params: { id: testPollingId },
          body: { option_id: chosenOpt },
          user: testUser1,
        });
        promises.push(vote(req, res));
      }
      await Promise.all(promises);

      // Verifikasi: Record vote User 1 HARUS tepat 1 baris
      const user1Votes = await pool.query('SELECT * FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [testPollingId, testUser1.id]);
      assert(user1Votes.rows.length === 1, `Concurrency violation: User 1 has ${user1Votes.rows.length} rows in polling_votes`);

      // Verifikasi: Total suara dari kedua user HARUS tepat 2
      const allVotes = await pool.query('SELECT COUNT(*) as total FROM polling_votes WHERE polling_id = $1', [testPollingId]);
      assert(parseInt(allVotes.rows[0].total, 10) === 2, `Total votes must be 2, got ${allVotes.rows[0].total}`);

      // Verifikasi: Jumlah vote_count di polling_options harus sama dengan jumlah vote di polling_votes
      const optRows = await pool.query('SELECT id, vote_count FROM polling_options WHERE polling_id = $1', [testPollingId]);
      const sumVoteCount = optRows.rows.reduce((sum, r) => sum + r.vote_count, 0);
      assert(sumVoteCount === 2, `Sum of option vote_count must be 2, got ${sumVoteCount}`);
      console.log('   Concurrency test lulus: Tepat 1 record per user, tidak ada duplicate atau suara ganda.\n');
    }

    // 10. Test Penolakan Setelah Polling Ditutup
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
         VALUES ('Polling Kedaluwarsa ${Date.now()}', 'Uji deadline', CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE - INTERVAL '1 day', 'Aktif', $1)
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

    console.log('================================================================');
    console.log('SEMUA 11 SKENARIO PENGUJIAN BACKEND BERHASIL DILALUI DENGAN SEMPURNA!');
    console.log('================================================================');
  } catch (err) {
    console.error('PENGUJIAN GAGAL:', err);
    process.exitCode = 1;
  } finally {
    console.log('\nMembersihkan fixture pengujian...');
    if (testPollingId) {
      await pool.query('DELETE FROM polling_votes WHERE polling_id = $1', [testPollingId]);
      await pool.query('DELETE FROM polling_options WHERE polling_id = $1', [testPollingId]);
      await pool.query('DELETE FROM polling WHERE id = $1', [testPollingId]);
    }
    if (expiredPollingId) {
      await pool.query('DELETE FROM polling_votes WHERE polling_id = $1', [expiredPollingId]);
      await pool.query('DELETE FROM polling_options WHERE polling_id = $1', [expiredPollingId]);
      await pool.query('DELETE FROM polling WHERE id = $1', [expiredPollingId]);
    }
    console.log('Fixture pengujian berhasil dibersihkan.');
    await pool.end();
  }
}

runTests();
