require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-agenda-crud');

const { pool } = require('../src/config/database');
const { getAgenda, createAgenda, updateAgenda, deleteAgenda } = require('../src/controllers/agenda.controller');

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
}

function mockReqRes({ method = 'GET', query = {}, body = {}, params = {}, user = null } = {}) {
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

async function runAgendaTests() {
  console.log('================================================================');
  console.log('TEST BACKEND AGENDA & KEGIATAN CRUD & TIME VALIDATION');
  console.log('================================================================\n');

  let testUser = null;
  let createdAgendaId = null;
  const testEmail = `test_agenda_${Date.now()}@test.local`;

  try {
    // 1. Setup isolated user
    console.log('1. Membuat akun uji pengurus...');
    const uRes = await pool.query(
      `INSERT INTO users (email, role, nama, password_hash) 
       VALUES ($1, 'pengurus_rt', 'Pengurus Agenda Test', 'hash') 
       RETURNING id, email, role, nama`,
      [testEmail]
    );
    testUser = uRes.rows[0];
    console.log(`   Akun dibuat: ${testUser.nama} (ID: ${testUser.id})\n`);

    // 2. Test createAgenda with HH:mm:ss format (from Flutter)
    console.log('2. Menguji createAgenda dengan waktu HH:mm:ss ("08:00:00")...');
    {
      const { req, res } = mockReqRes({
        method: 'POST',
        user: testUser,
        body: {
          judul: 'Kerja Bakti Bersama RT',
          deskripsi: 'Membersihkan selokan dan taman warga',
          tipe: 'Kegiatan',
          tanggal: '2026-08-20',
          waktu_mulai: '08:00:00',
          waktu_selesai: '11:30:00',
          lokasi: 'Lapangan RT 01',
          status: 'Akan Datang',
        },
      });

      await createAgenda(req, res);
      assert(res.getStatusCode() === 201, `Expected 201, got ${res.getStatusCode()}: ${JSON.stringify(res.getBody())}`);
      assert(res.getBody().success === true, 'Expected success === true');
      createdAgendaId = res.getBody().data.id;
      assert(createdAgendaId != null, 'Expected created agenda ID to be present');
      console.log(`   Agenda berhasil dibuat (ID: ${createdAgendaId}, Judul: ${res.getBody().data.judul})\n`);
    }

    // 3. Test getAgenda
    console.log('3. Menguji getAgenda...');
    {
      const { req, res } = mockReqRes({
        method: 'GET',
        user: testUser,
        query: { status: 'Akan Datang' },
      });

      await getAgenda(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      const found = res.getBody().data.find((a) => a.id === createdAgendaId);
      assert(found != null, 'Created agenda should be found in list');
      assert(found.tanggal === '2026-08-20', `Expected date '2026-08-20', got: ${found.tanggal}`);
      console.log(`   getAgenda berhasil mengembalikan ${res.getBody().count} data.\n`);
    }

    // 4. Test updateAgenda with status 'Akan Datang' and HH:mm format
    console.log('4. Menguji updateAgenda dengan status "Akan Datang" dan waktu HH:mm...');
    {
      const { req, res } = mockReqRes({
        method: 'PUT',
        user: testUser,
        params: { id: createdAgendaId },
        body: {
          judul: 'Kerja Bakti Bersama RT (Revisi)',
          deskripsi: 'Membersihkan selokan, taman, dan balai warga',
          tipe: 'Kegiatan',
          tanggal: '2026-08-21',
          waktu_mulai: '07:30',
          waktu_selesai: '10:30',
          lokasi: 'Balai Warga RT 01',
          status: 'Akan Datang',
        },
      });

      await updateAgenda(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}: ${JSON.stringify(res.getBody())}`);
      assert(res.getBody().success === true, 'Expected success === true');
      assert(res.getBody().data.judul === 'Kerja Bakti Bersama RT (Revisi)', 'Judul should be updated');
      console.log('   updateAgenda berhasil diperbarui.\n');
    }

    // 5. Test deleteAgenda
    console.log('5. Menguji deleteAgenda...');
    {
      const { req, res } = mockReqRes({
        method: 'DELETE',
        user: testUser,
        params: { id: createdAgendaId },
      });

      await deleteAgenda(req, res);
      assert(res.getStatusCode() === 200, `Expected 200, got ${res.getStatusCode()}`);
      assert(res.getBody().success === true, 'Expected success === true');
      console.log('   deleteAgenda berhasil dihapus (soft delete).\n');
    }

    console.log('================================================================');
    console.log('SEMUA PENGUJIAN AGENDA & KEGIATAN BERHASIL 100%!');
    console.log('================================================================');
  } catch (err) {
    console.error('PENGUJIAN GAGAL:', err);
    process.exitCode = 1;
  } finally {
    if (createdAgendaId) {
      await pool.query('DELETE FROM agenda WHERE id = $1', [createdAgendaId]);
    }
    if (testUser?.id) {
      await pool.query('DELETE FROM users WHERE id = $1', [testUser.id]);
    }
    await pool.end();
  }
}

runAgendaTests();
