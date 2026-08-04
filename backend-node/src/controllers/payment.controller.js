const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/database');
const { pastikanTerpasang, CLIENT_KEY, IS_PRODUCTION } = require('../config/midtrans');
const midtrans = require('../services/midtrans.service');
const { catatKeKasRt, STATUS_LUNAS } = require('./bill.controller');
const { logActivity } = require('../services/log.service');

/**
 * Pembayaran iuran lewat Midtrans.
 *
 * ## Pemisahan yang menjaga Kas RT tetap jujur
 *
 *   payment_transactions = PERCOBAAN bayar, dibuat saat warga menekan Bayar
 *   bill_payments        = uang DITERIMA, hanya diisi setelah Midtrans
 *                          mengonfirmasi settlement
 *
 * Tagihan TIDAK PERNAH dilunasi berdasarkan apa yang dikirim aplikasi. Satu-
 * satunya jalan menuju lunas adalah `terapkanStatus`, dan fungsi itu selalu
 * menanyakan status resmi ke server Midtrans lebih dulu.
 *
 * ## Empat penjagaan uang
 *
 *  1. Tanda tangan notifikasi diverifikasi (midtrans.service).
 *  2. Status diambil ulang ke Midtrans; isi POST tidak pernah dipercaya.
 *  3. gross_amount dari Midtrans dicocokkan dengan yang tersimpan — tanpa ini
 *     seseorang berpotensi membayar Rp1 untuk tagihan Rp50.000.
 *  4. Idempoten berlapis: order_id UNIQUE, transisi hanya dari 'pending', dan
 *     finances_ref_uniq sebagai penjaga terakhir. Midtrans MEMANG mengirim
 *     notifikasi yang sama berkali-kali.
 */

/** Selisih pembulatan yang ditoleransi saat mencocokkan nominal (rupiah). */
const TOLERANSI_RUPIAH = 1;

// ======================== MULAI PEMBAYARAN ========================

async function mulaiPembayaran(req, res) {
  if (!pastikanTerpasang(res)) return;

  const { bill_ids: billIds } = req.body;
  if (!Array.isArray(billIds) || billIds.length === 0) {
    return res.status(400).json({
      success: false,
      message: 'Pilih minimal satu tagihan untuk dibayar.',
    });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // FOR UPDATE mengunci barisnya, sehingga dua permintaan bersamaan tidak
    // bisa sama-sama membuat order untuk tagihan yang sama.
    const tagihan = await client.query(
      `SELECT b.*, k.no_kk, k.kepala_keluarga
         FROM bills b
         JOIN keluarga k ON b.keluarga_id = k.id
        WHERE b.id = ANY($1::uuid[])
        FOR UPDATE OF b`,
      [billIds]
    );

    if (tagihan.rows.length !== billIds.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Sebagian tagihan tidak ditemukan.' });
    }

    // Warga hanya boleh membayar tagihan kartu keluarganya sendiri. Pengurus
    // boleh membayarkan siapa pun (mis. membantu warga di balai RT).
    if (req.user.role === 'warga') {
      const milik = await client.query(
        'SELECT no_kk FROM users WHERE id = $1',
        [req.user.id]
      );
      const noKk = milik.rows[0]?.no_kk;
      const bukanMilik = tagihan.rows.filter((b) => b.no_kk !== noKk);
      if (!noKk || bukanMilik.length > 0) {
        await client.query('ROLLBACK');
        return res.status(403).json({
          success: false,
          message: 'Anda hanya bisa membayar tagihan kartu keluarga sendiri.',
        });
      }
    }

    const sudahLunas = tagihan.rows.filter((b) => b.status === STATUS_LUNAS);
    if (sudahLunas.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: `${sudahLunas.length} tagihan sudah lunas dan tidak bisa dibayar lagi.`,
      });
    }

    const kkBerbeda = new Set(tagihan.rows.map((b) => b.keluarga_id));
    if (kkBerbeda.size > 1) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: 'Satu pembayaran hanya boleh untuk satu kartu keluarga.',
      });
    }

    const total = tagihan.rows.reduce((s, b) => s + Math.round(Number(b.nominal)), 0);
    const orderId = `RT-${Date.now()}-${uuidv4().split('-')[0].toUpperCase()}`;

    const trx = await client.query(
      `INSERT INTO payment_transactions
         (order_id, user_id, keluarga_id, gross_amount, status)
       VALUES ($1, $2, $3, $4, 'pending') RETURNING *`,
      [orderId, req.user.id, tagihan.rows[0].keluarga_id, total]
    );

    // Nominal DISALIN, bukan dibaca ulang nanti: yang ditagihkan harus tetap
    // sebesar yang tertera saat warga menekan Bayar.
    for (const b of tagihan.rows) {
      await client.query(
        `INSERT INTO payment_transaction_bills (transaction_id, bill_id, nominal, is_pending)
         VALUES ($1, $2, $3, true)`,
        [trx.rows[0].id, b.id, Math.round(Number(b.nominal))]
      );
    }

    // Panggil Midtrans SEBELUM commit. Kalau gagal, seluruh transaksi
    // dibatalkan dan tidak ada order menggantung tanpa token.
    const pembayar = await client.query(
      'SELECT nama, email, no_hp FROM users WHERE id = $1',
      [req.user.id]
    );

    const snap = await midtrans.buatSnap({
      orderId,
      grossAmount: total,
      pelanggan: pembayar.rows[0] || {},
      rincian: tagihan.rows.map((b) => ({
        id: b.id,
        nama: `${b.jenis_tagihan} ${b.bulan}`,
        harga: Math.round(Number(b.nominal)),
      })),
    });

    await client.query(
      `UPDATE payment_transactions
          SET snap_token = $1, redirect_url = $2, updated_at = NOW()
        WHERE id = $3`,
      [snap.token, snap.redirect_url, trx.rows[0].id]
    );

    await client.query('COMMIT');

    return res.status(201).json({
      success: true,
      message: 'Pembayaran dibuat. Lanjutkan di halaman Midtrans.',
      data: {
        order_id: orderId,
        snap_token: snap.token,
        redirect_url: snap.redirect_url,
        gross_amount: total,
        jumlah_tagihan: tagihan.rows.length,
        client_key: CLIENT_KEY,
        is_production: IS_PRODUCTION,
      },
    });
  } catch (err) {
    await client.query('ROLLBACK');

    // Indeks payment_bill_pending_uniq yang menolak.
    if (err.code === '23505' && String(err.constraint || '').includes('pending')) {
      return res.status(409).json({
        success: false,
        message: 'Sebagian tagihan sudah punya pembayaran yang sedang berjalan. '
          + 'Selesaikan atau batalkan pembayaran itu dulu.',
      });
    }

    console.error('MulaiPembayaran Error:', err.message);
    return res.status(500).json({
      success: false,
      message: `Gagal membuat pembayaran: ${err.message}`,
    });
  } finally {
    client.release();
  }
}

