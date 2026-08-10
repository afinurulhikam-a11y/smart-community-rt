/**
 * Bacaan meteran air — dicatat terpisah dari tagihan, dan itu inti rancangannya.
 *
 * Warga mengisi meteran tanggal 1–5; tagihan baru difinalisasi tanggal 25.
 * Kalau bacaannya ditulis ke `bills`, warga membutuhkan baris yang belum ada
 * saat ia mengisi. Karena itu `pembacaan_meteran` berdiri sendiri, dibuat oleh
 * pengisian itu sendiri lewat upsert — tidak ada baris yang perlu disiapkan
 * lebih dulu oleh siapa pun.
 *
 * Modul ini berbagi izin `keuangan.iuran` dengan modul tagihan, mengikuti
 * preseden `alokasi_bop` yang juga berkas terpisah namun berbagi `keuangan.bop`.
 */
const { pool } = require('../config/database');
const { logActivity, bandingkan, TIPE } = require('../services/log.service');
const {
  periodeDari,
  bolehIsiMeteran,
  TANGGAL_TUTUP_METERAN,
  STATUS_TERISI,
  STATUS_ANOMALI,
} = require('../utils/tagihan-air');

/**
 * Kartu keluarga milik pemanggil.
 *
 * Warga hanya pernah menyentuh barisnya sendiri, dan itu ditegakkan di sini —
 * bukan dengan mempercayai `keluarga_id` yang dikirim klien. Pola `no_kk` ini
 * sama dengan yang dipakai `buildQuery` di bill.controller dan `mulaiPembayaran`
 * di payment.controller.
 */
async function keluargaMilik(userId) {
  const r = await pool.query(
    `SELECT k.id, k.no_kk, k.kepala_keluarga, k.alamat, k.blok, k.langganan_sampah
     FROM keluarga k
     JOIN users u ON u.no_kk = k.no_kk
     WHERE u.id = $1 AND k.deleted_at IS NULL
     LIMIT 1`,
    [userId]
  );
  return r.rows[0] || null;
}

/** Angka meteran akhir periode sebelumnya, dari BACAAN — bukan dari tagihan. */
async function meteranPeriodeSebelumnya(db, keluargaId, periode) {
  const r = await db.query(
    `SELECT meteran_sekarang FROM pembacaan_meteran
     WHERE keluarga_id = $1 AND periode < $2 AND meteran_sekarang IS NOT NULL
     ORDER BY periode DESC LIMIT 1`,
    [keluargaId, periode]
  );
  return r.rows[0]?.meteran_sekarang ?? null;
}

/**
 * GET /api/meteran/saya — keadaan periode berjalan milik warga.
 *
 * Mengembalikan apa yang perlu diketahui layar sebelum menampilkan formulir:
 * apakah ini periode pertama (warga mengisi dua angka), apakah masih boleh
 * mengisi, dan berapa angka pembandingnya.
 */
