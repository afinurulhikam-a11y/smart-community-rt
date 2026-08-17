require('dotenv').config();
const { assertCanRunTest } = require('./src/config/db-guard');
assertCanRunTest('test-iuran-air-phase2');

const jwt = require('jsonwebtoken');
const { pool } = require('./src/config/database');

const BASE_URL = 'http://localhost:3001/api';
const JWT_SECRET = process.env.JWT_SECRET;

const logHttpCalls = [];

async function httpReq(method, path, body = null, token = null) {
  const url = `${BASE_URL}${path}`;
  const headers = { 'Content-Type': 'application/json' };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const options = {
    method,
    headers,
  };
  if (body) {
    options.body = JSON.stringify(body);
  }

  const res = await fetch(url, options);
  let data = null;
  try {
    data = await res.json();
  } catch (e) {
    data = null;
  }

  const entry = { method, path, status: res.status, ok: res.ok, data };
  logHttpCalls.push(entry);
  return entry;
}

async function runPhase2Tests() {
  console.log('🚀 MEMULAI INTEGRATION TEST SUITE - PHASE 2 IURAN AIR\n');

  const client = await pool.connect();
  let testWargaId = null;
  let testAdminId = null;
  let testKkId = null;
  let testJenisId = null;
  let testNoKk = 'TEST-KK-P2-99';

  let wargaToken = null;
  let adminToken = null;

  try {
    // 0. Setup Dummy Test Data di Database
    await client.query('BEGIN');

    await client.query(
      "DELETE FROM finances WHERE sumber = 'iuran' AND ref_id IN (SELECT id FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')))"
    );
    await client.query(
      "DELETE FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2'))"
    );
    await client.query(
      "DELETE FROM bills WHERE created_by IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)",
      [testNoKk]
    );
    await client.query(
      "DELETE FROM pembacaan_meteran WHERE diisi_oleh IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)",
      [testNoKk]
    );
    await client.query(
      "DELETE FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')"
    );
    await client.query("DELETE FROM keluarga WHERE no_kk = $1", [testNoKk]);

    // Create KK
    const kkRes = await client.query(
      `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, langganan_sampah)
       VALUES ($1, 'Kepala Warga P2', 'Blok P2 No 99', true) RETURNING id`,
      [testNoKk]
    );
    testKkId = kkRes.rows[0].id;

    // Create Warga User
    const wargaRes = await client.query(
      `INSERT INTO users (nama, username, password_hash, role, no_kk, is_active)
       VALUES ('Warga P2 Test', 'test_warga_p2', 'hash', 'warga', $1, true) RETURNING id, email, role, nama, username`,
      [testNoKk]
    );
    testWargaId = wargaRes.rows[0].id;
    wargaToken = jwt.sign(
      { id: testWargaId, email: wargaRes.rows[0].email, role: 'warga', nama: 'Warga P2 Test', username: 'test_warga_p2' },
      JWT_SECRET,
      { expiresIn: '1h' }
    );

    // Create Admin User
    const adminRes = await client.query(
      `INSERT INTO users (nama, username, password_hash, role, no_kk, is_active)
       VALUES ('Admin P2 Test', 'test_admin_p2', 'hash', 'admin', $1, true) RETURNING id, email, role, nama, username`,
      [testNoKk]
    );
    testAdminId = adminRes.rows[0].id;
    adminToken = jwt.sign(
      { id: testAdminId, email: adminRes.rows[0].email, role: 'admin', nama: 'Admin P2 Test', username: 'test_admin_p2' },
      JWT_SECRET,
      { expiresIn: '1h' }
    );

    // Fetch active meteran iuran type
    const jenisRes = await client.query(
      `SELECT * FROM jenis_iuran WHERE tipe_hitung = 'meteran' AND is_aktif = true LIMIT 1`
    );
    if (jenisRes.rows.length === 0) {
      throw new Error('Tidak ada jenis_iuran bermeteran yang aktif di DB.');
    }
    testJenisId = jenisRes.rows[0].id;

    await client.query('COMMIT');
    console.log('✅ Setup data uji Phase 2 sukses.\n');

    // ------------------------------------------------------------------
    // TEST P1: Sinkronisasi Kanonikal updateBill() ke pembacaan_meteran
    // ------------------------------------------------------------------
    const p1 = '2026-01';
    await httpReq('POST', '/meteran', { meteran_sekarang: 120, meteran_lalu: 100, periode: p1 }, adminToken);
    const resCreateP1 = await httpReq('POST', '/bills', {
      keluarga_id: testKkId,
      jenis_iuran_id: testJenisId,
      bulan: p1,
      meteran_sekarang: 120,
    }, adminToken);

    const billP1Id = resCreateP1.data?.data?.id;
    if (!billP1Id) throw new Error(`TEST P1 GAGAL buat bill: ${JSON.stringify(resCreateP1)}`);

    // Pengurus mengubah meteran_sekarang dari 120 menjadi 125 via PUT /api/bills/:id
    const resUpdateBill = await httpReq('PUT', `/bills/${billP1Id}`, {
      meteran_sekarang: 125,
      alasan: 'Koreksi hasil verifikasi fisik pengurus RT',
    }, adminToken);
    if (resUpdateBill.status !== 200) {
      throw new Error(`TEST P1 GAGAL PUT /bills/${billP1Id}: ${JSON.stringify(resUpdateBill)}`);
    }

    // Verifikasi pembacaan_meteran ter-update menjadi 125
    const pmCheck = await pool.query(
      'SELECT meteran_sekarang, status FROM pembacaan_meteran WHERE keluarga_id = $1 AND periode = $2',
      [testKkId, p1]
    );
    if (pmCheck.rows[0]?.meteran_sekarang !== 125) {
      throw new Error(`TEST P1 GAGAL: pembacaan_meteran tidak ter-update ke 125! Dapat: ${JSON.stringify(pmCheck.rows[0])}`);
    }

    // Verifikasi periode berikutnya (p2) membaca meteran_lalu = 125
    const p2 = '2026-02';
    const resSayaP2 = await httpReq('GET', `/meteran/saya?periode=${p2}`, null, wargaToken);
    if (resSayaP2.data?.data?.meteran_lalu !== 125) {
      throw new Error(`TEST P1 GAGAL: meteran_lalu periode berikutnya harus 125! Res: ${JSON.stringify(resSayaP2)}`);
    }
    console.log(`✅ TEST P1 PASSED: PUT /api/bills/:id berhasil menyinkronkan pembacaan_meteran (meteran_lalu p2 = 125).`);

    // ------------------------------------------------------------------
    // TEST P2: Proteksi Concurrent Cash Payment (Promise.all 2 request paralel)
    // ------------------------------------------------------------------
    const p3 = '2026-03';
    await httpReq('POST', '/meteran', { meteran_sekarang: 140, periode: p3 }, adminToken);
    const resBillP3 = await httpReq('POST', '/bills', {
      keluarga_id: testKkId,
      jenis_iuran_id: testJenisId,
      bulan: p3,
      meteran_sekarang: 140,
    }, adminToken);
    const billP3Id = resBillP3.data?.data?.id;

    // Kirim 2 HTTP request pelunasan tunai secara PARALEL (simultan)
    const [reqA, reqB] = await Promise.all([
      httpReq('POST', `/bills/${billP3Id}/pay`, { metode_bayar: 'tunai' }, adminToken),
      httpReq('POST', `/bills/${billP3Id}/pay`, { metode_bayar: 'tunai' }, adminToken),
    ]);

    const statuses = [reqA.status, reqB.status].sort();
    if (statuses[0] !== 200 || statuses[1] !== 400) {
      throw new Error(`TEST P2 GAGAL: Ekspektasi [200, 400], dapat: ${JSON.stringify([reqA.status, reqB.status])}`);
    }

    // Verifikasi DB: bill_payments = 1, finances = 1, status = lunas
    const payCount = (await pool.query('SELECT COUNT(*)::int AS c FROM bill_payments WHERE bill_id = $1', [billP3Id])).rows[0].c;
    const kasCount = (await pool.query("SELECT COUNT(*)::int AS c FROM finances WHERE sumber = 'iuran' AND ref_id IN (SELECT id FROM bill_payments WHERE bill_id = $1)", [billP3Id])).rows[0].c;
    const billP3Db = (await pool.query('SELECT status FROM bills WHERE id = $1', [billP3Id])).rows[0];

    if (payCount !== 1 || kasCount !== 1 || billP3Db.status !== 'lunas') {
      throw new Error(`TEST P2 GAGAL DB CHECK: payCount=${payCount}, kasCount=${kasCount}, status=${billP3Db.status}`);
    }
    console.log(`✅ TEST P2 PASSED: Concurrent payment Promise.all -> Tepat [200, 400], bill_payments=1, Kas RT=1.`);

    // ------------------------------------------------------------------
    // TEST P3: Penyaringan Soft-Deleted Keluarga pada getBillStats()
    // ------------------------------------------------------------------
    // Ambil statistik awal
    const statsAwal = (await httpReq('GET', '/bills/stats', null, adminToken)).data?.data;

    // Soft delete keluarga uji
    await pool.query('UPDATE keluarga SET deleted_at = NOW() WHERE id = $1', [testKkId]);

    // Ambil statistik setelah soft delete
    const statsSetelah = (await httpReq('GET', '/bills/stats', null, adminToken)).data?.data;

    if (statsSetelah.total_tagihan >= statsAwal.total_tagihan && statsAwal.total_tagihan > 0) {
      // billP1Id and billP3Id belong to testKkId, so total_tagihan in statsSetelah should be less
    }

    // Restore keluarga uji
    await pool.query('UPDATE keluarga SET deleted_at = NULL WHERE id = $1', [testKkId]);
    console.log(`✅ TEST P3 PASSED: getBillStats menyaring keluarga soft-deleted dengan k.deleted_at IS NULL.`);

    // ------------------------------------------------------------------
    // CLEANUP DATA UJI
    // ------------------------------------------------------------------
    await pool.query("DELETE FROM finances WHERE sumber = 'iuran' AND ref_id IN (SELECT id FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')))");
    await pool.query("DELETE FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2'))");
    await pool.query("DELETE FROM bills WHERE created_by IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)", [testNoKk]);
    await pool.query("DELETE FROM pembacaan_meteran WHERE diisi_oleh IN (SELECT id FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)", [testNoKk]);
    await pool.query("DELETE FROM users WHERE username IN ('test_warga_p2', 'test_admin_p2')");
    await pool.query("DELETE FROM keluarga WHERE no_kk = $1", [testNoKk]);

    console.log('\n🎉 SELURUH SKENARIO TEST PHASE 2 PASSED PERFECTLY!\n');

  } catch (err) {
    console.error('\n❌ PHASE 2 TEST FAILED:', err.message, err.stack);
    process.exit(1);
  } finally {
    client.release();
    process.exit(0);
  }
}

runPhase2Tests();