// ======================== TERAPKAN STATUS ========================

/**
 * Menerapkan status resmi Midtrans ke sebuah order.
 *
 * Dipakai webhook MAUPUN pemeriksaan status manual, supaya keduanya mustahil
 * berbeda perilaku. `data` harus berasal dari `midtrans.ambilStatus()`, bukan
 * dari isi permintaan mana pun.
 */
async function terapkanStatus(orderId, data) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const trxRes = await client.query(
      'SELECT * FROM payment_transactions WHERE order_id = $1 FOR UPDATE',
      [orderId]
    );
    if (trxRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { ok: false, alasan: 'Order tidak ditemukan.' };
    }
    const trx = trxRes.rows[0];

    // Penjagaan #3: nominal harus cocok.
    const dariMidtrans = Math.round(Number(data.gross_amount));
    const tersimpan = Math.round(Number(trx.gross_amount));
    if (Math.abs(dariMidtrans - tersimpan) > TOLERANSI_RUPIAH) {
      await client.query('ROLLBACK');
      console.error(
        `Nominal tidak cocok untuk ${orderId}: Midtrans ${dariMidtrans}, tersimpan ${tersimpan}`
      );
      return { ok: false, alasan: 'Nominal pembayaran tidak cocok.' };
    }

    const hasil = midtrans.terjemahkanStatus(data);

    // Penjagaan #4: hanya transaksi yang masih pending yang boleh berubah.
    // Notifikasi ulang untuk order yang sudah selesai berhenti di sini.
    if (trx.status !== 'pending') {
      await client.query(
        'UPDATE payment_transactions SET midtrans_payload = $1, updated_at = NOW() WHERE id = $2',
        [JSON.stringify(data), trx.id]
      );
      await client.query('COMMIT');
      return { ok: true, status: trx.status, catatan: 'Sudah final, diabaikan.' };
    }

    if (hasil === 'pending') {
      await client.query(
        `UPDATE payment_transactions
            SET payment_type = $1, midtrans_payload = $2, updated_at = NOW()
          WHERE id = $3`,
        [data.payment_type || null, JSON.stringify(data), trx.id]
      );
      await client.query('COMMIT');
      return { ok: true, status: 'pending' };
    }

    if (hasil === 'gagal') {
      await client.query(
        `UPDATE payment_transactions
            SET status = $1, payment_type = $2, midtrans_payload = $3, updated_at = NOW()
          WHERE id = $4`,
        [data.transaction_status, data.payment_type || null, JSON.stringify(data), trx.id]
      );
      // Lepaskan kuncinya agar tagihan bisa dibayar ulang.
      await client.query(
        'UPDATE payment_transaction_bills SET is_pending = false WHERE transaction_id = $1',
        [trx.id]
      );
      await client.query('COMMIT');
      return { ok: true, status: data.transaction_status };
    }

    // ---- LUNAS ----
    const daftar = await client.query(
      `SELECT ptb.bill_id, ptb.nominal, b.*
         FROM payment_transaction_bills ptb
         JOIN bills b ON b.id = ptb.bill_id
        WHERE ptb.transaction_id = $1
        FOR UPDATE OF b`,
      [trx.id]
    );

    const metode = `midtrans:${data.payment_type || 'online'}`;

    for (const baris of daftar.rows) {
      if (baris.status === STATUS_LUNAS) continue; // sudah dilunasi jalur lain

      const invoice = `INV-${Date.now()}-${uuidv4().split('-')[0].toUpperCase()}`;
      const bayar = await client.query(
        `INSERT INTO bill_payments (bill_id, user_id, jumlah_bayar, metode_bayar, invoice_number)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [baris.bill_id, trx.user_id, baris.nominal, metode, invoice]
      );

      await client.query(
        'UPDATE bills SET status = $1, user_id = $2, updated_at = NOW() WHERE id = $3',
        [STATUS_LUNAS, trx.user_id, baris.bill_id]
      );

      // Jalur pencatatan kas yang SAMA dengan pembayaran tunai.
      await catatKeKasRt(client, {
        payment: bayar.rows[0],
        bill: { ...baris, id: baris.bill_id, nominal: baris.nominal },
        userId: trx.user_id,
      });
    }

    await client.query(
      `UPDATE payment_transactions
          SET status = 'settlement', payment_type = $1, midtrans_payload = $2,
              settled_at = NOW(), updated_at = NOW()
        WHERE id = $3`,
      [data.payment_type || null, JSON.stringify(data), trx.id]
    );
    await client.query(
      'UPDATE payment_transaction_bills SET is_pending = false WHERE transaction_id = $1',
      [trx.id]
    );

    await client.query('COMMIT');
    return { ok: true, status: 'settlement', jumlah_tagihan: daftar.rows.length };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('TerapkanStatus Error:', err.message);
    return { ok: false, alasan: err.message };
  } finally {
    client.release();
  }
}

// ======================== WEBHOOK ========================

/**
 * Notifikasi dari Midtrans. TANPA authMiddleware — pemanggilnya Midtrans,
 * bukan pengguna. Keamanannya justru berlapis di dalam.
 */
async function notifikasi(req, res) {
  if (!pastikanTerpasang(res)) return;

  try {
    const body = req.body || {};

    // Penjagaan #1: tanda tangan.
    if (!midtrans.verifikasiTandaTangan(body)) {
      console.warn(`Notifikasi ditolak, tanda tangan tidak sah: ${body.order_id}`);
      return res.status(403).json({ success: false, message: 'Tanda tangan tidak sah.' });
    }

    // Penjagaan #2: jangan percaya isi POST — tanya langsung ke Midtrans.
    const resmi = await midtrans.ambilStatus(body.order_id);
    const hasil = await terapkanStatus(body.order_id, resmi);

    if (!hasil.ok) {
      return res.status(400).json({ success: false, message: hasil.alasan });
    }

    // Midtrans menganggap non-200 sebagai kegagalan dan akan mengirim ulang.
    return res.status(200).json({ success: true, message: 'Notifikasi diproses.' });
  } catch (err) {
    console.error('Notifikasi Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== PERIKSA STATUS ========================

/**
 * Dipakai tombol "Periksa Status" di aplikasi.
 *
 * Sama sahihnya dengan webhook, karena status tetap diambil dari Midtrans —
 * aplikasi hanya memicu pemeriksaan, tidak menentukan hasilnya.
 */
async function periksaStatus(req, res) {
  if (!pastikanTerpasang(res)) return;

  try {
    const { order_id: orderId } = req.params;

    const trx = await pool.query(
      'SELECT * FROM payment_transactions WHERE order_id = $1',
      [orderId]
    );
    if (trx.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Transaksi tidak ditemukan.' });
    }
    // Warga hanya boleh memeriksa transaksinya sendiri.
    if (req.user.role === 'warga' && trx.rows[0].user_id !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Bukan transaksi Anda.' });
    }

    const resmi = await midtrans.ambilStatus(orderId);
    const hasil = await terapkanStatus(orderId, resmi);

    const terbaru = await pool.query(
      'SELECT * FROM payment_transactions WHERE order_id = $1',
      [orderId]
    );

    return res.status(200).json({
      success: true,
      message: hasil.ok ? 'Status diperbarui.' : hasil.alasan,
      data: {
        order_id: orderId,
        status: terbaru.rows[0].status,
        payment_type: terbaru.rows[0].payment_type,
        gross_amount: Number(terbaru.rows[0].gross_amount),
        lunas: terbaru.rows[0].status === 'settlement',
      },
    });
  } catch (err) {
    // Order yang belum pernah dibayar belum ada di Midtrans.
    if (String(err.message).includes("404") || String(err.message).includes("doesn't exist")) {
      return res.status(200).json({
        success: true,
        message: 'Pembayaran belum dimulai di Midtrans.',
        data: { order_id: req.params.order_id, status: 'pending', lunas: false },
      });
    }
    console.error('PeriksaStatus Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== RIWAYAT ========================

async function riwayat(req, res) {
  try {
    const params = [];
    let where = '';
    if (req.user.role === 'warga') {
      params.push(req.user.id);
      where = 'WHERE pt.user_id = $1';
    }

    const r = await pool.query(
      `SELECT pt.order_id, pt.status, pt.gross_amount, pt.payment_type,
              pt.snap_token, pt.redirect_url,
              pt.created_at, pt.settled_at, u.nama AS nama_pembayar,
              COUNT(ptb.bill_id)::int AS jumlah_tagihan
         FROM payment_transactions pt
         LEFT JOIN users u ON pt.user_id = u.id
         LEFT JOIN payment_transaction_bills ptb ON ptb.transaction_id = pt.id
         ${where}
        GROUP BY pt.id, u.nama
        ORDER BY pt.created_at DESC
        LIMIT 100`,
      params
    );

    return res.status(200).json({ success: true, count: r.rowCount, data: r.rows });
  } catch (err) {
    console.error('RiwayatPembayaran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== BATAL ========================

/**
 * Melepas kunci pembayaran yang ditinggalkan warga, agar tagihannya bisa
 * dibayar ulang tanpa menunggu kedaluwarsa dari Midtrans.
 */
async function batalkan(req, res) {
  const client = await pool.connect();
  try {
    const { order_id: orderId } = req.params;
    await client.query('BEGIN');

    const trx = await client.query(
      "SELECT * FROM payment_transactions WHERE order_id = $1 AND status = 'pending' FOR UPDATE",
      [orderId]
    );
    if (trx.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        success: false,
        message: 'Transaksi tidak ditemukan atau sudah selesai.',
      });
    }
    if (req.user.role === 'warga' && trx.rows[0].user_id !== req.user.id) {
      await client.query('ROLLBACK');
      return res.status(403).json({ success: false, message: 'Bukan transaksi Anda.' });
    }

    await client.query(
      "UPDATE payment_transactions SET status = 'cancel', updated_at = NOW() WHERE id = $1",
      [trx.rows[0].id]
    );
    await client.query(
      'UPDATE payment_transaction_bills SET is_pending = false WHERE transaction_id = $1',
      [trx.rows[0].id]
    );

    await client.query('COMMIT');
    await logActivity(req, 'PEMBAYARAN', `Membatalkan pembayaran ${orderId}.`);

    return res.status(200).json({ success: true, message: 'Pembayaran dibatalkan.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('BatalkanPembayaran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  } finally {
    client.release();
  }
}

/** Halaman sederhana yang dibuka Snap setelah pembayaran selesai. */
function halamanSelesai(req, res) {
  res.status(200).send(`<!doctype html>
<html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pembayaran Selesai</title></head>
<body style="font-family:system-ui,sans-serif;text-align:center;padding:48px 24px;color:#1E293B">
  <div style="font-size:56px">✅</div>
  <h2 style="color:#1B7A6A;margin:16px 0 8px">Pembayaran Diproses</h2>
  <p style="color:#64748B;font-size:14px;line-height:1.6">
    Silakan kembali ke aplikasi dan tekan <b>Periksa Status</b><br>
    untuk memperbarui tagihan Anda.
  </p>
</body></html>`);
}

module.exports = {
  mulaiPembayaran,
  notifikasi,
  periksaStatus,
  riwayat,
  batalkan,
  halamanSelesai,
  terapkanStatus,
};