async function meteranSaya(req, res) {
  try {
    const kk = await keluargaMilik(req.user.id);
    if (!kk) {
      return res.status(404).json({
        success: false,
        message: 'Akun ini belum tertaut ke kartu keluarga mana pun.',
      });
    }

    const periode = req.query.periode || periodeDari();
    const bacaan = await pool.query(
      'SELECT * FROM pembacaan_meteran WHERE keluarga_id = $1 AND periode = $2',
      [kk.id, periode]
    );
    const sebelumnya = await meteranPeriodeSebelumnya(pool, kk.id, periode);

    return res.status(200).json({
      success: true,
      data: {
        pelanggan: {
          nama: kk.kepala_keluarga,
          no_kk: kk.no_kk,
          blok: kk.blok,
          alamat: kk.alamat,
          langganan_sampah: kk.langganan_sampah !== false,
        },
        periode,
        // Periode pertama dikenali dari tidak adanya bacaan sebelumnya — bukan
        // dari tanggal atau hitungan bulan. Rumah yang baru masuk di tengah
        // tahun pun tetap menjalani periode pertamanya sendiri.
        periode_pertama: sebelumnya === null,
        meteran_lalu: bacaan.rows[0]?.meteran_lalu ?? sebelumnya,
        bacaan: bacaan.rows[0] || null,
        boleh_isi: bolehIsiMeteran(),
        batas_tanggal: TANGGAL_TUTUP_METERAN,
      },
    });
  } catch (err) {
    console.error('MeteranSaya Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * POST /api/meteran — warga mengisi meteran periode berjalan.
 *
 * Tiga hal yang tidak dipercayakan kepada klien:
 *
 *  1. `keluarga_id` — diambil dari `no_kk` pemanggil.
 *  2. `meteran_lalu` sejak periode kedua — diambil dari bacaan sebelumnya, dan
 *     kiriman klien DIABAIKAN. Menolaknya akan memutus klien lama yang masih
 *     mengirim; mengabaikannya lebih aman dan hasilnya sama.
 *  3. Pemakaian dan total — tidak disimpan di sini sama sekali.
 */
async function isiMeteran(req, res) {
  try {
    const kk = await keluargaMilik(req.user.id);
    if (!kk) {
      return res.status(404).json({
        success: false,
        message: 'Akun ini belum tertaut ke kartu keluarga mana pun.',
      });
    }

    if (!bolehIsiMeteran()) {
      return res.status(403).json({
        success: false,
        message: `Batas input meteran adalah tanggal ${TANGGAL_TUTUP_METERAN}. `
          + 'Hubungi pengurus RT bila perlu koreksi.',
      });
    }

    const periode = periodeDari();
    const { meteran_sekarang } = req.body;

    const kini = Number(meteran_sekarang);
    if (!Number.isInteger(kini) || kini < 0) {
      return res.status(400).json({
        success: false,
        message: 'Meteran sekarang wajib diisi berupa bilangan bulat.',
      });
    }

    const sebelumnya = await meteranPeriodeSebelumnya(pool, kk.id, periode);
    let lalu;

    if (sebelumnya === null) {
      // Periode pertama: belum ada pembanding, jadi warga mengisinya.
      const dariKlien = Number(req.body.meteran_lalu);
      if (!Number.isInteger(dariKlien) || dariKlien < 0) {
        return res.status(400).json({
          success: false,
          message: 'Ini periode pertama Anda — isi juga meteran sebelumnya.',
        });
      }
      lalu = dariKlien;
    } else {
      lalu = sebelumnya;
    }

    // Bacaan mundur TETAP DISIMPAN, ditandai anomali. Menolaknya berarti warga
    // yang salah ketik tidak punya cara melapor dan angkanya hilang begitu saja;
    // pengurus tidak akan pernah tahu ada yang perlu diperiksa. Yang dijaga
    // adalah tagihannya — `bills_meteran_maju` memastikan angka tidak wajar
    // tidak pernah sampai ke sana.
    const anomali = kini < lalu;
    const status = anomali ? STATUS_ANOMALI : STATUS_TERISI;
    const catatan = anomali
      ? `Meteran sekarang (${kini}) lebih kecil daripada meteran sebelumnya (${lalu}).`
      : null;

    const hasil = await pool.query(
      `INSERT INTO pembacaan_meteran
         (keluarga_id, periode, meteran_lalu, meteran_sekarang, status, catatan, diisi_oleh, diisi_pada)
       VALUES ($1,$2,$3,$4,$5,$6,$7,NOW())
       ON CONFLICT (keluarga_id, periode) DO UPDATE SET
         meteran_lalu     = EXCLUDED.meteran_lalu,
         meteran_sekarang = EXCLUDED.meteran_sekarang,
         status           = EXCLUDED.status,
         catatan          = EXCLUDED.catatan,
         diisi_oleh       = EXCLUDED.diisi_oleh,
         diisi_pada       = NOW(),
         updated_at       = NOW()
       WHERE pembacaan_meteran.bill_id IS NULL
       RETURNING *`,
      [kk.id, periode, lalu, kini, status, catatan, req.user.id]
    );

    // Baris tidak kembali berarti klausa WHERE menolaknya: tagihannya sudah
    // terbit. Mengubah bacaan setelah itu tidak akan mengubah tagihan yang
    // sudah ada, jadi lebih jujur menolaknya daripada menyimpan diam-diam.
    if (hasil.rowCount === 0) {
      return res.status(409).json({
        success: false,
        message: 'Tagihan periode ini sudah diterbitkan. Hubungi pengurus RT untuk koreksi.',
      });
    }

    await logActivity(
      req,
      TIPE.UPDATE,
      `Mengisi meteran air periode ${periode}: ${lalu} → ${kini}`
        + (anomali ? ' — DITANDAI ANOMALI' : ` (${kini - lalu} m³)`)
    );

    return res.status(200).json({
      success: true,
      message: anomali
        ? 'Meteran tersimpan, tetapi angkanya lebih kecil daripada bulan lalu. '
          + 'Pengurus akan memeriksanya.'
        : 'Meteran berhasil disimpan.',
      data: hasil.rows[0],
    });
  } catch (err) {
    console.error('IsiMeteran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * GET /api/meteran — daftar bacaan.
 *
 * Pengurus melihat seluruh rumah; warga hanya barisnya sendiri. Penyaringannya
 * di sini, bukan di layar — layar yang menyaring hanya menyembunyikan, tidak
 * mencegah.
 */
async function daftarMeteran(req, res) {
  try {
    const { periode, status } = req.query;
    const kondisi = [];
    const params = [];
    const p = () => `$${params.length}`;

    if (req.user.role === 'warga') {
      params.push(req.user.id);
      kondisi.push(`k.no_kk = (SELECT no_kk FROM users WHERE id = ${p()})`);
    }
    if (periode) {
      params.push(periode);
      kondisi.push(`pm.periode = ${p()}`);
    }
    if (status) {
      params.push(status);
      kondisi.push(`pm.status = ${p()}`);
    }

    const where = kondisi.length ? `WHERE ${kondisi.join(' AND ')}` : '';
    const hasil = await pool.query(
      `SELECT pm.*, k.no_kk, k.kepala_keluarga, k.blok, k.alamat,
              b.status AS status_tagihan, b.nominal
       FROM pembacaan_meteran pm
       JOIN keluarga k ON pm.keluarga_id = k.id
       LEFT JOIN bills b ON pm.bill_id = b.id
       ${where}
       ORDER BY pm.periode DESC, k.kepala_keluarga ASC`,
      params
    );

    return res.status(200).json({
      success: true,
      count: hasil.rows.length,
      data: hasil.rows,
    });
  } catch (err) {
    console.error('DaftarMeteran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * PUT /api/meteran/:id/koreksi — pengurus mengoreksi, dengan alasan.
 *
 * `alasan` WAJIB. Koreksi angka meteran mengubah berapa yang harus dibayar
 * warga, dan baris yang sudah dikoreksi tidak menyimpan jejak apa pun tentang
 * kenapa — tanpa alasan, jejak auditnya hanya mencatat bahwa sesuatu berubah.
 *
 * Tidak mengenal batas tanggal: justru untuk keadaan setelah tanggal 5 inilah
 * jalur ini ada.
 */
async function koreksiMeteran(req, res) {
  try {
    const { id } = req.params;
    const { meteran_lalu, meteran_sekarang, alasan } = req.body;

    if (!alasan || !alasan.trim()) {
      return res.status(400).json({
        success: false,
        message: 'Alasan koreksi wajib diisi.',
      });
    }

    const lamaRes = await pool.query(
      `SELECT pm.*, k.kepala_keluarga
       FROM pembacaan_meteran pm
       JOIN keluarga k ON pm.keluarga_id = k.id
       WHERE pm.id = $1`,
      [id]
    );
    if (lamaRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Bacaan meteran tidak ditemukan.' });
    }
    const lama = lamaRes.rows[0];

    const ambil = (baru, lamaNilai) =>
      baru !== undefined && baru !== null && baru !== '' ? Number(baru) : lamaNilai;

    const mLalu = ambil(meteran_lalu, lama.meteran_lalu);
    const mKini = ambil(meteran_sekarang, lama.meteran_sekarang);

    const anomali = mKini !== null && mLalu !== null && mKini < mLalu;
    const status = mKini === null ? lama.status : (anomali ? STATUS_ANOMALI : STATUS_TERISI);

    const hasil = await pool.query(
      `UPDATE pembacaan_meteran SET
         meteran_lalu     = $1,
         meteran_sekarang = $2,
         status           = $3,
         catatan          = $4,
         dikoreksi_oleh   = $5,
         dikoreksi_pada   = NOW(),
         updated_at       = NOW()
       WHERE id = $6 RETURNING *`,
      [mLalu, mKini, status, alasan.trim(), req.user.id, id]
    );

    const baru = hasil.rows[0];
    const perubahan = bandingkan(lama, baru, {
      meteran_lalu: 'Meteran lalu',
      meteran_sekarang: 'Meteran sekarang',
      status: 'Status',
    });

    await logActivity(
      req,
      TIPE.UPDATE,
      `Koreksi meteran ${lama.kepala_keluarga} periode ${lama.periode}`
        + (perubahan ? ` — ${perubahan}` : '')
        + ` — alasan: ${alasan.trim()}`
    );

    return res.status(200).json({
      success: true,
      message: 'Koreksi meteran tersimpan.',
      data: baru,
      // Tagihan yang sudah terbit TIDAK ikut berubah dari sini. Nominalnya
      // dikoreksi lewat PUT /bills/:id, yang punya penjaganya sendiri terhadap
      // tagihan yang sudah lunas dan sudah masuk Kas RT.
      catatan: baru.bill_id
        ? 'Tagihan periode ini sudah terbit — nominalnya perlu dikoreksi terpisah lewat menu tagihan.'
        : null,
    });
  } catch (err) {
    console.error('KoreksiMeteran Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  meteranSaya,
  isiMeteran,
  daftarMeteran,
  koreksiMeteran,
  // Dipakai uji dan modul lain; diekspor supaya tidak ditulis ulang.
  meteranPeriodeSebelumnya,
  keluargaMilik,
};
