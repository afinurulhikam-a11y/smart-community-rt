const { pool } = require('../config/database');
const bcrypt = require('bcryptjs');
const ExcelJS = require('exceljs');
const { logActivity, TIPE } = require('../services/log.service');
const {
  RESET_GROUPS,
  GRUP_TOTAL,
  cariGrup,
  frasaKonfirmasi,
} = require('../config/reset-groups');

/**
 * Reset data sistem.
 *
 * Tiga jaminan yang dipegang seluruh berkas ini:
 *
 *   1. Nama tabel TIDAK PERNAH datang dari klien. Klien hanya mengirim `kode`
 *      kelompok; daftar dan urutan tabelnya dibaca dari reset-groups.js.
 *   2. Penghapusan selalu di dalam satu transaksi. Gagal sedikit saja,
 *      ROLLBACK penuh — tidak ada keadaan setengah terhapus.
 *   3. Setiap eksekusi tercatat di `reset_logs`, tabel yang tidak pernah ikut
 *      direset oleh kelompok mana pun.
 */

/** Menyalin normalisasi IP dari log.service.js agar reset_logs seragam. */
function ambilIp(req) {
  const raw = req.headers['x-forwarded-for'] || req.socket.remoteAddress || req.ip || '127.0.0.1';
  return String(raw).split(',')[0].trim().replace('::ffff:', '').replace('::1', '127.0.0.1');
}

function klausaWhere(entri) {
  return entri.where ? ` WHERE ${entri.where}` : '';
}

/** Jumlah baris yang akan terhapus oleh satu entri tabel. */
async function hitungBaris(db, entri) {
  const r = await db.query(`SELECT COUNT(*)::int AS n FROM ${entri.tabel}${klausaWhere(entri)}`);
  return r.rows[0].n;
}

/**
 * Rincian dampak sebuah kelompok, per tabel.
 *
 * `ikutan` menandai baris yang terhapus karena rantai FK, bukan karena ia
 * sasaran utama kelompok ini. Layar menampilkannya terpisah supaya tidak ada
 * yang lenyap tanpa disadari.
 */
async function rincianGrup(db, grup) {
  const rincian = [];
  for (const entri of grup.tabel) {
    rincian.push({
      tabel: entri.tabel,
      jumlah: await hitungBaris(db, entri),
      ikutan: entri.ikutan === true,
    });
  }
  return rincian;
}

function totalkan(rincian) {
  return rincian.reduce((a, r) => a + r.jumlah, 0);
}

// ======================== RINGKASAN ========================

/**
 * Jumlah baris nyata per kelompok, untuk kartu di layar.
 *
 * Yang dihitung hanya tabel sasaran utama — kalau data ikutan ikut dijumlah,
 * kartu "Data Warga" akan menampilkan angka tagihan iuran dan membingungkan.
 * Dampak lengkapnya muncul saat pratinjau.
 */
