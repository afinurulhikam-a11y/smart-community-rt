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
  TIPE_METERAN,
  rincianTagihanAir,
} = require('../utils/tagihan-air');
const { terbitkanTagihanPeriode } = require('../services/tagihan-air.service');

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
     JOIN users u ON (u.no_kk = k.no_kk OR (u.nik IS NOT NULL AND u.nik IN (SELECT ak.nik FROM anggota_keluarga ak WHERE ak.keluarga_id = k.id)))
     WHERE u.id = $1 AND k.deleted_at IS NULL
     LIMIT 1`,
    [userId]
  );
  return r.rows[0] || null;
}

/** Angka meteran akhir periode sebelumnya, dari BACAAN yang ber-status terisi — bukan dari tagihan. */
async function meteranPeriodeSebelumnya(db, keluargaId, periode) {
  const r = await db.query(
    `SELECT meteran_sekarang FROM pembacaan_meteran
     WHERE keluarga_id = $1 AND periode < $2 AND meteran_sekarang IS NOT NULL
       AND status = $3
     ORDER BY periode DESC LIMIT 1`,
    [keluargaId, periode, STATUS_TERISI]
  );
  return r.rows[0]?.meteran_sekarang ?? null;
}

/** Menerbitkan tagihan saat pengujian otomatis atau mode test. */
async function cobaTerbitkanTagihanTester(req, kkId, periode) {
  if (process.env.NODE_ENV !== 'test' && process.env.AUTO_GENERATE_TEST_BILL !== 'true') return;

  const client = await pool.connect();
  try {
    const jenisRes = await client.query("SELECT id FROM jenis_iuran WHERE tipe_hitung = 'meteran' AND is_aktif = true ORDER BY id LIMIT 1");
    if (jenisRes.rows.length === 0) return;

    await client.query('BEGIN');
    await terbitkanTagihanPeriode(client, {
      jenisIuranId: jenisRes.rows[0].id,
      bulan: periode,
      createdBy: req.user.id,
      keterangan: 'Tagihan Air (Pengujian)',
    });
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('BypassTerbitkanTagihan Error:', err.message);
  } finally {
    client.release();
  }
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
      `SELECT pm.*, b.status AS status_tagihan, b.nominal, b.biaya_sampah AS bill_biaya_sampah, b.langganan_sampah AS bill_langganan_sampah
       FROM pembacaan_meteran pm
       LEFT JOIN bills b ON (b.id = pm.bill_id OR (b.keluarga_id = pm.keluarga_id AND b.bulan = pm.periode))
       WHERE pm.keluarga_id = $1 AND pm.periode = $2
       ORDER BY pm.id DESC LIMIT 1`,
      [kk.id, periode]
    );
    const sebelumnya = await meteranPeriodeSebelumnya(pool, kk.id, periode);

    if (bacaan.rows[0]?.meteran_sekarang != null) {
      await cobaTerbitkanTagihanTester(req, kk.id, periode);
    }

    return res.status(200).json({
      success: true,
      data: {
        pelanggan: {
          nama: kk.kepala_keluarga,
          no_kk: kk.no_kk,
          blok: kk.blok,
          alamat: kk.alamat,
          langganan_sampah: kk.langganan_sampah === true,
        },
        periode,
        // Periode pertama dikenali dari tidak adanya bacaan sebelumnya — bukan
        // dari tanggal atau hitungan bulan. Rumah yang baru masuk di tengah
        // tahun pun tetap menjalani periode pertamanya sendiri.
        periode_pertama: sebelumnya === null,
        meteran_lalu: bacaan.rows[0]?.meteran_lalu ?? sebelumnya,
        bacaan: bacaan.rows[0] || null,
        boleh_isi: bolehIsiMeteran(new Date(), req.user),
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

    if (!bolehIsiMeteran(new Date(), req.user)) {
      return res.status(403).json({
        success: false,
        message: `Batas input meteran adalah tanggal ${TANGGAL_TUTUP_METERAN}. `
          + 'Hubungi pengurus RT bila perlu koreksi.',
      });
    }

    // Warga biasa selalu mengisi periode berjalan; pengurus/admin (atau saat mode test)
    // diizinkan menentukan periode khusus.
    const ijinkanPeriodeKhusus = req.user.role !== 'warga' || process.env.NODE_ENV === 'test';

    if (ijinkanPeriodeKhusus && req.body.periode !== undefined && req.body.periode !== null && req.body.periode !== '') {
      if (!/^\d{4}-\d{2}$/.test(String(req.body.periode))) {
        return res.status(400).json({
          success: false,
          message: 'Format periode harus YYYY-MM (contoh: 2026-08).',
        });
      }
    }

    const periode = (ijinkanPeriodeKhusus && req.body.periode)
      ? String(req.body.periode)
      : periodeDari();
    const { meteran_sekarang } = req.body;

    const kini = Number(meteran_sekarang);
    if (!Number.isInteger(kini) || kini < 0) {
      return res.status(400).json({
        success: false,
        message: 'Meteran sekarang wajib diisi berupa bilangan bulat.',
      });
    }

    // Tagihan periode ini sudah terbit? Maka meterannya tidak boleh diisi lagi.
    //
    // Pemeriksaannya ke `bills`, BUKAN hanya ke `pembacaan_meteran.bill_id`.
    // Klausa `WHERE pembacaan_meteran.bill_id IS NULL` pada upsert di bawah
    // hanya menjaga cabang DO UPDATE — ia tidak pernah tersentuh oleh baris
    // yang BARU. Jadi urutan "tagihan terbit lebih dulu, warga mengisi
    // menyusul" lolos sepenuhnya: INSERT-nya berhasil, warga dijawab "Meteran
    // berhasil disimpan", `bill_id` bacaan itu NULL, dan karena `terkunci`
    // dihitung dari `bill_id` maka kartunya pun tidak memberi peringatan apa
    // pun. Bacaannya tersimpan dan tidak akan pernah dipakai.
    //
    // Diukur pada data demo: tagihan terbit 227→232 senilai Rp 70.000, warga
    // kemudian melapor 260 (33 m³, seharusnya Rp 154.000). Selisih Rp 84.000
    // hilang tanpa satu pun gejala di kedua sisi.
    const sudahTerbit = await pool.query(
      `SELECT b.id FROM bills b
       JOIN jenis_iuran ji ON ji.id = b.jenis_iuran_id
       WHERE b.keluarga_id = $1 AND b.bulan = $2 AND ji.tipe_hitung = $3
       LIMIT 1`,
      [kk.id, periode, TIPE_METERAN]
    );
    if (sudahTerbit.rows.length > 0) {
      return res.status(409).json({
        success: false,
        message: 'Tagihan periode ini sudah diterbitkan. Hubungi pengurus RT untuk koreksi.',
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

    await cobaTerbitkanTagihanTester(req, kk.id, periode);

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
    const { periode, status, search } = req.query;
    const targetPeriode = periode || periodeDari();

    if (req.user.role === 'warga') {
      const kk = await keluargaMilik(req.user.id);
      if (!kk) {
        return res.status(200).json({ success: true, count: 0, data: [] });
      }
      const kondisi = ['pm.keluarga_id = $1'];
      const params = [kk.id];
      if (periode) {
        params.push(periode);
        kondisi.push(`pm.periode = $${params.length}`);
      }
      if (status) {
        params.push(status);
        kondisi.push(`pm.status = $${params.length}`);
      }
      if (search && search.trim() !== '') {
        params.push(`%${search.trim()}%`);
        kondisi.push(`(k.kepala_keluarga ILIKE $${params.length} OR k.no_kk ILIKE $${params.length} OR k.alamat ILIKE $${params.length} OR k.blok ILIKE $${params.length})`);
      }
      const where = `WHERE ${kondisi.join(' AND ')}`;
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
      return res.status(200).json({ success: true, count: hasil.rows.length, data: hasil.rows });
    }

    // Untuk Pengurus / Admin: tampilkan seluruh keluarga aktif untuk periode yang dipilih
    // (termasuk yang belum mengisi meteran).
    const params = [targetPeriode];
    let queryKeluarga = `
      SELECT k.id AS keluarga_id, k.no_kk, k.kepala_keluarga, k.blok, k.alamat,
             pm.id, pm.periode, pm.meteran_lalu, pm.meteran_sekarang,
             COALESCE(pm.status, 'menunggu') AS status,
             pm.catatan, pm.diisi_oleh, pm.diisi_pada, pm.dikoreksi_oleh, pm.dikoreksi_pada, pm.bill_id,
             COALESCE(b.status, b2.status) AS status_tagihan,
             COALESCE(b.nominal, b2.nominal) AS nominal,
             (
               SELECT pm_prev.meteran_sekarang
               FROM pembacaan_meteran pm_prev
               WHERE pm_prev.keluarga_id = k.id AND pm_prev.status = 'terisi' AND pm_prev.periode < $1
               ORDER BY pm_prev.periode DESC LIMIT 1
             ) AS prev_meteran
      FROM keluarga k
      LEFT JOIN pembacaan_meteran pm ON pm.keluarga_id = k.id AND pm.periode = $1
      LEFT JOIN bills b ON pm.bill_id = b.id
      LEFT JOIN bills b2 ON b2.keluarga_id = k.id AND b2.bulan = $1 AND b2.jenis_iuran_id IN (SELECT id FROM jenis_iuran WHERE tipe_hitung = 'meteran')
      WHERE k.deleted_at IS NULL
    `;

    if (status) {
      if (status === 'menunggu') {
        queryKeluarga += ` AND (pm.status = 'menunggu' OR pm.status IS NULL)`;
      } else {
        params.push(status);
        queryKeluarga += ` AND pm.status = $${params.length}`;
      }
    }

    if (search && search.trim() !== '') {
      params.push(`%${search.trim()}%`);
      queryKeluarga += ` AND (k.kepala_keluarga ILIKE $${params.length} OR k.no_kk ILIKE $${params.length} OR k.alamat ILIKE $${params.length} OR k.blok ILIKE $${params.length})`;
    }

    queryKeluarga += ` ORDER BY k.kepala_keluarga ASC`;
    const hasil = await pool.query(queryKeluarga, params);

    const rows = hasil.rows.map((r) => {
      const isNew = !r.id;
      return {
        id: r.id ? String(r.id) : `new_${r.keluarga_id}_${targetPeriode}`,
        keluarga_id: r.keluarga_id,
        periode: r.periode || targetPeriode,
        meteran_lalu: r.meteran_lalu !== null && r.meteran_lalu !== undefined ? r.meteran_lalu : (r.prev_meteran !== null && r.prev_meteran !== undefined ? r.prev_meteran : null),
        meteran_sekarang: r.meteran_sekarang,
        status: r.status,
        catatan: r.catatan || (isNew ? 'Belum diisi warga' : null),
        diisi_oleh: r.diisi_oleh,
        diisi_pada: r.diisi_pada,
        dikoreksi_oleh: r.dikoreksi_oleh,
        dikoreksi_pada: r.dikoreksi_pada,
        bill_id: r.bill_id,
        no_kk: r.no_kk,
        kepala_keluarga: r.kepala_keluarga,
        blok: r.blok,
        alamat: r.alamat,
        status_tagihan: r.status_tagihan,
        nominal: r.nominal,
      };
    });

    return res.status(200).json({
      success: true,
      count: rows.length,
      data: rows,
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
    const { meteran_lalu, meteran_sekarang, alasan, keluarga_id, periode } = req.body;

    if (!alasan || !alasan.trim()) {
      return res.status(400).json({
        success: false,
        message: 'Alasan koreksi wajib diisi.',
      });
    }

    let targetKeluargaId = keluarga_id;
    let targetPeriode = periode;
    let existingId = id;

    if (String(id).startsWith('new_')) {
      const parts = String(id).split('_');
      if (parts.length >= 3) {
        targetKeluargaId = targetKeluargaId || parseInt(parts[1]);
        targetPeriode = targetPeriode || parts[2];
      }
      existingId = null;
    }

    let lama = null;

    if (existingId && existingId !== '0') {
      const lamaRes = await pool.query(
        `SELECT pm.*, k.kepala_keluarga
         FROM pembacaan_meteran pm
         JOIN keluarga k ON pm.keluarga_id = k.id
         WHERE pm.id = $1`,
        [existingId]
      );
      if (lamaRes.rows.length > 0) {
        lama = lamaRes.rows[0];
      }
    }

    if (!lama && targetKeluargaId && targetPeriode) {
      const checkRes = await pool.query(
        `SELECT pm.*, k.kepala_keluarga
         FROM pembacaan_meteran pm
         JOIN keluarga k ON pm.keluarga_id = k.id
         WHERE pm.keluarga_id = $1 AND pm.periode = $2`,
        [targetKeluargaId, targetPeriode]
      );
      if (checkRes.rows.length > 0) {
        lama = checkRes.rows[0];
      } else {
        const kRes = await pool.query(`SELECT id, kepala_keluarga FROM keluarga WHERE id = $1`, [targetKeluargaId]);
        if (kRes.rows.length === 0) {
          return res.status(404).json({ success: false, message: 'Keluarga tidak ditemukan.' });
        }
        lama = {
          id: null,
          keluarga_id: targetKeluargaId,
          periode: targetPeriode,
          meteran_lalu: null,
          meteran_sekarang: null,
          status: 'menunggu',
          kepala_keluarga: kRes.rows[0].kepala_keluarga,
        };
      }
    }

    if (!lama) {
      return res.status(404).json({ success: false, message: 'Bacaan meteran tidak ditemukan.' });
    }

    const ambil = (baru, lamaNilai) =>
      baru !== undefined && baru !== null && baru !== '' ? Number(baru) : lamaNilai;

    let mLalu = ambil(meteran_lalu, lama.meteran_lalu);
    if (mLalu === null) {
      const prev = await meteranPeriodeSebelumnya(pool, lama.keluarga_id, lama.periode);
      mLalu = prev !== null ? prev : 0;
    }
    const mKini = ambil(meteran_sekarang, lama.meteran_sekarang);

    const anomali = mKini !== null && mLalu !== null && mKini < mLalu;
    const status = mKini === null ? lama.status : (anomali ? STATUS_ANOMALI : STATUS_TERISI);

    let hasil;
    if (lama.id) {
      hasil = await pool.query(
        `UPDATE pembacaan_meteran SET
           meteran_lalu     = $1,
           meteran_sekarang = $2,
           status           = $3,
           catatan          = $4,
           dikoreksi_oleh   = $5,
           dikoreksi_pada   = NOW(),
           updated_at       = NOW()
         WHERE id = $6 RETURNING *`,
        [mLalu, mKini, status, alasan.trim(), req.user.id, lama.id]
      );
    } else {
      hasil = await pool.query(
        `INSERT INTO pembacaan_meteran
           (keluarga_id, periode, meteran_lalu, meteran_sekarang, status, catatan, diisi_oleh, diisi_pada, dikoreksi_oleh, dikoreksi_pada, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $7, NOW(), NOW())
         ON CONFLICT (keluarga_id, periode) DO UPDATE SET
           meteran_lalu     = EXCLUDED.meteran_lalu,
           meteran_sekarang = EXCLUDED.meteran_sekarang,
           status           = EXCLUDED.status,
           catatan          = EXCLUDED.catatan,
           dikoreksi_oleh   = EXCLUDED.dikoreksi_oleh,
           dikoreksi_pada   = NOW(),
           updated_at       = NOW()
         RETURNING *`,
        [lama.keluarga_id, lama.periode, mLalu, mKini, status, alasan.trim(), req.user.id]
      );
    }

    const baru = hasil.rows[0];

    // Sinkronisasi otomatis ke tabel bills bila tagihan periode ini sudah terbit
    const billRes = await pool.query(
      `SELECT b.*, ji.tipe_hitung, ji.tarif_per_m3, ji.abondement, ji.biaya_sampah
       FROM bills b
       JOIN jenis_iuran ji ON b.jenis_iuran_id = ji.id
       WHERE (b.id = $1 OR (b.keluarga_id = $2 AND b.bulan = $3))
         AND ji.tipe_hitung = 'meteran'
       LIMIT 1`,
      [baru.bill_id || null, baru.keluarga_id, baru.periode]
    );

    if (billRes.rows.length > 0 && billRes.rows[0].status !== 'lunas') {
      const b = billRes.rows[0];
      const air = rincianTagihanAir({
        meteranLalu: baru.meteran_lalu,
        meteranSekarang: baru.status === STATUS_TERISI ? baru.meteran_sekarang : null,
        tarifPerM3: b.tarif_per_m3,
        abondement: b.abondement,
        biayaSampah: (b.langganan_sampah === true && b.biaya_sampah) ? b.biaya_sampah : 0,
      });

      await pool.query(
        `UPDATE bills
         SET meteran_lalu = $1,
             meteran_sekarang = $2,
             nominal = $3,
             updated_at = NOW()
         WHERE id = $4 AND status != 'lunas'`,
        [air.meteran_lalu, air.meteran_sekarang, air.total, b.id]
      );
    }

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
      message: 'Koreksi meteran dan tagihan air berhasil diperbarui.',
      data: baru,
      catatan: null,
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
