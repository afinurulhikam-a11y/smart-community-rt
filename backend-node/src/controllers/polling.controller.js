const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');

async function getPolling(req, res) {
  try {
    const { status } = req.query;
    let query = `SELECT p.*, u.nama AS created_by_nama FROM polling p LEFT JOIN users u ON p.created_by = u.id WHERE 1=1`;
    const params = [];
    if (status && status !== 'Semua') {
      params.push(status.toLowerCase());
      query += ` AND LOWER(p.status) = $${params.length}`;
    }
    query += ' ORDER BY p.created_at DESC';
    const result = await pool.query(query, params);
    // Suara milik pemanggil, sekali ambil untuk seluruh polling. Tanpa ini
    // layar tidak bisa tahu polling mana yang sudah ia pilih, sehingga tombol
    // memilih akan terus muncul dan berakhir 409.
    const suaraSaya = await pool.query(
      'SELECT polling_id, option_id FROM polling_votes WHERE user_id = $1',
      [req.user.id]
    );
    const pilihanSaya = new Map(suaraSaya.rows.map((v) => [v.polling_id, v.option_id]));

    // SATU query untuk seluruh opsi, bukan satu query per polling.
    //
    // Sebelumnya blok ini berupa `for` yang menembak `SELECT ... WHERE
    // polling_id = $1` sekali untuk setiap baris polling. Dua puluh polling
    // berarti dua puluh satu perjalanan bolak-balik ke database untuk satu kali
    // buka layar, dan angkanya tumbuh mengikuti jumlah polling — bukan mengikuti
    // jumlah data yang sebenarnya dibutuhkan.
    const semuaId = result.rows.map((p) => p.id);
    const opsiPerPolling = new Map();

    if (semuaId.length > 0) {
      const opsi = await pool.query(
        'SELECT * FROM polling_options WHERE polling_id = ANY($1::int[]) ORDER BY polling_id, id',
        [semuaId]
      );
      for (const o of opsi.rows) {
        if (!opsiPerPolling.has(o.polling_id)) opsiPerPolling.set(o.polling_id, []);
        opsiPerPolling.get(o.polling_id).push(o);
      }
    }

    const pollingList = result.rows.map((p) => {
      const daftarOpsi = opsiPerPolling.get(p.id) || [];
      const totalVotes = daftarOpsi.reduce((sum, o) => sum + (o.vote_count || 0), 0);
      return {
        ...p,
        options: daftarOpsi.map((o) => ({
          ...o,
          percentage: totalVotes > 0 ? Math.round((o.vote_count / totalVotes) * 100) : 0,
        })),
        total_votes: totalVotes,
        sudah_vote: pilihanSaya.has(p.id),
        pilihan_saya: pilihanSaya.get(p.id) ?? null,
      };
    });
    return res.status(200).json({ success: true, count: pollingList.length, data: pollingList });
  } catch (err) {
    console.error('GetPolling Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function createPolling(req, res) {
  try {
    const { judul, deskripsi, tanggal_mulai, tanggal_selesai, options } = req.body;
    if (!judul || !tanggal_mulai || !tanggal_selesai) return res.status(400).json({ success: false, message: 'Judul, tanggal mulai, dan tanggal selesai wajib diisi.' });
    if (!options || !Array.isArray(options) || options.length < 2) return res.status(400).json({ success: false, message: 'Minimal 2 opsi polling diperlukan.' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const pollingResult = await client.query(
        `INSERT INTO polling (judul, deskripsi, tanggal_mulai, tanggal_selesai, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [judul, deskripsi || null, tanggal_mulai, tanggal_selesai, req.user.id]
      );
      const polling = pollingResult.rows[0];
      for (const opt of options) {
        await client.query('INSERT INTO polling_options (polling_id, label) VALUES ($1, $2)', [polling.id, opt]);
      }
      await client.query('COMMIT');
      await logActivity(req, TIPE.CREATE, `Membuat polling "${ringkas(polling.judul)}"`);

      return res.status(201).json({ success: true, message: 'Polling berhasil dibuat.', data: polling });
    } catch (txErr) { await client.query('ROLLBACK'); throw txErr; }
    finally { client.release(); }
  } catch (err) {
    console.error('CreatePolling Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function vote(req, res) {
  try {
    const { id } = req.params;
    const { option_id } = req.body;
    if (!option_id) return res.status(400).json({ success: false, message: 'option_id wajib diisi.' });
    // Check if polling exists and is active
    const pollingResult = await pool.query('SELECT * FROM polling WHERE id = $1', [id]);
    if (pollingResult.rows.length === 0) return res.status(404).json({ success: false, message: 'Polling tidak ditemukan.' });
    if (pollingResult.rows[0].status !== 'aktif') return res.status(400).json({ success: false, message: 'Polling sudah ditutup.' });
    // Pilihan harus benar-benar milik polling ini. Tanpa pemeriksaan ini,
    // mengirim option_id milik polling lain akan menambah vote_count polling
    // tersebut — suara masuk ke tempat yang salah.
    const opsi = await pool.query('SELECT id FROM polling_options WHERE id = $1 AND polling_id = $2', [option_id, id]);
    if (opsi.rows.length === 0) {
      return res.status(400).json({ success: false, message: 'Pilihan tidak tersedia pada polling ini.' });
    }

    // Check duplicate vote
    const existing = await pool.query('SELECT id FROM polling_votes WHERE polling_id = $1 AND user_id = $2', [id, req.user.id]);
    if (existing.rows.length > 0) return res.status(409).json({ success: false, message: 'Anda sudah pernah vote di polling ini.' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('INSERT INTO polling_votes (polling_id, option_id, user_id) VALUES ($1, $2, $3)', [id, option_id, req.user.id]);
      await client.query('UPDATE polling_options SET vote_count = vote_count + 1 WHERE id = $1', [option_id]);
      await client.query('COMMIT');

      // Dicatat setelah COMMIT. Pilihan yang diambil TIDAK ikut dicatat —
      // hanya bahwa yang bersangkutan sudah memilih. Suara adalah hal yang
      // wajar dirahasiakan, dan tabel ini permanen serta terbaca administrator.
      await logActivity(req, TIPE.CREATE, `Memberikan suara pada polling #${id}`);

      return res.status(200).json({ success: true, message: 'Vote berhasil dicatat.' });
    } catch (txErr) { await client.query('ROLLBACK'); throw txErr; }
    finally { client.release(); }
  } catch (err) {
    // Pemeriksaan duplikat di atas bisa dilewati oleh dua permintaan yang
    // datang bersamaan; UNIQUE (polling_id, user_id) yang menjadi penjaga
    // terakhir. Terjemahkan jadi pesan yang sama, bukan 500.
    if (err.code === '23505') {
      return res.status(409).json({ success: false, message: 'Anda sudah pernah vote di polling ini.' });
    }
    console.error('Vote Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updatePollingStatus(req, res) {
  try {
    const { id } = req.params;
    const { status } = req.body;
    const rawStatus = (status || '').toLowerCase();
    const validStatus = ['aktif', 'ditutup', 'selesai'];
    if (!rawStatus || !validStatus.includes(rawStatus)) {
      return res.status(400).json({ success: false, message: `Status harus salah satu dari: Aktif, Ditutup, Selesai` });
    }
    const formattedStatus = rawStatus.charAt(0).toUpperCase() + rawStatus.slice(1);
    const result = await pool.query(
      'UPDATE polling SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [formattedStatus, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Polling tidak ditemukan.' });

    // Menutup polling menghentikan suara yang masuk. Kapan itu dilakukan bisa
    // menjadi pertanyaan bila hasilnya diperdebatkan.
    await logActivity(
      req,
      TIPE.UPDATE,
      `Mengubah status polling "${ringkas(result.rows[0].judul)}" menjadi ${formattedStatus}`
    );

    return res.status(200).json({ success: true, message: `Status polling berhasil diubah menjadi ${formattedStatus}.`, data: result.rows[0] });
  } catch (err) {
    console.error('UpdatePollingStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deletePolling(req, res) {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM polling WHERE id = $1 RETURNING id, judul', [id]);
    if (result.rows.length === 0) return res.status(404).json({ success: false, message: 'Polling tidak ditemukan.' });
    await logActivity(req, TIPE.DELETE, `Menghapus polling "${ringkas(result.rows[0].judul)}" beserta seluruh suara yang sudah masuk`);

    return res.status(200).json({ success: true, message: 'Polling berhasil dihapus.', data: result.rows[0] });
  } catch (err) {
    console.error('DeletePolling Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getPolling, createPolling, vote, updatePollingStatus, deletePolling };