async function getRingkasan(req, res) {
  try {
    const hasil = [];
    for (const grup of RESET_GROUPS) {
      let jumlah = 0;
      for (const entri of grup.tabel) {
        if (entri.ikutan) continue;
        jumlah += await hitungBaris(pool, entri);
      }
      hasil.push({
        kode: grup.kode,
        nama: grup.nama,
        deskripsi: grup.deskripsi,
        ikon: grup.ikon,
        jumlah,
        konfirmasi: frasaKonfirmasi(grup),
      });
    }

    const total = await rincianGrup(pool, GRUP_TOTAL);
    hasil.push({
      kode: GRUP_TOTAL.kode,
      nama: GRUP_TOTAL.nama,
      deskripsi: GRUP_TOTAL.deskripsi,
      ikon: GRUP_TOTAL.ikon,
      jumlah: totalkan(total),
      konfirmasi: frasaKonfirmasi(GRUP_TOTAL),
    });

    return res.status(200).json({ success: true, data: hasil, count: hasil.length });
  } catch (err) {
    console.error('GetRingkasan Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== PRATINJAU ========================

async function pratinjauReset(req, res) {
  try {
    const grup = cariGrup(req.body.grup);
    if (!grup) {
      return res.status(400).json({ success: false, message: 'Kelompok reset tidak dikenal.' });
    }

    const rincian = await rincianGrup(pool, grup);
    const utama = rincian.filter((r) => !r.ikutan);
    const ikutan = rincian.filter((r) => r.ikutan && r.jumlah > 0);

    return res.status(200).json({
      success: true,
      data: {
        kode: grup.kode,
        nama: grup.nama,
        deskripsi: grup.deskripsi,
        konfirmasi: frasaKonfirmasi(grup),
        utama,
        ikutan,
        total: totalkan(rincian),
      },
    });
  } catch (err) {
    console.error('PratinjauReset Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

// ======================== CADANGAN ========================

/**
 * Nama sheet Excel maksimal 31 karakter dan tidak boleh memuat : \ / ? * [ ].
 * Nama tabel kita aman, tapi panjangnya tetap perlu dipangkas.
 */
function namaSheet(tabel) {
  return tabel.replace(/[:\\/?*[\]]/g, '_').slice(0, 31);
}

/**
 * ExcelJS menulis Date memakai komponen UTC, sehingga tanggal WIB bergeser
 * mundur sehari. Cadangan ini untuk dibaca manusia, jadi tanggal ditulis
 * sebagai teks lokal — tidak ada tanggal yang berubah arti.
 */
function nilaiSel(v) {
  if (v === null || v === undefined) return '';
  if (v instanceof Date) {
    const p = (n) => String(n).padStart(2, '0');
    return `${v.getFullYear()}-${p(v.getMonth() + 1)}-${p(v.getDate())} `
      + `${p(v.getHours())}:${p(v.getMinutes())}:${p(v.getSeconds())}`;
  }
  if (typeof v === 'object') return JSON.stringify(v);
  return v;
}

/**
 * Unduh seluruh baris yang akan dihapus, satu sheet per tabel.
 *
 * Dipanggil sebelum eksekusi bila pengguna memilih mencadangkan. Layar
 * membatalkan penghapusan bila unduhan ini gagal.
 */
async function cadanganReset(req, res) {
  try {
    const grup = cariGrup(req.body.grup || req.query.grup);
    if (!grup) {
      return res.status(400).json({ success: false, message: 'Kelompok reset tidak dikenal.' });
    }

    const workbook = new ExcelJS.Workbook();
    workbook.creator = 'Smart Community RT';
    workbook.created = new Date();

    let adaIsi = false;
    for (const entri of grup.tabel) {
      const hasil = await pool.query(`SELECT * FROM ${entri.tabel}${klausaWhere(entri)}`);
      if (hasil.rows.length === 0) continue;
      adaIsi = true;

      const sheet = workbook.addWorksheet(namaSheet(entri.tabel));
      const kolom = Object.keys(hasil.rows[0]);
      sheet.columns = kolom.map((k) => ({ header: k, key: k, width: 22 }));
      sheet.getRow(1).font = { bold: true };
      for (const baris of hasil.rows) {
        sheet.addRow(Object.fromEntries(kolom.map((k) => [k, nilaiSel(baris[k])])));
      }
    }

    if (!adaIsi) {
      const sheet = workbook.addWorksheet('Kosong');
      sheet.addRow(['Tidak ada data yang akan dihapus untuk kelompok ini.']);
    }

    const stempel = new Date().toISOString().slice(0, 10);
    const namaFile = `Cadangan_${grup.kode.replace(/\./g, '_')}_${stempel}.xlsx`;

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename=${namaFile}`);
    await workbook.xlsx.write(res);
    res.end();

    // Berkas ini berisi salinan mentah seluruh tabel dalam kelompoknya —
    // termasuk data pribadi warga. Mengunduhnya adalah kejadian yang harus
    // terbaca, bukan hanya penghapusannya.
    await logActivity(
      req,
      TIPE.AKSES,
      `Mengunduh cadangan data kelompok "${grup.nama || grup.kode}" (${namaFile})`
    );
  } catch (err) {
    console.error('CadanganReset Error:', err.message);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, message: 'Gagal membuat berkas cadangan.' });
    }
  }
}

// ======================== EKSEKUSI ========================

/**
 * Verifikasi password admin pemanggil.
 *
 * Mengembalikan pesan yang sama untuk user hilang maupun password salah —
 * tidak ada gunanya membedakan, dan membedakannya justru membocorkan info.
 */
async function passwordBenar(userId, password) {
  if (!password) return false;
  const r = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
  if (r.rows.length === 0) return false;
  return bcrypt.compare(password, r.rows[0].password_hash);
}

async function eksekusiReset(req, res) {
  const { grup: kode, konfirmasi, password, dicadangkan } = req.body;

  const grup = cariGrup(kode);
  if (!grup) {
    return res.status(400).json({ success: false, message: 'Kelompok reset tidak dikenal.' });
  }

  const frasa = frasaKonfirmasi(grup);
  if (String(konfirmasi || '').trim() !== frasa) {
    return res.status(400).json({
      success: false,
      message: `Frasa konfirmasi tidak cocok. Ketik persis: "${frasa}".`,
    });
  }

  try {
    if (!(await passwordBenar(req.user.id, password))) {
      return res.status(401).json({
        success: false,
        message: 'Password admin salah. Tidak ada data yang dihapus.',
      });
    }
  } catch (err) {
    console.error('EksekusiReset (verifikasi) Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // rowCount dari DELETE adalah jumlah yang benar-benar terhapus, jadi
    // rincian ini bukan perkiraan melainkan hasil sesungguhnya.
    const rincian = {};
    let total = 0;
    for (const entri of grup.tabel) {
      const r = await client.query(`DELETE FROM ${entri.tabel}${klausaWhere(entri)}`);
      if (r.rowCount > 0) {
        rincian[entri.tabel] = (rincian[entri.tabel] || 0) + r.rowCount;
        total += r.rowCount;
      }
    }

    await client.query(
      `INSERT INTO reset_logs
         (grup_kode, grup_nama, rincian, total_baris, dicadangkan,
          user_id, user_nama, user_role, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        grup.kode, grup.nama, JSON.stringify(rincian), total, dicadangkan === true,
        req.user.id, req.user.nama || req.user.email, req.user.role, ambilIp(req),
      ]
    );

    await client.query('COMMIT');

    // Sengaja SETELAH commit: kelompok "Log Aktivitas" mengosongkan
    // activity_logs, jadi mencatat di dalam transaksi berarti catatan reset
    // ikut terhapus oleh reset itu sendiri.
    const ringkas = Object.entries(rincian).map(([t, n]) => `${t}: ${n}`).join(', ');
    await logActivity(
      req, TIPE.RESET,
      `Reset "${grup.nama}" — ${total} baris dihapus${ringkas ? ` (${ringkas})` : ''}.`
    );

    return res.status(200).json({
      success: true,
      message: total > 0
        ? `Reset "${grup.nama}" berhasil. ${total} baris dihapus.`
        : `Tidak ada data untuk dihapus pada "${grup.nama}".`,
      data: { kode: grup.kode, nama: grup.nama, rincian, total },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('EksekusiReset Error:', err.message);
    return res.status(500).json({
      success: false,
      message: `Reset dibatalkan, tidak ada data yang terhapus. Penyebab: ${err.message}`,
    });
  } finally {
    client.release();
  }
}

// ======================== RIWAYAT ========================

async function getRiwayatReset(req, res) {
  try {
    const r = await pool.query(
      `SELECT id, grup_kode, grup_nama, rincian, total_baris, dicadangkan,
              user_nama, user_role, ip_address, created_at
       FROM reset_logs ORDER BY created_at DESC, id DESC LIMIT 100`
    );
    return res.status(200).json({ success: true, data: r.rows, count: r.rowCount });
  } catch (err) {
    console.error('GetRiwayatReset Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = {
  getRingkasan,
  pratinjauReset,
  cadanganReset,
  eksekusiReset,
  getRiwayatReset,
};
