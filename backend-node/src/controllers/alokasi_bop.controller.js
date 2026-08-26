const { pool } = require('../config/database');
const { logActivity, rupiah } = require('../services/log.service');
const { klausaRt, whereRt, rtUntukSimpan, tolakLuarRt } = require('../utils/lingkup-rt');

/**
 * Alokasi (pagu) dana BOP per periode.
 *
 * Realisasi dihitung per TAHUN, bukan per termin, karena transaksi BOP hanya
 * punya tanggal — tidak ada penanda termin pada belanjanya. Karena itu kolom
 * realisasi pada tiap baris menampilkan realisasi tahun bersangkutan, dan
 * perbandingan yang bermakna adalah total pagu setahun lawan total belanja
 * setahun.
 */
async function getAlokasiBop(req, res) {
  try {
    const { tahun } = req.query;
    const params = [];
    let where = '';
    if (tahun) {
      params.push(tahun);
      where = `WHERE a.tahun = $${params.length}`;
    }
    where += where ? klausaRt(req, 'a', params) : whereRt(req, 'a', params);

    // Kedua subkueri IKUT dilingkupi, dan itu bukan kerapian.
    //
    // `realisasi_tahun` dan `total_pagu_tahun` dipakai layar BOP untuk
    // menyimpulkan pagu terlampaui atau tidak. Melingkupi baris luarnya saja
    // menghasilkan baris milik satu RT yang realisasinya dijumlah dari
    // SELURUH RW — angka yang tidak menjawab pertanyaan mana pun, dan yang
    // membuat bendahara membaca pagunya jebol karena belanja RT tetangga.
    //
    // Dipakai `a.rt_id` sebagai acuan, bukan RT pemanggil, supaya barisnya
    // tetap konsisten dengan dirinya sendiri saat administrator melihat
    // seluruh RW: tiap baris melaporkan realisasi RT-nya masing-masing.
    const result = await pool.query(`
      SELECT a.*,
             u.nama AS created_by_nama,
             COALESCE((
               SELECT SUM(b.jumlah) FROM bop_finances b
               WHERE b.tipe = 'pengeluaran'
                 AND date_part('year', b.tanggal) = a.tahun
                 AND b.rt_id IS NOT DISTINCT FROM a.rt_id
             ), 0)::float8 AS realisasi_tahun,
             COALESCE((
               SELECT SUM(x.nominal) FROM alokasi_bop x
                WHERE x.tahun = a.tahun
                  AND x.rt_id IS NOT DISTINCT FROM a.rt_id
             ), 0)::float8 AS total_pagu_tahun
      FROM alokasi_bop a
      LEFT JOIN users u ON a.created_by = u.id
      ${where}
      ORDER BY a.tahun DESC, a.termin ASC
    `, params);

    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetAlokasiBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

function validasi({ tahun, nominal }) {
  if (tahun === undefined || tahun === null || tahun === '') {
    return 'Tahun wajib diisi.';
  }
  const t = parseInt(tahun, 10);
  if (isNaN(t) || t < 2000 || t > 2100) {
    return 'Tahun tidak masuk akal. Isi antara 2000 dan 2100.';
  }
  if (nominal === undefined || nominal === null || nominal === '') {
    return 'Nominal pagu wajib diisi.';
  }
  if (Number(nominal) <= 0) {
    return 'Nominal pagu harus lebih dari 0.';
  }
  return null;
}

async function createAlokasiBop(req, res) {
  try {
    const { tahun, termin, nominal, sumber_dana, keterangan } = req.body;

    const salah = validasi({ tahun, nominal });
    if (salah) return res.status(400).json({ success: false, message: salah });

    const result = await pool.query(
      `INSERT INTO alokasi_bop (tahun, termin, nominal, sumber_dana, keterangan, created_by, rt_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [
        parseInt(tahun, 10), (termin || 'Tahunan').trim(), nominal,
        sumber_dana || null, keterangan || null, req.user.id, rtUntukSimpan(req),
      ]
    );
    const dibuat = result.rows[0];
    await logActivity(
      req,
      'CREATE',
      `Menetapkan pagu Dana BOP ${dibuat.tahun} (${dibuat.termin}) sebesar ${rupiah(dibuat.nominal)}`
    );
    return res.status(201).json({ success: true, message: 'Alokasi dana BOP berhasil dicatat.', data: dibuat });
  } catch (err) {
    // 23505 = pelanggaran UNIQUE (tahun, termin). Balas pesan yang terbaca
    // manusia, bukan error Postgres mentah.
    if (err.code === '23505') {
      return res.status(409).json({
        success: false,
        message: `Alokasi untuk ${req.body.termin || 'Tahunan'} tahun ${req.body.tahun} sudah pernah dicatat. Ubah yang sudah ada bila nominalnya berubah.`,
      });
    }
    console.error('CreateAlokasiBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function updateAlokasiBop(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'alokasi_bop', id)) return;
    const { tahun, termin, nominal, sumber_dana, keterangan } = req.body;

    if (nominal !== undefined && Number(nominal) <= 0) {
      return res.status(400).json({ success: false, message: 'Nominal pagu harus lebih dari 0.' });
    }
    if (tahun !== undefined) {
      const t = parseInt(tahun, 10);
      if (isNaN(t) || t < 2000 || t > 2100) {
        return res.status(400).json({ success: false, message: 'Tahun tidak masuk akal. Isi antara 2000 dan 2100.' });
      }
    }

    const result = await pool.query(
      `UPDATE alokasi_bop SET
         tahun       = COALESCE($1, tahun),
         termin      = COALESCE($2, termin),
         nominal     = COALESCE($3, nominal),
         sumber_dana = COALESCE($4, sumber_dana),
         keterangan  = COALESCE($5, keterangan)
       WHERE id = $6 RETURNING *`,
      [
        tahun === undefined ? null : parseInt(tahun, 10),
        termin?.trim() || null, nominal ?? null,
        sumber_dana ?? null, keterangan ?? null, id,
      ]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Alokasi tidak ditemukan.' });
    }
    const baru = result.rows[0];
    await logActivity(
      req,
      'UPDATE',
      `Mengubah pagu Dana BOP ${baru.tahun} (${baru.termin}) menjadi ${rupiah(baru.nominal)}`
    );
    return res.status(200).json({ success: true, message: 'Alokasi dana BOP berhasil diperbarui.', data: baru });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({
        success: false,
        message: 'Sudah ada alokasi lain dengan tahun dan termin yang sama.',
      });
    }
    console.error('UpdateAlokasiBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function deleteAlokasiBop(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'alokasi_bop', id)) return;

    const alokasi = await pool.query('SELECT tahun FROM alokasi_bop WHERE id = $1', [id]);
    if (alokasi.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Alokasi tidak ditemukan.' });
    }

    // Menghapus pagu yang sudah ada belanjanya memutus jejak pertanggungjawaban:
    // realisasi jadi tidak punya pembanding.
    //
    // Ikut dilingkupi, kalau tidak penjagaannya salah sasaran: pagu RT 002
    // menjadi tidak bisa dihapus hanya karena RT 001 punya belanja di tahun
    // yang sama — sebuah penolakan yang pesannya menyebut angka yang tidak
    // ada di layar orang yang membacanya.
    const paramsBelanja = [alokasi.rows[0].tahun];
    const belanja = await pool.query(
      `SELECT COUNT(*)::int AS c FROM bop_finances
       WHERE tipe = 'pengeluaran' AND date_part('year', tanggal) = $1
       ${klausaRt(req, '', paramsBelanja)}`,
      paramsBelanja
    );
    if (belanja.rows[0].c > 0) {
      return res.status(409).json({
        success: false,
        message: `Tahun ${alokasi.rows[0].tahun} sudah punya ${belanja.rows[0].c} transaksi pengeluaran, sehingga alokasinya tidak bisa dihapus. Ubah nominalnya bila keliru.`,
      });
    }

    await pool.query('DELETE FROM alokasi_bop WHERE id = $1', [id]);
    await logActivity(
      req,
      'DELETE',
      `Menghapus pagu Dana BOP ${alokasi.rows[0].tahun} sebesar ${rupiah(alokasi.rows[0].nominal)}`
    );
    return res.status(200).json({ success: true, message: 'Alokasi dana BOP berhasil dihapus.' });
  } catch (err) {
    console.error('DeleteAlokasiBop Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { getAlokasiBop, createAlokasiBop, updateAlokasiBop, deleteAlokasiBop };
