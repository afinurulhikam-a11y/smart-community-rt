require('dotenv').config();
const { assertCanRunTest } = require('../src/config/db-guard');
assertCanRunTest('test-iuran-air-phase1');

const jwt = require('jsonwebtoken');
const { pool } = require('../src/config/database');

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
  let data;
  try {
    data = await res.json();
  } catch (e) {
    data = null;
  }

  const entry = { method, path, status: res.status, ok: res.ok, data };
  logHttpCalls.push(entry);
  return entry;
}

async function runHttpRegressionTests() {
  console.log('🚀 MEMULAI SUNGGUHAN HTTP INTEGRATION TEST SUITE - PHASE 1 IURAN AIR\n');

  const client = await pool.connect();
  let testWargaId;
  let testAdminId;
  let testKkId;
  let testJenisId;
  let testNoKk = 'TEST-KK-HTTP-99';

  let wargaToken;
  let adminToken;

  try {
    // 0. Setup Dummy Test Data di Database
    await client.query('BEGIN');

    await client.query(
      "DELETE FROM finances WHERE sumber = 'iuran' AND ref_id IN (SELECT id FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http')))"
    );
    await client.query(
      "DELETE FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http'))"
    );
    await client.query(
      "DELETE FROM bills WHERE created_by IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)",
      [testNoKk]
    );
    await client.query(
      "DELETE FROM pembacaan_meteran WHERE diisi_oleh IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)",
      [testNoKk]
    );
    await client.query(
      "DELETE FROM users WHERE username IN ('test_warga_http', 'test_admin_http')"
    );
    await client.query("DELETE FROM keluarga WHERE no_kk = $1", [testNoKk]);

    // Create KK
    const kkRes = await client.query(
      `INSERT INTO keluarga (no_kk, kepala_keluarga, alamat, langganan_sampah)
       VALUES ($1, 'Kepala Warga HTTP', 'Blok HTTP No 99', true) RETURNING id`,
      [testNoKk]
    );
    testKkId = kkRes.rows[0].id;

    // Create Warga User
    const wargaRes = await client.query(
      `INSERT INTO users (nama, username, password_hash, role, no_kk, is_active)
       VALUES ('Warga HTTP Test', 'test_warga_http', 'hash', 'warga', $1, true) RETURNING id, email, role, nama, username`,
      [testNoKk]
    );
    testWargaId = wargaRes.rows[0].id;
    wargaToken = jwt.sign(
      { id: testWargaId, email: wargaRes.rows[0].email, role: 'warga', nama: 'Warga HTTP Test', username: 'test_warga_http' },
      JWT_SECRET,
      { expiresIn: '1h' }
    );

    // Create Admin User
    const adminRes = await client.query(
      `INSERT INTO users (nama, username, password_hash, role, no_kk, is_active)
       VALUES ('Admin HTTP Test', 'test_admin_http', 'hash', 'admin', $1, true) RETURNING id, email, role, nama, username`,
      [testNoKk]
    );
    testAdminId = adminRes.rows[0].id;
    adminToken = jwt.sign(
      { id: testAdminId, email: adminRes.rows[0].email, role: 'admin', nama: 'Admin HTTP Test', username: 'test_admin_http' },
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
    console.log('✅ Setup data uji & token JWT HTTP sukses.\n');

    // ------------------------------------------------------------------
    // TEST SECURITY: Proteksi Warga terhadap Manipulasi req.body.periode
    // ------------------------------------------------------------------
    // 1. Warga mencoba mengirim periode lampau ("2025-01") -> req.body.periode diabaikan (tetap pakai periode berjalan)
    const resWargaPast = await httpReq('POST', '/meteran', { meteran_sekarang: 80, meteran_lalu: 50, periode: '2025-01' }, wargaToken);
    if (resWargaPast.data?.data?.periode === '2025-01') {
      throw new Error(`SECURITY TEST GAGAL: Warga berhasil memanipulasi periode lampau! Res: ${JSON.stringify(resWargaPast)}`);
    }

    // 2. Warga mencoba mengirim periode masa depan ("2027-12") -> req.body.periode diabaikan
    const resWargaFuture = await httpReq('POST', '/meteran', { meteran_sekarang: 9999, periode: '2027-12' }, wargaToken);
    if (resWargaFuture.data?.data?.periode === '2027-12') {
      throw new Error(`SECURITY TEST GAGAL: Warga berhasil memanipulasi periode masa depan! Res: ${JSON.stringify(resWargaFuture)}`);
    }

    // 3. Admin/pengurus mengirim format periode invalid -> Ditolak HTTP 400 Bad Request
    const resAdminInvalid = await httpReq('POST', '/meteran', { meteran_sekarang: 80, periode: 'invalid-period' }, adminToken);
    if (resAdminInvalid.status !== 400 || !resAdminInvalid.data?.message?.includes('Format periode')) {
      throw new Error(`SECURITY TEST GAGAL: Format periode invalid harus ditolak HTTP 400! Res: ${JSON.stringify(resAdminInvalid)}`);
    }

    console.log('✅ SECURITY TEST PASSED: Manipulasi periode oleh warga diabaikan & format invalid ditolak HTTP 400.\n');

    // ------------------------------------------------------------------
    // TEST 1: Periode Pertama -> Input Meteran Lalu & Sekarang via HTTP API
    // ------------------------------------------------------------------
    const p1 = '2026-01';
    await pool.query('DELETE FROM pembacaan_meteran WHERE keluarga_id = $1', [testKkId]);
    await pool.query('DELETE FROM bills WHERE keluarga_id = $1', [testKkId]);

    // GET /api/meteran/saya?periode=2026-01
    const resSaya1 = await httpReq('GET', `/meteran/saya?periode=${p1}`, null, wargaToken);
    if (resSaya1.status !== 200 || resSaya1.data?.data?.periode_pertama !== true) {
      throw new Error(`TEST 1 GAGAL GET /meteran/saya: ${JSON.stringify(resSaya1)}`);
    }

    // POST /api/meteran (Admin/Pengurus mengeset periode khusus p1 untuk setup pengujian)
    const resIsi1 = await httpReq('POST', '/meteran', { meteran_sekarang: 115, meteran_lalu: 100, periode: p1 }, adminToken);
    if (resIsi1.status !== 200 || !resIsi1.data?.success) {
      throw new Error(`TEST 1 GAGAL POST /meteran: ${JSON.stringify(resIsi1)}`);
    }
    console.log(`✅ TEST 1 PASSED: HTTP POST /api/meteran -> Status ${resIsi1.status} (${resIsi1.data.message})`);

    // ------------------------------------------------------------------
    // TEST 2: Periode Kedua -> Meteran Lalu Otomatis Dari Reading Terisi
    // ------------------------------------------------------------------
    const p2 = '2026-02';
    // POST /api/meteran (Admin mengeset periode p2 untuk setup pengujian)
    const resIsi2 = await httpReq('POST', '/meteran', { meteran_sekarang: 130, periode: p2 }, adminToken);
    if (resIsi2.status !== 200 || resIsi2.data?.data?.meteran_lalu !== 115) {
      throw new Error(`TEST 2 GAGAL: meteran_lalu otomatis harus 115. HTTP Res: ${JSON.stringify(resIsi2)}`);
    }
    console.log(`✅ TEST 2 PASSED: HTTP POST /api/meteran -> Status ${resIsi2.status} (meteran_lalu otomatis = 115)`);

    // ------------------------------------------------------------------
    // TEST 3: Bacaan Anomali Tidak Menjadi Acuan Periode Berikutnya
    // ------------------------------------------------------------------
    const p3 = '2026-03';
    // Admin menginput anomali (50 < 130) pada p3
    const resIsi3 = await httpReq('POST', '/meteran', { meteran_sekarang: 50, periode: p3 }, adminToken);
    if (resIsi3.status !== 200 || resIsi3.data?.data?.status !== 'anomali') {
      throw new Error(`TEST 3 GAGAL: Input 50 harus ditandai anomali. HTTP Res: ${JSON.stringify(resIsi3)}`);
    }

    const p4 = '2026-04';
    const resSaya4 = await httpReq('GET', `/meteran/saya?periode=${p4}`, null, wargaToken);
    if (resSaya4.status !== 200 || resSaya4.data?.data?.meteran_lalu !== 130) {
      throw new Error(`TEST 3 GAGAL GET /meteran/saya: Bacaan anomali (50) diabaikan; meteran_lalu harus 130! Res: ${JSON.stringify(resSaya4)}`);
    }
    console.log(`✅ TEST 3 PASSED: HTTP GET /api/meteran/saya?periode=2026-04 -> Status ${resSaya4.status} (meteran_lalu anomali diabaikan, dapat 130)`);

    // ------------------------------------------------------------------
    // TEST 4: Perhitungan Tagihan Manual vs Scheduler Identik
    // ------------------------------------------------------------------
    const p5 = '2026-05';
    // Admin melapor p5 (150)
    await httpReq('POST', '/meteran', { meteran_sekarang: 150, periode: p5 }, adminToken);

    // POST /api/bills/generate (Batch generate oleh Admin)
    const resGenBatch = await httpReq('POST', '/bills/generate', { jenis_iuran_id: testJenisId, bulan: p5, paksa: true }, adminToken);
    if (resGenBatch.status !== 200 && resGenBatch.status !== 201) {
      throw new Error(`TEST 4 GAGAL POST /bills/generate: ${JSON.stringify(resGenBatch)}`);
    }

    const resGetBillBatch = await httpReq('GET', `/bills?bulan=${p5}&keluarga_id=${testKkId}`, null, adminToken);
    const billBatch = resGetBillBatch.data?.data?.[0];
    if (!billBatch) throw new Error('TEST 4 GAGAL: Tagihan batch tidak ditemukan via GET /bills');

    // DELETE /api/bills/:id (Admin menghapus bill p5)
    const resDelBill = await httpReq('DELETE', `/bills/${billBatch.id}`, null, adminToken);
    if (resDelBill.status !== 200) throw new Error(`TEST 4 GAGAL DELETE /bills/${billBatch.id}`);

    // POST /api/bills (Single bill creation oleh Admin)
    const resCreateManual = await httpReq('POST', '/bills', {
      keluarga_id: testKkId,
      jenis_iuran_id: testJenisId,
      bulan: p5,
      meteran_sekarang: 150,
    }, adminToken);
    if (resCreateManual.status !== 201) throw new Error(`TEST 4 GAGAL POST /bills: ${JSON.stringify(resCreateManual)}`);
    const billManual = resCreateManual.data?.data;

    if (Number(billBatch.nominal) !== Number(billManual.nominal) ||
        billBatch.meteran_lalu !== billManual.meteran_lalu ||
        billBatch.meteran_sekarang !== billManual.meteran_sekarang ||
        billBatch.biaya_sampah !== billManual.biaya_sampah) {
      throw new Error(`TEST 4 GAGAL: Rincian batch dan manual tidak identik! Batch: ${JSON.stringify(billBatch)}, Manual: ${JSON.stringify(billManual)}`);
    }
    console.log(`✅ TEST 4 PASSED: HTTP POST /api/bills/generate & POST /api/bills -> Status 200 & 201 (Nominal identik Rp ${billManual.nominal})`);

    // ------------------------------------------------------------------
    // TEST 5: Pelanggan Tanpa Langganan Sampah Tidak Dikenakan Biaya Sampah
    // ------------------------------------------------------------------
    // PUT /api/bills/langganan-sampah (Warga menonaktifkan langganan sampah)
    const resSampahOff = await httpReq('PUT', '/bills/langganan-sampah', { langganan_sampah: false }, wargaToken);
    if (resSampahOff.status !== 200) throw new Error(`TEST 5 GAGAL PUT /bills/langganan-sampah: ${JSON.stringify(resSampahOff)}`);

    const p6 = '2026-06';
    await httpReq('POST', '/meteran', { meteran_sekarang: 160, periode: p6 }, adminToken);

    // POST /api/bills (Manual)
    const resCreateP6 = await httpReq('POST', '/bills', {
      keluarga_id: testKkId,
      jenis_iuran_id: testJenisId,
      bulan: p6,
      meteran_sekarang: 160,
    }, adminToken);
    if (resCreateP6.status !== 201 || resCreateP6.data?.data?.biaya_sampah !== 0) {
      throw new Error(`TEST 5 GAGAL: KK non-sampah biaya_sampah harus 0! Res: ${JSON.stringify(resCreateP6)}`);
    }
    console.log(`✅ TEST 5 PASSED: HTTP PUT /bills/langganan-sampah & POST /api/bills -> Status ${resCreateP6.status} (biaya_sampah = 0)`);

    // ------------------------------------------------------------------
    // TEST 6: Hapus Tagihan Lama Tidak Memutus Histori Meteran
    // ------------------------------------------------------------------
    const p6BillId = resCreateP6.data?.data?.id;
    // DELETE /api/bills/:id
    const resDelP6 = await httpReq('DELETE', `/bills/${p6BillId}`, null, adminToken);
    if (resDelP6.status !== 200) throw new Error(`TEST 6 GAGAL DELETE /bills/${p6BillId}`);

    // GET /api/meteran/saya?periode=2026-07
    const p7 = '2026-07';
    const resSaya7 = await httpReq('GET', `/meteran/saya?periode=${p7}`, null, wargaToken);
    if (resSaya7.status !== 200 || resSaya7.data?.data?.meteran_lalu !== 160) {
      throw new Error(`TEST 6 GAGAL: Setelah tagihan p6 dihapus, meteran_lalu p7 tetap harus 160! Res: ${JSON.stringify(resSaya7)}`);
    }
    console.log(`✅ TEST 6 PASSED: HTTP DELETE /api/bills & GET /api/meteran/saya -> Status ${resSaya7.status} (meteran_lalu tetap 160 dari pembacaan_meteran)`);

    // ------------------------------------------------------------------
    // TEST 7: Jenis Iuran Nonaktif Ditolak pada Pembuatan Tagihan
    // ------------------------------------------------------------------
    const jenisNonaktifRes = await pool.query(
      `INSERT INTO jenis_iuran (nama_iuran, nominal_default, periode, is_aktif, tipe_hitung, tarif_per_m3, abondement, biaya_sampah)
       VALUES ('Air Nonaktif HTTP Test', 0, 'bulanan', false, 'meteran', 3000, 25000, 30000) RETURNING id`
    );
    const nonaktifId = jenisNonaktifRes.rows[0].id;

    // POST /api/bills dengan jenis_iuran_id nonaktif
    const resNonaktif = await httpReq('POST', '/bills', {
      keluarga_id: testKkId,
      jenis_iuran_id: nonaktifId,
      bulan: '2026-08',
    }, adminToken);

    if (resNonaktif.status !== 400 || !resNonaktif.data?.message?.includes('dinonaktifkan')) {
      throw new Error(`TEST 7 GAGAL: Pembuatan tagihan untuk jenis iuran nonaktif harus ditolak HTTP 400! Res: ${JSON.stringify(resNonaktif)}`);
    }

    await pool.query('DELETE FROM jenis_iuran WHERE id = $1', [nonaktifId]);
    console.log(`✅ TEST 7 PASSED: HTTP POST /api/bills -> Status ${resNonaktif.status} (${resNonaktif.data.message})`);

    // ------------------------------------------------------------------
    // TEST 8: Idempotensi Pembayaran & Kas RT (Bayar Tunai 2x)
    // ------------------------------------------------------------------
    const p8 = '2026-08';
    await httpReq('PUT', '/bills/langganan-sampah', { langganan_sampah: true }, wargaToken);
    await httpReq('POST', '/meteran', { meteran_sekarang: 170, periode: p8 }, adminToken);

    // POST /api/bills (Create p8 bill)
    const resBill8 = await httpReq('POST', '/bills', {
      keluarga_id: testKkId,
      jenis_iuran_id: testJenisId,
      bulan: p8,
      meteran_sekarang: 170,
    }, adminToken);
    const bill8Id = resBill8.data?.data?.id;

    // POST /api/bills/:id/pay (Bayar tunai ke-1 oleh Admin)
    const resPay1 = await httpReq('POST', `/bills/${bill8Id}/pay`, { metode_bayar: 'tunai' }, adminToken);
    if (resPay1.status !== 200) throw new Error(`TEST 8 GAGAL POST /bills/${bill8Id}/pay ke-1: ${JSON.stringify(resPay1)}`);

    const countFinances1 = (await pool.query(
      `SELECT COUNT(*)::int AS c FROM finances WHERE sumber = 'iuran' AND ref_id IN (
         SELECT id FROM bill_payments WHERE bill_id = $1
       )`,
      [bill8Id]
    )).rows[0].c;
    if (countFinances1 !== 1) throw new Error(`TEST 8 GAGAL: Kas RT harusnya 1 baris, dapat ${countFinances1}`);

    // POST /api/bills/:id/pay (Bayar tunai ke-2 pada tagihan yang sudah lunas)
    const resPay2 = await httpReq('POST', `/bills/${bill8Id}/pay`, { metode_bayar: 'tunai' }, adminToken);
    if (resPay2.status !== 400 || !resPay2.data?.message?.includes('lunas')) {
      throw new Error(`TEST 8 GAGAL POST /bills/${bill8Id}/pay ke-2: Diharapkan HTTP 400 Lunas, dapat ${JSON.stringify(resPay2)}`);
    }

    const countFinances2 = (await pool.query(
      `SELECT COUNT(*)::int AS c FROM finances WHERE sumber = 'iuran' AND ref_id IN (
         SELECT id FROM bill_payments WHERE bill_id = $1
       )`,
      [bill8Id]
    )).rows[0].c;
    if (countFinances2 !== 1) throw new Error(`TEST 8 GAGAL: Kas RT terduplikasi! Dapat ${countFinances2}`);

    console.log(`✅ TEST 8 PASSED: HTTP POST /api/bills/:id/pay -> Pembayaran ke-1 Status 200, Pembayaran ke-2 Status ${resPay2.status} (Kas RT tetap 1 baris).`);

    // ------------------------------------------------------------------
    // CLEANUP DATA UJI
    // ------------------------------------------------------------------
    await pool.query("DELETE FROM finances WHERE sumber = 'iuran' AND ref_id IN (SELECT id FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http')))");
    await pool.query("DELETE FROM bill_payments WHERE user_id IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http'))");
    await pool.query("DELETE FROM bills WHERE created_by IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)", [testNoKk]);
    await pool.query("DELETE FROM pembacaan_meteran WHERE diisi_oleh IN (SELECT id FROM users WHERE username IN ('test_warga_http', 'test_admin_http')) OR keluarga_id IN (SELECT id FROM keluarga WHERE no_kk = $1)", [testNoKk]);
    await pool.query("DELETE FROM users WHERE username IN ('test_warga_http', 'test_admin_http')");
    await pool.query("DELETE FROM keluarga WHERE no_kk = $1", [testNoKk]);

    console.log('\n🎉 SELURUH 8 SKENARIO HTTP INTEGRATION TEST PASSED PERFECTLY!\n');

    console.log('═══════════════════════════════════════════════════════════════════════════');
    console.log('                 LAPORAN PANGGILAN HTTP INTEGRATION TEST                  ');
    console.log('═══════════════════════════════════════════════════════════════════════════');
    logHttpCalls.forEach((call, i) => {
      console.log(`${String(i + 1).padStart(2, ' ')}. [${call.method.padEnd(6, ' ')}] ${call.path.padEnd(35, ' ')} ➔ Status ${call.status} ${call.ok ? 'OK' : 'ERR'}`);
    });
    console.log('═══════════════════════════════════════════════════════════════════════════\n');

  } catch (err) {
    console.error('\n❌ HTTP INTEGRATION TEST FAILED:', err.message, err.stack);
    process.exit(1);
  } finally {
    client.release();
    process.exit(0);
  }
}

runHttpRegressionTests();
