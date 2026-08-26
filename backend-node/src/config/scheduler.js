/**
 * Penerbitan tagihan air otomatis.
 *
 * ===================================================================
 * Kenapa memeriksa setiap hari, bukan menembak sekali tanggal 25
 * ===================================================================
 *
 * `cron('0 2 25 * *')` hanya berjalan bila prosesnya kebetulan hidup pada
 * detik itu. Railway menyebarkan ulang instance saat deploy, bisa
 * menidurkannya, dan bisa memindahkannya. Kalau proses sedang mati pada saat
 * itu, tagihan bulan itu TIDAK PERNAH TERBIT — dan tidak ada satu pun gejala
 * yang memberi tahu. Yang terlihat hanya warga yang tiba-tiba tidak punya
 * tagihan, kemungkinan besar berminggu-minggu kemudian.
 *
 * Karena itu pemeriksaannya harian dan idempoten: "sudah tanggal 25 ke atas,
 * dan tagihan periode ini belum lengkap? kalau ya, terbitkan." Ia menyembuhkan
 * dirinya sendiri. Terlambat sehari jauh lebih baik daripada terlewat sebulan.
 *
 * Dijalankan juga sekali saat startup, dengan alasan yang sama: kalau server
 * mati sepanjang tanggal 25 dan baru hidup tanggal 26, tagihannya terbit
 * begitu ia bangun — bukan menunggu jadwal harian berikutnya.
 *
 * ===================================================================
 * Yang TIDAK dilakukan penjadwal ini
 * ===================================================================
 *
 * Ia tidak pernah mengarang angka meteran. Rumah yang warganya tidak melapor
 * tetap diterbitkan tagihannya sebesar bagian tetap saja — abondement dan
 * biaya sampah bila berlangganan — dan bacaannya tetap kosong. Mengisi angka
 * karangan akan menagih warga atas pemakaian yang tidak pernah diukur.
 *
 * Ia juga tidak punya logika penerbitan sendiri. Seluruhnya memanggil
 * `terbitkanTagihanPeriode()` yang sama dengan tombol Generate Manual, supaya
 * keduanya tidak mungkin berbeda perilaku.
 */
const cron = require('node-cron');
const { pool } = require('./database');
const { logSistem, TIPE } = require('../services/log.service');
const { terbitkanTagihanPeriode } = require('../services/tagihan-air.service');
const {
  periodeDari,
  bolehTerbitkanTagihan,
  TANGGAL_TERBIT_TAGIHAN,
} = require('../utils/tagihan-air');

/** Zona waktu eksplisit — server bisa berjalan di UTC, RT-nya tidak. */
const ZONA = process.env.TZ_SCHEDULER || 'Asia/Jakarta';

/** Setiap hari pukul 02.00, saat lalu lintas paling sepi. */
const JADWAL = process.env.CRON_TAGIHAN || '0 2 * * *';

/**
 * Terbitkan tagihan periode berjalan bila memang waktunya dan belum lengkap.
 *
 * Mengembalikan ringkasan, bukan melempar: penjadwal yang melempar akan
 * menjatuhkan proses, dan gagal menerbitkan tagihan tidak boleh menjatuhkan
 * seluruh API.
 */
