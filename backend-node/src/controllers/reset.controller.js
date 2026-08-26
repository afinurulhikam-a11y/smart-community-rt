const { pool } = require('../config/database');
const bcrypt = require('bcryptjs');
const ExcelJS = require('exceljs');
const { logActivity, TIPE } = require('../services/log.service');
const { rtAktif } = require('../utils/lingkup-rt');
const {
  RESET_GROUPS,
  GRUP_TOTAL,
  TABEL_TANPA_RT,
  cariGrup,
  frasaKonfirmasi,
  polaLingkupRt,
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

/**
 * Klausa WHERE untuk satu entri tabel, beserta parameternya.
 *
 * Dua penyaring digabung di sini dan HANYA di sini: `entri.where` dari
 * registry (mis. "hanya baris milik warga") dan pelingkupan RT. Menempatkan
 * yang kedua di tiap pemanggil berarti empat tempat — pratinjau, ringkasan,
 * cadangan, eksekusi — dan yang terlewat tidak berbunyi: ia hanya menghapus
 * lebih banyak daripada yang diminta.
 *
 * Nilai RT didorong ke `params`, tidak pernah disambung sebagai teks.
 */
function klausaWhere(entri, rt, params) {
  const bagian = [];
  if (entri.where) bagian.push(entri.where);
  if (rt) {
    const pola = polaLingkupRt(entri.tabel, params.length + 1);
    if (pola) {
      params.push(rt);
      bagian.push(pola);
    }
  }
  return bagian.length ? ` WHERE ${bagian.join(' AND ')}` : '';
}

/** Jumlah baris yang akan terhapus oleh satu entri tabel. */
async function hitungBaris(db, entri, rt) {
  if (dilewatiKarenaRt(entri, rt)) return 0;
  const params = [];
  const where = klausaWhere(entri, rt, params);
  const r = await db.query(`SELECT COUNT(*)::int AS n FROM ${entri.tabel}${where}`, params);
  return r.rows[0].n;
}

/**
 * RT yang sedang dilihat, beserta nomornya.
 *
 * Nomornya dibaca dari basis data, bukan dari token: ia ikut masuk ke frasa
 * konfirmasi dan ke `reset_logs`, dan keduanya harus menyebut RT yang benar-
 * benar dihapus. `null` berarti seluruh RW — perilaku sebelum ada modul RT.
 */
async function lingkupReset(req) {
  const id = rtAktif(req);
  if (!id) return { id: null, kode: null };
  const r = await pool.query('SELECT kode FROM rt WHERE id = $1 AND deleted_at IS NULL', [id]);
  return { id, kode: r.rows[0]?.kode ?? null };
}

/**
 * Tabel dalam sebuah kelompok yang tidak punya dimensi RT sama sekali.
 *
 * Hari ini hanya `sensor_logs`: barisnya memuat jenis sensor, nilai, dan
 * waktu, dan tidak ada satu pun kolom yang menghubungkannya ke sebuah RT.
 */
function tabelTakBerRt(grup) {
  return grup.tabel.map((t) => t.tabel).filter((t) => TABEL_TANPA_RT.includes(t));
}

/**
 * Apakah sebuah entri DILEWATI pada reset yang dilingkupi ke satu RT.
 *
 * ===================================================================
 * Kenapa dilewati, bukan menggagalkan seluruh kelompoknya
 * ===================================================================
 *
 * Percobaan pertama menolak kelompok mana pun yang memuat tabel semacam ini.
 * Itu terlihat tegas dan ternyata salah sasaran: `sensor_logs` ada di dalam
 * URUTAN_TOTAL, jadi aturan itu membuat **Reset Total per RT mustahil** —
 * padahal justru itu yang paling masuk akal diminta seorang administrator
 * yang sedang membereskan satu RT.
 *
 * Jadi entrinya dilewati, dan pelewatannya DITAMPILKAN: pratinjau menandainya
 * `dilewati`, dan hasil eksekusi ikut menyebutkannya. Yang berbahaya bukan
 * melewati sesuatu, melainkan melewatinya tanpa memberi tahu.
 *
 * Kelompok yang SELURUH tabelnya begini (yaitu kelompok Sensor) tetap ditolak
 * — bukan karena aturannya berbeda, melainkan karena tidak ada satu pun baris
 * yang akan tersentuh, dan tombol yang tidak melakukan apa pun harus
 * mengatakannya, bukan melapor "berhasil, 0 baris".
 */
function dilewatiKarenaRt(entri, rt) {
  return Boolean(rt) && TABEL_TANPA_RT.includes(entri.tabel);
}

/** Kalimat penolakan untuk kelompok yang seluruhnya tak punya dimensi RT. */
function pesanTakBerRt(daftar, kodeRt) {
  return `Kelompok ini hanya berisi ${daftar.join(', ')}, yang tidak menyimpan RT `
    + `sama sekali — jadi tidak ada yang bisa dihapus khusus untuk RT ${kodeRt}. `
    + 'Pilih "Semua RT" lebih dulu bila memang hendak menghapusnya untuk seluruh RW.';
}

/** Benar bila kelompok ini tidak menyentuh apa pun dalam lingkup RT terpilih. */
function seluruhnyaTakBerRt(grup, rt) {
  return Boolean(rt) && grup.tabel.every((t) => dilewatiKarenaRt(t, rt));
}

/**
 * Rincian dampak sebuah kelompok, per tabel.
 *
 * `ikutan` menandai baris yang terhapus karena rantai FK, bukan karena ia
 * sasaran utama kelompok ini. Layar menampilkannya terpisah supaya tidak ada
 * yang lenyap tanpa disadari.
 */
async function rincianGrup(db, grup, rt) {
  const rincian = [];
  for (const entri of grup.tabel) {
    rincian.push({
      tabel: entri.tabel,
      jumlah: await hitungBaris(db, entri, rt),
      ikutan: entri.ikutan === true,
      dilewati: dilewatiKarenaRt(entri, rt),
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
    const lingkup = await lingkupReset(req);
    const hasil = [];
    for (const grup of RESET_GROUPS) {
      let jumlah = 0;
      for (const entri of grup.tabel) {
        if (entri.ikutan) continue;
        jumlah += await hitungBaris(pool, entri, lingkup.id);
      }
      hasil.push({
        kode: grup.kode,
        nama: grup.nama,
        deskripsi: grup.deskripsi,
        ikon: grup.ikon,
        jumlah,
        konfirmasi: frasaKonfirmasi(grup, lingkup.kode),
        // Kartu yang tidak bisa dijalankan dalam lingkup ini ditandai di sini,
        // bukan dibiarkan gagal setelah administrator mengetik frasanya.
        terkunci: seluruhnyaTakBerRt(grup, lingkup.id),
      });
    }

    const total = await rincianGrup(pool, GRUP_TOTAL, lingkup.id);
    hasil.push({
      kode: GRUP_TOTAL.kode,
      nama: GRUP_TOTAL.nama,
      deskripsi: GRUP_TOTAL.deskripsi,
      ikon: GRUP_TOTAL.ikon,
      jumlah: totalkan(total),
      konfirmasi: frasaKonfirmasi(GRUP_TOTAL, lingkup.kode),
      terkunci: false,
    });

    return res.status(200).json({
      success: true,
      data: hasil,
      count: hasil.length,
      // Dibaca layar untuk menuliskan lingkupnya di atas daftar kartu. Sebuah
      // penghapusan yang lingkupnya tidak terlihat adalah cacat tersendiri,
      // sekalipun penghapusannya sendiri benar.
      lingkup: { rt_id: lingkup.id, rt_kode: lingkup.kode },
    });
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

    const lingkup = await lingkupReset(req);
    if (seluruhnyaTakBerRt(grup, lingkup.id)) {
      return res.status(400).json({
        success: false, message: pesanTakBerRt(tabelTakBerRt(grup), lingkup.kode),
      });
    }

    const rincian = await rincianGrup(pool, grup, lingkup.id);
    const utama = rincian.filter((r) => !r.ikutan);
    const ikutan = rincian.filter((r) => r.ikutan && r.jumlah > 0);
    // Ditampilkan terpisah supaya administrator melihat apa yang TIDAK ikut
    // terhapus, bukan menyimpulkannya dari angka nol yang terlihat wajar.
    const dilewati = rincian.filter((r) => r.dilewati).map((r) => r.tabel);

    return res.status(200).json({
      success: true,
      data: {
        kode: grup.kode,
        nama: grup.nama,
        deskripsi: grup.deskripsi,
        konfirmasi: frasaKonfirmasi(grup, lingkup.kode),
        rt_kode: lingkup.kode,
        utama,
        ikutan,
        dilewati,
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

    // Cadangan HARUS memakai lingkup yang sama dengan penghapusannya. Berbeda
    // sedikit pun berarti salah satu dari dua hal: berkasnya memuat data RT
    // lain (kebocoran), atau tidak memuat semua yang akan dihapus (cadangan
    // yang tidak bisa dipakai memulihkan).
    const lingkup = await lingkupReset(req);
    if (seluruhnyaTakBerRt(grup, lingkup.id)) {
      return res.status(400).json({
        success: false, message: pesanTakBerRt(tabelTakBerRt(grup), lingkup.kode),
      });
    }

    let adaIsi = false;
    for (const entri of grup.tabel) {
      // Dilewati di sini juga, dengan alasan yang sama: cadangan harus memuat
      // persis apa yang akan dihapus. Menyertakan sensor_logs pada cadangan
      // per RT berarti berkasnya menjanjikan pemulihan atas baris yang tidak
      // pernah tersentuh.
      if (dilewatiKarenaRt(entri, lingkup.id)) continue;
      const pCad = [];
      const whereCad = klausaWhere(entri, lingkup.id, pCad);
      const hasil = await pool.query(`SELECT * FROM ${entri.tabel}${whereCad}`, pCad);
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
    const bagianRt = lingkup.kode ? `RT${lingkup.kode}_` : '';
    const namaFile = `Cadangan_${bagianRt}${grup.kode.replace(/\./g, '_')}_${stempel}.xlsx`;

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

  let lingkup;
  try {
    lingkup = await lingkupReset(req);
  } catch (err) {
    console.error('EksekusiReset (lingkup) Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }

  if (seluruhnyaTakBerRt(grup, lingkup.id)) {
    return res.status(400).json({
      success: false, message: pesanTakBerRt(tabelTakBerRt(grup), lingkup.kode),
    });
  }

  const frasa = frasaKonfirmasi(grup, lingkup.kode);
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
    const dilewati = [];
    for (const entri of grup.tabel) {
      if (dilewatiKarenaRt(entri, lingkup.id)) {
        dilewati.push(entri.tabel);
        continue;
      }
      const pDel = [];
      const whereDel = klausaWhere(entri, lingkup.id, pDel);
      const r = await client.query(`DELETE FROM ${entri.tabel}${whereDel}`, pDel);
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
        // Nama kelompok DITULIS beserta RT-nya. `reset_logs` tidak punya kolom
        // rt_id — ia tabel dilindungi yang tidak ikut migrasi v43 — dan
        // riwayat yang tidak menyebutkan lingkupnya membuat dua baris "Reset
        // Data Warga" tidak bisa dibedakan satu sama lain.
        grup.kode, lingkup.kode ? `${grup.nama} (RT ${lingkup.kode})` : grup.nama,
        JSON.stringify(rincian), total, dicadangkan === true,
        req.user.id, req.user.nama || req.user.email, req.user.role, ambilIp(req),
      ]
    );

    await client.query('COMMIT');

    // Sengaja SETELAH commit: kelompok "Log Aktivitas" mengosongkan
    // activity_logs, jadi mencatat di dalam transaksi berarti catatan reset
    // ikut terhapus oleh reset itu sendiri.
    const ringkas = Object.entries(rincian).map(([t, n]) => `${t}: ${n}`).join(', ');
    // Lingkupnya ikut ke jejak audit. "Reset Data Warga — 48 baris" tidak bisa
    // dibedakan dari reset RT lain tanpa keterangan ini, dan tabel ini
    // permanen: keterangan yang hilang saat menulis tidak bisa ditambahkan.
    const sebutRt = lingkup.kode ? ` (RT ${lingkup.kode})` : ' (seluruh RW)';
    const sebutLewat = dilewati.length
      ? ` Dilewati karena tidak menyimpan RT: ${dilewati.join(', ')}.`
      : '';
    await logActivity(
      req, TIPE.RESET,
      `Reset "${grup.nama}"${sebutRt} — ${total} baris dihapus`
      + `${ringkas ? ` (${ringkas})` : ''}.${sebutLewat}`
    );

    return res.status(200).json({
      success: true,
      message: (total > 0
        ? `Reset "${grup.nama}"${sebutRt} berhasil. ${total} baris dihapus.`
        : `Tidak ada data untuk dihapus pada "${grup.nama}"${sebutRt}.`) + sebutLewat,
      data: {
        kode: grup.kode,
        nama: grup.nama,
        rt_kode: lingkup.kode,
        rincian,
        dilewati,
        total,
      },
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('EksekusiReset Error:', err.message);
    return res.status(500).json({
      success: false,
      // Satu-satunya tempat pesan galat mentah masih ikut dikirim, dan itu
      // disengaja: rutenya roleGuard('admin'), dan penyebab gagalnya reset
      // hampir selalu urutan foreign key — nama constraint-nya justru
      // keterangan yang dibutuhkan untuk memperbaikinya. Menggantinya dengan
      // "terjadi kesalahan" akan membuat administrator menebak-nebak sambil
      // mengulang perintah yang menghapus data.
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
