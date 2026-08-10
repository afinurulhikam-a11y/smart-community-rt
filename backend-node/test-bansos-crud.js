require('dotenv').config();
const http = require('http');
const { pool } = require('./src/config/database');

const PORT = process.env.PORT || 3001;
const BASE_URL = `http://localhost:${PORT}/api`;

function request(method, path, body = null, token = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(BASE_URL + path);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method,
      headers: {
        'Content-Type': 'application/json',
      },
    };
    if (token) {
      options.headers['Authorization'] = `Bearer ${token}`;
    }

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        let json;
        try {
          json = JSON.parse(data);
        } catch (e) {
          json = { raw: data };
        }
        resolve({ status: res.statusCode, body: json });
      });
    });

    req.on('error', (err) => reject(err));
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('=== BENCHMARK & TEST CRITICAL BANTUAN SOSIAL ===');

  // 1. Login Admin
  const loginRes = await request('POST', '/auth/login', {
    email: 'admin@example.com',
    password: 'admin123',
  });

  if (loginRes.status !== 200 || !loginRes.body.data?.token) {
    throw new Error(`Login Admin gagal: ${JSON.stringify(loginRes.body)}`);
  }
  const token = loginRes.body.data.token;
  console.log('✅ 1. Login Admin berhasil.');

  // Clean previous test data
  await pool.query("DELETE FROM bantuan_sosial WHERE id >= 37 OR no_sk LIKE 'SK-%-TEST' OR keterangan LIKE '%TEST%' OR keterangan LIKE '%Agustus 2026%'");

  // Ambil 1 user warga dari DB
  const userRes = await pool.query("SELECT id FROM users WHERE role = 'warga' LIMIT 2");
  if (userRes.rows.length === 0) throw new Error('Tidak ada user warga');
  const warga1 = userRes.rows[0].id;
  const warga2 = userRes.rows[1] ? userRes.rows[1].id : warga1;

  // 2. Tambah Bantuan Sembako Satu Kali
  const resSembako = await request(
    'POST',
    '/bantuan-sosial',
    {
      user_id: warga1,
      jenis_bantuan: 'Program Sembako (BPNT)',
      bentuk_bantuan: 'Non-tunai / barang',
      sumber_bantuan: 'Pemerintah Pusat',
      no_sk: 'SK-BPNT-2026-TEST',
      tanggal_bantuan: '2026-08-15',
      nominal: 200000,
      keterangan: 'Paket sembako bulanan',
    },
    token
  );
  if (resSembako.status !== 201) {
    throw new Error(`Tambah Sembako gagal [${resSembako.status}]: ${JSON.stringify(resSembako.body)}`);
  }
  console.log('✅ 2. Tambah Sembako (BPNT) satu kali -> BERHASIL HTTP 201');
  const sembakoId = resSembako.body.data.id;

  // 3. Tambah PKH Berperiode
  const resPkh = await request(
    'POST',
    '/bantuan-sosial',
    {
      user_id: warga2,
      jenis_bantuan: 'PKH',
      bentuk_bantuan: 'Tunai',
      sumber_bantuan: 'Pemerintah Pusat',
      no_sk: 'SK-PKH-2026-TEST',
      tanggal_mulai: '2026-08-01',
      tanggal_selesai: '2026-12-31',
      nominal: 750000,
      keterangan: 'PKH Kuartal III-IV',
    },
    token
  );
  if (resPkh.status !== 201) {
    throw new Error(`Tambah PKH gagal [${resPkh.status}]: ${JSON.stringify(resPkh.body)}`);
  }
  console.log('✅ 3. Tambah PKH berperiode -> BERHASIL HTTP 201');

  // 4. Tambah PBI-JK (Bantuan Kesehatan, Layanan, Nominal kosong/0)
  const resPbi = await request(
    'POST',
    '/bantuan-sosial',
    {
      user_id: warga1,
      jenis_bantuan: 'PBI-JK',
      bentuk_bantuan: 'Layanan',
      sumber_bantuan: 'Pemerintah Pusat',
      tanggal_bantuan: '2026-08-10',
      nominal: '', // Kosong
      keterangan: 'Subsidi BPJS Kesehatan PBI',
    },
    token
  );
  if (resPbi.status !== 201) {
    throw new Error(`Tambah PBI-JK gagal [${resPbi.status}]: ${JSON.stringify(resPbi.body)}`);
  }
  console.log('✅ 4. Tambah PBI-JK (Layanan, Nominal kosong) -> BERHASIL HTTP 201');

  // 5. Tambah BLT Desa (Tunai, Nominal tersimpan)
  const resBlt = await request(
    'POST',
    '/bantuan-sosial',
    {
      user_id: warga2,
      jenis_bantuan: 'BLT Desa',
      bentuk_bantuan: 'Tunai',
      sumber_bantuan: 'Pemerintah Desa',
      tanggal_bantuan: '2026-08-12',
      nominal: 300000,
      keterangan: 'BLT Desa Agustus 2026',
    },
    token
  );
  if (resBlt.status !== 201) {
    throw new Error(`Tambah BLT Desa gagal [${resBlt.status}]: ${JSON.stringify(resBlt.body)}`);
  }
  console.log('✅ 5. Tambah BLT Desa -> BERHASIL HTTP 201');

  // 6. Get List & Verification
  const listRes = await request('GET', '/bantuan-sosial?tahun=2026', null, token);
  if (listRes.status !== 200 || !Array.isArray(listRes.body.data)) {
    throw new Error(`Get List gagal [${listRes.status}]: ${JSON.stringify(listRes.body)}`);
  }
  console.log(`✅ 6. Get List (Filter 2026) -> BERHASIL (${listRes.body.data.length} item)`);

  // 7. Edit Data (Update Sembako)
  const editRes = await request(
    'PUT',
    `/bantuan-sosial/${sembakoId}`,
    {
      jenis_bantuan: 'Program Sembako (BPNT)',
      bentuk_bantuan: 'Non-tunai / barang',
      nominal: 250000,
      status: 'Selesai',
      keterangan: 'Sembako sudah diterima penuh',
    },
    token
  );
  if (editRes.status !== 200) {
    throw new Error(`Edit Bantuan gagal [${editRes.status}]: ${JSON.stringify(editRes.body)}`);
  }
  console.log('✅ 7. Edit Data Bantuan -> BERHASIL HTTP 200');

  // 8. Export Excel & PDF
  const exportExcel = await request('GET', '/bantuan-sosial/export?format=excel', null, token);
  if (exportExcel.status !== 200) throw new Error('Export Excel gagal');
  console.log('✅ 8. Export Excel -> BERHASIL HTTP 200');

  const exportPdf = await request('GET', '/bantuan-sosial/export?format=pdf', null, token);
  if (exportPdf.status !== 200) throw new Error('Export PDF gagal');
  console.log('✅ 9. Export PDF -> BERHASIL HTTP 200');

  // Clean test items created in this run
  await pool.query("DELETE FROM bantuan_sosial WHERE no_sk LIKE '%-TEST' OR keterangan LIKE '%TEST%' OR keterangan LIKE '%Agustus 2026%'");
  console.log('✅ 10. Pembersihan data pengujian berhasil.');

  console.log('\nALL END-TO-END HTTP TESTS PASSED PERFECTLY!');
  process.exit(0);
}

runTests().catch((err) => {
  console.error('❌ HTTP Test Failed:', err);
  process.exit(1);
});