async function terbitkanBilaWaktunya({ paksa = false, tanggal = new Date() } = {}) {
  if (!paksa && !bolehTerbitkanTagihan(tanggal)) {
    return { dijalankan: false, alasan: `belum tanggal ${TANGGAL_TERBIT_TAGIHAN}` };
  }

  const client = await pool.connect();
  try {
    const lockRes = await client.query('SELECT pg_try_advisory_lock(889911) AS acquired');
    if (!lockRes.rows[0]?.acquired) {
      return { dijalankan: false, alasan: 'proses penjadwal sedang berjalan di instance lain' };
    }

    try {
      const periode = periodeDari(tanggal);

      // Hanya jenis iuran bermeteran yang diterbitkan otomatis. Iuran bernominal
      // tetap — bila kelak ada lagi — tetap diterbitkan manual, karena nominalnya
      // adalah keputusan pengurus, bukan hasil pengukuran.
      const jenisRes = await client.query(
        `SELECT id, nama_iuran, rt_id FROM jenis_iuran
         WHERE is_aktif = true AND tipe_hitung = 'meteran'
         ORDER BY id`
      );
      if (jenisRes.rows.length === 0) {
        return { dijalankan: false, alasan: 'tidak ada jenis iuran bermeteran yang aktif' };
      }

      const ringkas = [];

      for (const jenis of jenisRes.rows) {
        // Lewati bila seluruh KK sudah punya tagihan periode ini.
        // Dilingkupi ke RT pemilik jenis iuran ini, sama seperti penerbitannya.
        // Tanpa itu hitungannya memasukkan rumah RT lain yang memang tidak
        // akan pernah ditagih oleh jenis ini — sehingga "kurang" tidak pernah
        // mencapai nol dan penjadwal mencoba lagi setiap hari, selamanya.
        const kurang = await client.query(
          `SELECT COUNT(*)::int AS n
           FROM keluarga k
           WHERE k.deleted_at IS NULL
             AND k.rt_id IS NOT DISTINCT FROM $3
             AND NOT EXISTS (
               SELECT 1 FROM bills b
               WHERE b.keluarga_id = k.id AND b.jenis_iuran_id = $1 AND b.bulan = $2
             )`,
          [jenis.id, periode, jenis.rt_id]
        );
        if (kurang.rows[0].n === 0) {
          ringkas.push({ jenis: jenis.nama_iuran, dibuat: 0, lengkap: true });
          continue;
        }

        try {
          await client.query('BEGIN');
          const hasil = await terbitkanTagihanPeriode(client, {
            jenisIuranId: jenis.id,
            bulan: periode,
            createdBy: null,
            keterangan: null,
            jatuhTempo: null,
          });

          if (!hasil.ok) {
            await client.query('ROLLBACK');
            ringkas.push({ jenis: jenis.nama_iuran, gagal: hasil.alasan });
            continue;
          }

          await client.query('COMMIT');
          ringkas.push({
            jenis: jenis.nama_iuran,
            dibuat: hasil.dibuat,
            dilewati: hasil.dilewati,
            rincian: hasil.rincian,
          });

          if (hasil.dibuat > 0) {
            await logSistem(
              TIPE.CREATE,
              `Penjadwal menerbitkan tagihan ${jenis.nama_iuran} periode ${periode}: `
                + `${hasil.dibuat} dibuat, ${hasil.dilewati} dilewati — `
                + `${hasil.rincian.terisi} dengan bacaan meteran, `
                + `${hasil.rincian.tanpa_bacaan} tanpa bacaan, `
                + `${hasil.rincian.anomali} anomali`,
              { pelaku: 'Penjadwal Sistem' }
            );
          }
        } catch (e) {
          await client.query('ROLLBACK').catch(() => {});
          ringkas.push({ jenis: jenis.nama_iuran, gagal: e.message });
        }
      }

      return { dijalankan: true, periode, ringkas };
    } finally {
      await client.query('SELECT pg_advisory_unlock(889911)').catch(() => {});
    }
  } finally {
    client.release();
  }
}

let tugas = null;

/** Pasang penjadwal. Dipanggil sekali dari `server.listen`. */
function mulaiPenjadwal() {
  if (tugas) return tugas;

  if (!cron.validate(JADWAL)) {
    console.log(`⚠️  Jadwal cron tidak sah: "${JADWAL}" — penjadwal tidak dipasang.`);
    return null;
  }

  tugas = cron.schedule(JADWAL, () => {
    terbitkanBilaWaktunya()
      .then((h) => {
        if (h.dijalankan && h.ringkas.some((r) => r.dibuat > 0)) {
          console.log('🧾 Penjadwal tagihan:', JSON.stringify(h.ringkas));
        }
      })
      .catch((e) => console.log('ℹ️ Catatan penjadwal tagihan:', e.message));
  }, { timezone: ZONA });

  console.log(`⏰ Penjadwal tagihan aktif — "${JADWAL}" (${ZONA})`);

  // Sekali saat startup, mengejar tanggal 25 yang terlewat karena server mati.
  // Ditunda sebentar supaya tidak bersaing dengan autoSetupCloud saat boot.
  setTimeout(() => {
    terbitkanBilaWaktunya()
      .then((h) => {
        if (h.dijalankan && h.ringkas.some((r) => r.dibuat > 0)) {
          console.log('🧾 Penjadwal (kejar saat startup):', JSON.stringify(h.ringkas));
        }
      })
      .catch((e) => console.log('ℹ️ Catatan penjadwal saat startup:', e.message));
  }, 15000).unref();

  return tugas;
}

module.exports = { mulaiPenjadwal, terbitkanBilaWaktunya };
