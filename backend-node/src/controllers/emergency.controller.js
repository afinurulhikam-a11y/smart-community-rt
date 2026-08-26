const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const { broadcast } = require('../config/websocket');
const mqttAlarm = require('../config/mqtt');
const dispatcher = require('../services/notification.dispatcher');
const { klausaRt, tolakLuarRt } = require('../utils/lingkup-rt');
const {
  WAJIBKAN_KETERANGAN_DARURAT,
  PENANDA_LEGACY,
  catatDaruratTanpaKeterangan,
} = require('../config/kompatibilitas');

/**
 * ===================================================================
 * SATU-SATUNYA tempat waktu darurat ditafsirkan
 * ===================================================================
 *
 * `emergency_alerts.created_at` dan `dismissed_at` bertipe `timestamp WITHOUT
 * time zone`. Tipe itu tidak menyimpan zona sama sekali — isinya jam dinding
 * belaka. Sejak `DB_TIMEZONE=Asia/Jakarta`, jam dinding itu SELALU WIB, karena
 * `NOW()` menulisnya di bawah zona sesi tersebut.
 *
 * Masalahnya muncul saat membacanya kembali. node-postgres menyusun objek Date
 * dari jam dinding itu memakai zona proses NODE, bukan zona sesi Postgres.
 * Akibatnya nilai yang sama ditafsirkan berbeda di dua mesin:
 *
 *   nilai tersimpan  : 2026-08-16 16:45:00   (jam dinding WIB)
 *   Node TZ=Asia/Jakarta → 2026-08-16T09:45:00.000Z   ← instant benar
 *   Node TZ=UTC          → 2026-08-16T16:45:00.000Z   ← MAJU 7 JAM
 *
 * Klien lalu memanggil `.toLocal()` — perilaku yang benar dan tidak perlu
 * diubah — sehingga di perangkat WIB nilai kedua tampil sebagai 23:45 untuk
 * kejadian pukul 16:45. Itulah +7 jam yang terlihat di produksi: Railway
 * menjalankan Node di UTC, mesin pengembangan di Asia/Jakarta. Karena itu
 * pengujian lokal SELALU lulus dan bug-nya hanya hidup di produksi.
 *
 * `::timestamptz` menutupnya di perbatasan SQL: ia menafsirkan jam dinding
 * memakai zona SESI Postgres — yang sudah dipaku ke `DB_TIMEZONE` oleh
 * `database.js` — lalu mengirimkan offsetnya secara eksplisit. node-postgres
 * membaca offset itu alih-alih menebak, sehingga hasilnya identik di mesin mana
 * pun. Ia juga mengikuti `DB_TIMEZONE` dengan sendirinya, tanpa menyalin nama
 * zona ke berkas ini dan tanpa menyisipkan env ke dalam SQL.
 *
 * Perbaikan ini sengaja BERHENTI di modul darurat. Mengubah pengurai tipe
 * node-postgres secara global memang menutup seluruh tabel sekaligus, tetapi
 * layar lain (Pengaduan, Pembayaran, Keuangan) membaca timestamp TANPA
 * `.toLocal()`, sehingga kini kebetulan menampilkan digit dari string `Z` apa
 * adanya. Menggeser instant-nya akan memperbaiki satu layar dan merusak
 * selusin lainnya sekaligus.
 *
 * Yang TIDAK diperbaiki: baris yang terlanjur ditulis SEBELUM `DB_TIMEZONE`
 * dipasang tersimpan sebagai jam dinding UTC, dan kini ditafsirkan sebagai WIB
 * — jadi kejadian lama tampil tujuh jam lebih maju. Memperbaikinya menuntut
 * pengetahuan tentang zona yang berlaku saat setiap baris ditulis, dan
 * menebaknya berarti merusak baris yang sudah benar.
 *
 * Dipakai lewat dua konstanta di bawah supaya tidak ada kueri yang tertinggal
 * dengan tafsir lama — daftar kolomnya satu, bukan tujuh salinan.
 */
const KOLOM_WAKTU_WIB = `
  ea.created_at::timestamptz AS created_at,
  ea.dismissed_at::timestamptz AS dismissed_at`;

/** Semua kolom `emergency_alerts`, dengan waktunya sudah ditafsirkan. */
const KOLOM_ALERT = `ea.id, ea.user_id, ea.message, ea.latitude, ea.longitude,
  ea.status, ea.dismissed_by,${KOLOM_WAKTU_WIB}`;

/** Bentuk tanpa awalan tabel, untuk `RETURNING` pada INSERT/UPDATE. */
const KOLOM_ALERT_RETURNING = `id, user_id, message, latitude, longitude,
  status, dismissed_by,
  created_at::timestamptz AS created_at,
  dismissed_at::timestamptz AS dismissed_at`;

/**
 * Batas panjang keterangan kejadian darurat.
 *
 * `KETERANGAN_MIN` sengaja pendek. Orang mengetiknya sambil panik, kadang
 * dengan satu tangan — memaksa kalimat lengkap akan membuat orang mengetik
 * "aaaaa" hanya supaya tombolnya mau ditekan, dan itu lebih buruk daripada
 * batas yang longgar. Lima karakter cukup untuk menolak "." dan "-" tetapi
 * masih menerima "Maling", "Banjir", "Api".
 *
 * `KETERANGAN_MAKS` mengikuti pemotongan yang sudah dipakai sebelumnya (500),
 * jadi tidak ada baris lama yang mendadak melanggar aturan baru.
 */
const KETERANGAN_MIN = 5;
const KETERANGAN_MAKS = 500;

/**
 * Memvalidasi keterangan kejadian, DI SERVER.
 *
 * Klien sudah memvalidasi lebih dulu, dan itu hanya kenyamanan: siapa pun bisa
 * memanggil endpoint ini dengan curl. Aturan yang menentukan ada di sini.
 *
 * Yang ditolak dan alasannya:
 *   - kosong / hanya spasi → kejadian tanpa konteks persis yang ingin
 *     dihilangkan; `"   "` harus ditolak sama tegasnya dengan `""`.
 *   - terlalu pendek → "." atau "-" secara teknis bukan spasi, tetapi sama
 *     tidak berartinya bagi pengurus yang membaca riwayat.
 *   - terlalu panjang → ditolak, BUKAN dipotong diam-diam. Memotong berarti
 *     menyimpan setengah kalimat orang tanpa memberi tahu, dan setengah
 *     kalimat pada catatan darurat bisa berarti kebalikannya.
 *
 * Mengembalikan `{ ok, nilai, pesan }` — bukan melempar — supaya pemanggil
 * yang menentukan bentuk responsnya.
 */
function validasiKeterangan(mentah) {
  // `kosong: true` membedakan "tidak dikirim sama sekali" dari "dikirim tetapi
  // buruk", dan pembedaan itulah yang membuat rollout bertahap mungkin:
  // hanya yang pertama yang boleh dilonggarkan untuk klien lama.
  if (mentah === undefined || mentah === null) {
    return { ok: false, kosong: true, pesan: 'Keterangan kejadian wajib diisi.' };
  }

  const nilai = mentah.toString().trim();

  if (nilai === '') {
    return { ok: false, kosong: true, pesan: 'Keterangan kejadian wajib diisi.' };
  }
  if (nilai.length < KETERANGAN_MIN) {
    return {
      ok: false,
      pesan: `Keterangan kejadian terlalu pendek — minimal ${KETERANGAN_MIN} karakter.`,
    };
  }
  if (nilai.length > KETERANGAN_MAKS) {
    return {
      ok: false,
      pesan: `Keterangan kejadian terlalu panjang — maksimal ${KETERANGAN_MAKS} karakter (saat ini ${nilai.length}).`,
    };
  }

  return { ok: true, nilai };
}

/**
 * Menyiarkan perubahan keadaan darurat ke aplikasi yang sedang terbuka.
 *
 * ===================================================================
 * Kenapa ini ada
 * ===================================================================
 *
 * `triggerAlarm` dan `dismissAlarm` sudah menyiarkan sejak awal, tetapi kedua
 * jalur TOMBOL DASBOR — `nyalakanDarurat` dan `matikanDarurat` — tidak. Jadi
 * menyalakan alarm dari dasbor satu ponsel tidak terlihat sama sekali di
 * ponsel lain sampai aplikasinya dibuka ulang. Padahal justru itu alur yang
 * paling sering dipakai.
 *
 * ===================================================================
 * Siaran adalah PEMBERITAHUAN, bukan sumber kebenaran
 * ===================================================================
 *
 * Karena itu kegagalannya ditelan. Baris `emergency_alerts` sudah tersimpan
 * dan sirene sudah berbunyi lewat MQTT; menggagalkan permintaan hanya karena
 * pemberitahuannya tidak terkirim akan membuat pemakai menekan tombol lagi
 * untuk keadaan yang sebenarnya sudah berhasil. Klien pun punya jaring
 * pengaman sendiri: membaca ulang saat dipasang, saat aplikasi kembali aktif,
 * dan saat WebSocket tersambung lagi.
 *
 * Pemanggilnya WAJIB memanggil ini SESUDAH `COMMIT`. Menyiarkan sebelum itu
 * berarti mengumumkan keadaan yang masih bisa dibatalkan.
 */
function siarkanPerubahanDarurat(muatan, muatanPerangkat) {
  try {
    return broadcast(muatan, muatanPerangkat);
  } catch (e) {
    console.error('⚠️  Siaran realtime darurat gagal:', e.message);
    return 0;
  }
}

function resetSentEmergencyIds() {
  // Status idempotensi kini tersimpan secara durable di tabel emergency_alerts (PostgreSQL)
}

/**
 * Mengirim notifikasi push FCM ke seluruh warga/pengurus aktif saat alarm darurat menyala.
 *
 * ===================================================================
 * Durable Database-Backed Idempotency & Multi-Instance Safety
 * ===================================================================
 *
 * Idempotensi dikunci secara atomik pada tingkat database (PostgreSQL):
 * - Status: 'unsent' -> 'pending' -> 'sent' (atau 'failed' bila terjadi error).
 * - Transisi 'pending' menggunakan UPDATE atomik bersyarat:
 *   UPDATE emergency_alerts SET fcm_dispatch_status = 'pending'
 *   WHERE id = $1 AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
 *
 * Aman dari process restart dan race condition pada deployment multi-instance.
 * Bila pengiriman FCM gagal, status ditandai 'failed' sehingga mekanisme retry
 * tetap dapat mencoba mengirim ulang tanpa terkunci permanen.
 *
 * Bersifat non-blocking & fail-safe: kegagalan FCM tidak membatalkan proses darurat,
 * aktivasi sirene MQTT, maupun siaran WebSocket.
 */
async function sendEmergencyPushNotification(alert, user = {}) {
  if (!alert || !alert.id) {
    console.log('ℹ️ [FCM Emergency] Alert tidak valid, push notifikasi dilewati.');
    return { skipped: true, reason: 'invalid_alert' };
  }

  if (alert.status && alert.status !== 'active') {
    console.log(`ℹ️ [FCM Emergency] Alert #${alert.id} bukan alert aktif (status: ${alert.status}), push notifikasi dilewati.`);
    return { skipped: true, reason: 'not_active' };
  }

  try {
    // Klaim dispatch secara atomik pada baris emergency_alerts (Race Condition Guard)
    const claimResult = await pool.query(
      `UPDATE emergency_alerts
       SET fcm_dispatch_status = 'pending'
       WHERE id = $1
         AND (fcm_dispatch_status = 'unsent' OR fcm_dispatch_status = 'failed' OR fcm_dispatch_status IS NULL)
       RETURNING id, fcm_dispatch_status`,
      [alert.id]
    );

    if (claimResult.rows.length === 0) {
      const checkStatus = await pool.query(
        `SELECT fcm_dispatch_status FROM emergency_alerts WHERE id = $1`,
        [alert.id]
      );
      const currentStatus = checkStatus.rows[0]?.fcm_dispatch_status || 'unknown';
      console.log(`ℹ️ [FCM Emergency] Alert #${alert.id} tidak dapat diklaim (status dispatch: '${currentStatus}'), siaran duplikat dicegah.`);
      return {
        skipped: true,
        reason: currentStatus === 'sent' ? 'already_sent' : 'already_processing_or_not_eligible',
      };
    }

    const userName = user.nama || 'Warga';
    const userAlamat = user.alamat && user.alamat !== '-' ? ` di ${user.alamat}` : '';
    const alertMessage = alert.message || 'Sinyal Darurat Panic Button';

    const title = '🚨 PERINGATAN DARURAT RT!';
    const body = `${userName}${userAlamat} membutuhkan bantuan segera! Pesan: "${alertMessage}"`;

    const pushResult = await dispatcher.sendToAllActive({
      title,
      body,
      data: {
        entity_type: 'emergency',
        entity_id: String(alert.id),
        action: 'ALARM_TRIGGERED',
        status: 'active',
        user_id: String(alert.user_id || user.id || ''),
        message: String(alertMessage),
        latitude: String(alert.latitude || ''),
        longitude: String(alert.longitude || ''),
        created_at: alert.created_at
          ? new Date(alert.created_at).toISOString()
          : new Date().toISOString(),
      },
      priority: 'high',
      collapseKey: 'emergency_alarm',
    });

    if (pushResult.skipped && pushResult.reason === 'no_active_users') {
      console.log('ℹ️ [FCM Emergency] Tidak ada user aktif untuk menerima notifikasi darurat.');
      await pool.query(
        `UPDATE emergency_alerts
         SET fcm_dispatch_status = 'sent', fcm_dispatched_at = CURRENT_TIMESTAMP, fcm_dispatch_error = NULL
         WHERE id = $1`,
        [alert.id]
      );
      return pushResult;
    }

    if (pushResult.success === false && !pushResult.simulated) {
      const errMsg = pushResult.error || 'FCM dispatch failure';
      await pool.query(
        `UPDATE emergency_alerts
         SET fcm_dispatch_status = 'failed', fcm_dispatch_error = $2
         WHERE id = $1`,
        [alert.id, errMsg]
      );
      console.error(`⚠️ [FCM Emergency] Dispatch FCM untuk Alert #${alert.id} gagal:`, errMsg);
      return pushResult;
    }

    // Tandai BERHASIL secara persisten
    await pool.query(
      `UPDATE emergency_alerts
       SET fcm_dispatch_status = 'sent', fcm_dispatched_at = CURRENT_TIMESTAMP, fcm_dispatch_error = NULL
       WHERE id = $1`,
      [alert.id]
    );

    console.log(
      `🚨 [FCM Emergency] Hasil Siaran Darurat #${alert.id}:\n` +
      `   - Total Token : ${pushResult.tokensCount || 0} perangkat aktif\n` +
      `   - Berhasil    : ${pushResult.successCount ?? (pushResult.simulated ? pushResult.tokensCount : 0)}\n` +
      `   - Gagal       : ${pushResult.failureCount ?? 0}\n` +
      `   - Mode        : ${pushResult.simulated ? 'Simulasi' : 'Live'}`
    );

    return pushResult;
  } catch (err) {
    await pool.query(
      `UPDATE emergency_alerts
       SET fcm_dispatch_status = 'failed', fcm_dispatch_error = $2
       WHERE id = $1`,
      [alert.id, err.message]
    ).catch(() => {});
    console.error('⚠️ [FCM Emergency] Gagal mengirim push notification darurat:', err.message);
    return { error: err.message };
  }
}

/**
 * PIN darurat yang berlaku. Satu tempat, dipakai seluruh endpoint darurat.
 *
 * Diverifikasi DI SINI, bukan di klien. Verifikasi di Flutter hanya menyaring
 * salah ketik; siapa pun bisa memanggil endpoint ini langsung dengan curl dan
 * melewatinya sama sekali.
 */
function pinDaruratBerlaku() {
  return (process.env.EMERGENCY_PIN && process.env.EMERGENCY_PIN.trim() !== '')
    ? process.env.EMERGENCY_PIN.trim()
    : '1234';
}

/** True bila PIN yang dikirim cocok. */
function pinCocok(pin) {
  return !!pin && pin.toString().trim() === pinDaruratBerlaku();
}

/**
 * Peran yang boleh menutup kejadian darurat milik siapa pun.
 *
 * Daftar ini SATU, dipakai `dismissAlarm` maupun `matikanDarurat`. Dua jalur
 * yang mematikan alarm tidak boleh punya dua aturan — pada hari keduanya
 * berbeda, yang lebih longgarlah yang akan dipakai orang.
 */
const PERAN_PENGURUS = ['admin', 'ketua_rt', 'sekretaris', 'bendahara', 'pengurus_rt'];

/**
 * Kunci penasihat yang menyerialkan seluruh perubahan keadaan darurat.
 *
 * `SELECT ... FOR UPDATE` SAJA TIDAK CUKUP, dan ini ditemukan oleh uji, bukan
 * saat merancang: kunci baris hanya bisa mengunci baris yang SUDAH ADA. Ketika
 * belum ada kejadian aktif, tiga permintaan ON bersamaan sama-sama membaca nol
 * baris, sama-sama lolos pemeriksaan "belum ada yang aktif", lalu sama-sama
 * INSERT — dan riwayat berisi tiga kejadian untuk satu keadaan darurat.
 * Uji skenario 9 menangkapnya persis begitu: 3 id berbeda, 3 baris bertambah.
 *
 * Kunci penasihat tidak terikat pada baris mana pun, jadi ia bekerja justru
 * ketika belum ada apa-apa untuk dikunci. Ia dilepas otomatis saat transaksi
 * berakhir — commit maupun rollback — sehingga tidak ada jalur yang bisa
 * meninggalkannya menggantung.
 *
 * Angkanya sembarang tetapi harus TETAP: ia hanya perlu berbeda dari kunci
 * penasihat lain di aplikasi yang sama.
 */
const KUNCI_DARURAT = 918273645;

/**
 * Siapa yang boleh menutup sebuah kejadian: PEMILIKNYA, atau pengurus.
 *
 * Diputuskan dari `req.user` yang sudah diverifikasi `authMiddleware` terhadap
 * database pada setiap permintaan — bukan dari peran yang dikirim klien, dan
 * bukan dari tombol yang kebetulan tampil di layar. Menyembunyikan tombol
 * hanyalah kenyamanan; inilah penjagaannya.
 */
function bolehMenutupDarurat(pengguna, kejadian) {
  if (!pengguna) return false;
  if (PERAN_PENGURUS.includes(pengguna.role)) return true;
  return !!kejadian.user_id && kejadian.user_id === pengguna.id;
}

async function triggerAlarm(req, res) {
  try {
    const { message, latitude, longitude, pin } = req.body;

    // Verifikasi 2-Langkah: PIN Keamanan (Default: 1234 bila tidak disetel)
    const pinDarurat = (process.env.EMERGENCY_PIN && process.env.EMERGENCY_PIN.trim() !== '')
      ? process.env.EMERGENCY_PIN.trim()
      : '1234';

    if (!pin || pin.toString().trim() !== pinDarurat) {
      return res.status(403).json({
        success: false,
        message: 'PIN Keamanan tidak valid. Pemicuan alarm dibatalkan.',
      });
    }

    const userResult = await pool.query('SELECT id, nama, no_hp, alamat FROM users WHERE id = $1', [req.user.id]);
    const validUserId = (userResult.rows && userResult.rows.length > 0) ? req.user.id : null;
    const user = (userResult.rows && userResult.rows.length > 0)
      ? userResult.rows[0]
      : { id: validUserId, nama: req.user?.nama || 'Admin RT', no_hp: req.user?.no_hp || '-', alamat: req.user?.alamat || '-' };

    const result = await pool.query(
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude)
       VALUES ($1, $2, $3, $4) RETURNING ${KOLOM_ALERT_RETURNING}`,
      [validUserId, message || 'DARURAT! Warga membutuhkan bantuan!', latitude || null, longitude || null]
    );
    const alert = result.rows[0];
    const sentCount = broadcast({
      type: 'ALARM_ON',
      event: 'emergency_alert',
      alert_id: alert.id,
      user_id: user.id,
      nama: user.nama || 'Warga/Admin',
      no_hp: user.no_hp || '-',
      alamat: user.alamat || '-',
      message: alert.message,
      latitude: alert.latitude,
      longitude: alert.longitude,
      timestamp: alert.created_at,
    }, {
      // Muatan untuk perangkat tanpa akun (ESP32). Sengaja TANPA nama, nomor
      // telepon, alamat, koordinat, maupun pesan bebas dari pelapor.
      //
      // Alat itu hanya perlu tahu bahwa alarm menyala — buzzer dan LED tidak
      // membaca nama siapa pun. Sementara koneksi tanpa token bisa dibuka siapa
      // saja yang menjangkau server ini, jadi apa pun yang dikirim ke sana
      // harus dianggap terbaca publik.
      //
      // Firmware sudah aman terhadap ini: ia membaca `type` untuk memicu alarm,
      // dan field lainnya punya nilai cadangan (`| "Tidak diketahui"`).
      type: 'ALARM_ON',
      alert_id: alert.id,
      timestamp: alert.created_at,
    });

    // ALAT digerakkan lewat MQTT, bukan lagi lewat WebSocket.
    //
    // `broadcast()` di atas tetap ada dan tetap penting, tetapi tugasnya kini
    // berbeda: ia memunculkan popup darurat di aplikasi PENGURUS. Perangkat
    // ESP32 sudah berpindah ke MQTT, jadi keduanya berjalan berdampingan dengan
    // pembagian tugas yang jelas — WebSocket untuk manusia, MQTT untuk alat.
    //
    // Kegagalannya tidak menggagalkan pelaporan: baris `emergency_alerts` sudah
    // tersimpan dan pengurus sudah diberi tahu. Yang dilakukan hanyalah mencatat
    // supaya "sirene tidak berbunyi padahal alarm terkirim" bisa dilacak.
    let sireneNyala = false;
    try {
      await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.NYALA, { kodeRt: req.user.rt_kode });
      sireneNyala = true;
    } catch (e) {
      console.error('⚠️  Alarm tercatat, tetapi sirene GAGAL dinyalakan:', e.message);
      await logActivity(req, TIPE.DARURAT, `Sirene GAGAL menyala — ${ringkas(e.message, 80)}`);
    }

    // Panggil WhatsApp Notification Service (Async)
    const { sendEmergencyWA } = require('../services/whatsapp.service');
    sendEmergencyWA({
      userNama: user.nama,
      alamat: user.alamat,
      noHp: user.no_hp,
      tipeEmergency: message || 'Sinyal Darurat Panic Button',
    }).catch((e) => console.log('ℹ️ Catatan WA Alarm:', e.message));

    // Siaran push notifikasi FCM secara non-blocking di latar
    dispatcher.dispatchAsync(() => sendEmergencyPushNotification(alert, user), 'Emergency');

    // Alarm palsu maupun sungguhan sama-sama harus berjejak: yang pertama
    // untuk menindak penyalahgunaan tombol panik, yang kedua sebagai bukti
    // waktu kejadian.
    await logActivity(req, TIPE.DARURAT, `Memicu ALARM DARURAT — "${ringkas(alert.message, 80)}"`);

    // `sirene_nyala` dilaporkan apa adanya. Pelaporan darurat tetap berhasil
    // walau sirenenya gagal — tetapi pemanggil berhak tahu bedanya, karena
    // "terkirim" dan "alat berbunyi" adalah dua hal yang berbeda.
    return res.status(201).json({
      success: true,
      message: sireneNyala
        ? `Sinyal darurat terkirim ke ${sentCount} perangkat, dan sirene dinyalakan.`
        : `Sinyal darurat terkirim ke ${sentCount} perangkat, tetapi SIRENE GAGAL menyala — periksa alat secara langsung.`,
      data: { alert, broadcast_count: sentCount, sirene_nyala: sireneNyala },
    });
  } catch (err) {
    console.error('TriggerAlarm Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal mengirim sinyal darurat. Coba lagi.' });
  }
}

async function dismissAlarm(req, res) {
  try {
    const { id } = req.params;
    if (await tolakLuarRt(pool, req, res, 'emergency_alerts', id)) return;
    const { pin } = req.body;

    // Verifikasi 2-Langkah: PIN Keamanan (Default: 1234 bila tidak disetel)
    const pinDarurat = (process.env.EMERGENCY_PIN && process.env.EMERGENCY_PIN.trim() !== '')
      ? process.env.EMERGENCY_PIN.trim()
      : '1234';

    if (!pin || pin.toString().trim() !== pinDarurat) {
      return res.status(403).json({
        success: false,
        message: 'PIN Keamanan tidak valid. Penutupan status darurat dibatalkan.',
      });
    }

    // Pastikan alert ada dan periksa otorisasi (Pemilik alarm ATAU Pengurus/Admin)
    const alertCheck = await pool.query('SELECT id, user_id, status FROM emergency_alerts WHERE id = $1', [id]);
    if (alertCheck.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Alert tidak ditemukan.' });
    }

    const alertItem = alertCheck.rows[0];
    const isOwner = alertItem.user_id === req.user.id;
    // Daftar peran yang SAMA dengan `matikanDarurat`, bukan salinan kedua.
    const isPengurus = PERAN_PENGURUS.includes(req.user.role);

    if (!isOwner && !isPengurus) {
      return res.status(403).json({
        success: false,
        message: 'Anda tidak memiliki hak untuk mematikan sinyal darurat milik warga lain.',
      });
    }

    // Pastikan user ID pelaksana valid di tabel users untuk menghindari FK violation
    const userCheck = await pool.query('SELECT id, nama FROM users WHERE id = $1', [req.user.id]);
    const validUserId = (userCheck.rows && userCheck.rows.length > 0) ? req.user.id : null;
    const adminName = (userCheck.rows && userCheck.rows.length > 0) ? userCheck.rows[0].nama : (req.user?.nama || 'Pengurus/Pelapor');

    const result = await pool.query(
      `UPDATE emergency_alerts SET status = 'dismissed', dismissed_by = $1, dismissed_at = NOW()
       WHERE id = $2 AND status = 'active' RETURNING ${KOLOM_ALERT_RETURNING}`,
      [validUserId, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Alert aktif tidak ditemukan atau sudah diselesaikan.' });
    }

    const sentCount = broadcast({
      type: 'ALARM_OFF',
      event: 'emergency_dismissed',
      alert_id: id,
      dismissed_by: validUserId,
      dismissed_by_nama: adminName,
      timestamp: new Date().toISOString(),
    }, {
      // Perangkat WAJIB menerima perintah mati. Menahannya berarti buzzer terus
      // berbunyi setelah pengurus menekan "Selesaikan" — kegagalan yang jauh
      // lebih terasa daripada kebocoran mana pun. Nama yang mematikan tidak
      // ikut dikirim; alat tidak membutuhkannya.
      type: 'ALARM_OFF',
      alert_id: id,
      timestamp: new Date().toISOString(),
    });
    // Sirene wajib ikut mati. Buzzer yang terus berbunyi setelah pengurus
    // menekan "Selesaikan" jauh lebih terasa daripada kegagalan mana pun di
    // aplikasi, jadi kegagalannya dicatat DAN dilaporkan ke pemanggil.
    let sireneMati = false;
    try {
      await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.MATI, { kodeRt: req.user.rt_kode });
      sireneMati = true;
    } catch (e) {
      console.error('⚠️  Status ditutup, tetapi sirene GAGAL dimatikan:', e.message);
      await logActivity(req, TIPE.DARURAT, `Sirene GAGAL dimatikan — ${ringkas(e.message, 80)}`);
    }

    // Siapa yang mematikan alarm, dan kapan. Ini pertanyaan pertama bila
    // kelak ada keluhan "alarm dimatikan padahal keadaan belum aman".
    await logActivity(req, TIPE.DARURAT, `Mematikan alarm darurat (id ${id})`);

    return res.status(200).json({
      success: true,
      message: sireneMati
        ? `Status darurat diselesaikan dan sirene dimatikan. Broadcast ke ${sentCount} perangkat.`
        : `Status darurat diselesaikan, tetapi SIRENE GAGAL dimatikan — matikan alat secara manual.`,
      data: { ...result.rows[0], dismissed_by_nama: adminName, sirene_mati: sireneMati },
    });
  } catch (err) {
    console.error('DismissAlarm Error:', err.message);
    return res.status(500).json({ success: false, message: 'Gagal menyelesaikan status darurat. Coba lagi.' });
  }
}

async function getAlerts(req, res) {
  try {
    const { status, page, limit } = req.query;

    const queryParams = [];
    let whereClause = 'WHERE 1=1';

    // Pelingkupan RT, sebelum penyaringan lain, supaya daftar dan
    // penghitungan totalnya memakai batas yang sama persis.
    whereClause += klausaRt(req, 'ea', queryParams);

    if (status) {
      queryParams.push(status);
      whereClause += ` AND ea.status = $${queryParams.length}`;
    }

    let limitNum = parseInt(limit, 10);
    let pageNum = parseInt(page, 10);
    const usePagination = !isNaN(limitNum) && limitNum > 0;

    if (usePagination) {
      if (isNaN(pageNum) || pageNum < 1) pageNum = 1;
    }

    const countResult = await pool.query(
      `SELECT COUNT(*) FROM emergency_alerts ea ${whereClause}`,
      queryParams
    );
    const totalData = parseInt(countResult.rows[0].count, 10);

    let query = `SELECT ${KOLOM_ALERT},
      COALESCE(ak.nama, u.nama, 'Administrator') AS nama_warga,
      COALESCE(
        NULLIF(TRIM(u.alamat), ''),
        NULLIF(TRIM(k.alamat), ''),
        CASE WHEN k.blok IS NOT NULL AND TRIM(k.blok) != '' THEN CONCAT('Blok ', k.blok) ELSE NULL END,
        'Alamat tidak tercatat'
      ) AS alamat,
      COALESCE(NULLIF(TRIM(u.no_hp), ''), NULLIF(TRIM(ak.no_hp), ''), '-') AS no_hp,
      COALESCE(u.no_kk, k.no_kk, '') AS no_kk,
      COALESCE(k.blok, '') AS blok,
      COALESCE(d.nama, CASE WHEN ea.dismissed_by IS NOT NULL THEN 'Pengurus RT' ELSE NULL END) AS dismissed_by_nama
      FROM emergency_alerts ea 
      LEFT JOIN users u ON ea.user_id = u.id 
      LEFT JOIN users d ON ea.dismissed_by = d.id 
      LEFT JOIN anggota_keluarga ak ON (u.nik IS NOT NULL AND u.nik = ak.nik)
      LEFT JOIN keluarga k ON (k.id = ak.keluarga_id OR (u.no_kk IS NOT NULL AND k.no_kk = u.no_kk))
      ${whereClause}
      ORDER BY ea.created_at DESC`;

    if (usePagination) {
      const offset = (pageNum - 1) * limitNum;
      queryParams.push(limitNum);
      query += ` LIMIT $${queryParams.length}`;
      queryParams.push(offset);
      query += ` OFFSET $${queryParams.length}`;
    } else {
      query += ' LIMIT 50';
    }

    const result = await pool.query(query, queryParams);

    const responseData = {
      success: true,
      count: result.rows.length,
      data: result.rows,
    };

    if (usePagination) {
      responseData.pagination = {
        total_data: totalData,
        total_pages: Math.ceil(totalData / limitNum) || 1,
        current_page: pageNum,
        per_page: limitNum,
      };
    }

    return res.status(200).json(responseData);
  } catch (err) {
    console.error('GetAlerts Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getActiveAlerts(req, res) {
  try {
    // Dilingkupi per RT seperti getAlerts, dan di sini taruhannya paling
    // tinggi di seluruh aplikasi: baris ini membawa NAMA, ALAMAT RUMAH, dan
    // NOMOR TELEPON orang yang sedang menekan tombol darurat. Tanpa
    // penyaringan, setiap pengurus di setiap RT menerima ketiganya — pada
    // saat orang itu paling rentan.
    //
    // Sirene fisiknya sudah dialamatkan per RT lewat topik MQTT sejak awal;
    // yang tertinggal justru sisi yang membawa data pribadinya.
    const params = [];
    const result = await pool.query(
      `SELECT ${KOLOM_ALERT},
        COALESCE(u.nama, 'Administrator') AS nama_warga,
        COALESCE(u.alamat, '') AS alamat,
        u.no_hp
        FROM emergency_alerts ea
        LEFT JOIN users u ON ea.user_id = u.id
        WHERE ea.status = 'active'
        ${klausaRt(req, 'ea', params)}
        ORDER BY ea.created_at DESC`,
      params
    );
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetActiveAlerts Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

/**
 * POST /api/emergency/alarm — menyalakan atau mematikan alat lewat MQTT.
 *
 * ===================================================================
 * Kenapa endpoint tersendiri, bukan menumpang /trigger
 * ===================================================================
 *
 * `/trigger` mencatat SEBUAH KEJADIAN: ia menulis baris `emergency_alerts`
 * dengan pelapor, pesan, dan koordinat, lalu memberi tahu pengurus. `/dismiss`
 * menutup kejadian itu dan menuntut `:id`-nya.
 *
 * Tombol di dasbor menjawab kebutuhan yang berbeda: menyalakan sirene sekarang,
 * dan mematikannya lagi. Ia tidak selalu punya `alert_id` — mematikan alarm
 * setelah aplikasi ditutup dan dibuka lagi tidak boleh menuntut orang mengingat
 * id kejadian. Memaksakan keduanya ke satu endpoint berarti `/dismiss` harus
 * menerima `:id` opsional, dan endpoint yang argumennya kadang wajib kadang
 * tidak adalah endpoint yang cepat atau lambat dipanggil salah.
 *
 * Penjagaannya sama persis dengan endpoint darurat lain: `authMiddleware` di
 * berkas rute, PIN diverifikasi di sini, dan setiap penekanan masuk ke
 * `activity_logs` — termasuk yang PIN-nya salah, karena percobaan yang gagal
 * justru yang paling perlu terlihat.
 */
async function kendaliAlarm(req, res) {
  const aksiMentah = (req.body?.aksi ?? '').toString().trim().toUpperCase();
  const { pin } = req.body || {};

  if (aksiMentah !== mqttAlarm.PERINTAH.NYALA && aksiMentah !== mqttAlarm.PERINTAH.MATI) {
    return res.status(400).json({
      success: false,
      message: `Aksi harus "${mqttAlarm.PERINTAH.NYALA}" atau "${mqttAlarm.PERINTAH.MATI}".`,
    });
  }

  // PIN diperiksa LEBIH DULU daripada kesiapan broker, dan urutan itu
  // menentukan.
  //
  // Terbalik, percobaan PIN yang salah dijawab 503 dan keluar sebelum sempat
  // dicatat — sehingga selama broker mati, seratus tebakan PIN tidak
  // meninggalkan satu baris pun di Log Aktivitas. Keadaan "alarm sedang tidak
  // bisa dipakai" justru saat penyalahgunaan paling mungkin tidak terlihat.
  if (!pinCocok(pin)) {
    await logActivity(req, TIPE.DARURAT, `PIN darurat SALAH saat mencoba ${aksiMentah} alarm`);
    return res.status(403).json({
      success: false,
      message: 'PIN darurat tidak valid.',
    });
  }

  // Keterangan kejadian WAJIB untuk ON, dan diperiksa SESUDAH PIN.
  //
  // Urutan itu menjaga sifat yang sudah ada: setiap percobaan PIN — terutama
  // yang salah — tetap masuk ke Log Aktivitas. Kalau keterangan diperiksa
  // lebih dulu, penebak PIN cukup mengirim badan permintaan tanpa keterangan
  // untuk dijawab 400 dan keluar sebelum sempat tercatat.
  //
  // Diperiksa juga SEBELUM kesiapan broker: "keterangan wajib diisi" adalah
  // sesuatu yang bisa diperbaiki pemakai saat itu juga, sedangkan 503 hanya
  // menyuruhnya menunggu. Yang bisa ditindaklanjuti disampaikan lebih dulu.
  let keterangan = null;
  let legacyTanpaKeterangan = false;

  if (aksiMentah === mqttAlarm.PERINTAH.NYALA) {
    // `keterangan` adalah nama baru; `message` diterima juga supaya klien yang
    // sudah beredar tidak putus hanya karena berbeda nama field.
    const hasil = validasiKeterangan(
      req.body?.keterangan ?? req.body?.message
    );

    // ROLLOUT BERTAHAP. Keterangan yang TIDAK DIKIRIM SAMA SEKALI masih
    // diterima selama Tahap 1, karena APK 1.1.0+3 yang beredar memang tidak
    // mengirimnya — dan menolaknya berarti mematikan tombol darurat di setiap
    // ponsel yang belum diperbarui.
    //
    // Yang TIDAK ikut dilonggarkan: keterangan yang dikirim tetapi melanggar
    // batas panjang. Itu bukan klien lama, melainkan klien baru yang mengirim
    // data buruk, dan menerimanya diam-diam akan menyimpan potongan kalimat ke
    // riwayat darurat.
    const bolehLewat =
      hasil.kosong === true && !WAJIBKAN_KETERANGAN_DARURAT;

    if (!hasil.ok && !bolehLewat) {
      await logActivity(
        req,
        TIPE.DARURAT,
        `Gagal menyalakan alarm — keterangan kejadian tidak sah (${hasil.pesan})`
      );
      return res.status(400).json({ success: false, message: hasil.pesan });
    }

    if (hasil.ok) {
      keterangan = hasil.nilai;
    } else {
      // Ditandai apa adanya, bukan dikarang. Menuliskan kalimat yang terdengar
      // manusiawi akan tampil di Riwayat Darurat seolah-olah pelapor benar-benar
      // mengetiknya — memalsukan catatan yang justru paling tidak boleh dipalsukan.
      keterangan = PENANDA_LEGACY;
      legacyTanpaKeterangan = true;
      catatDaruratTanpaKeterangan(req);
    }
  }

  // Broker belum disetel → 503 yang MENYEBUT sebabnya. Bukan 500 yang
  // membiarkan orang menebak, dan bukan diam-diam sukses.
  if (!mqttAlarm.terkonfigurasi()) {
    await logActivity(req, TIPE.DARURAT, `Gagal ${aksiMentah} alarm — MQTT_URL belum disetel`);
    return res.status(503).json({
      success: false,
      message: 'Alarm belum bisa dipakai: MQTT_URL belum disetel di server. Hubungi administrator.',
    });
  }

  // Keterangan dioper sebagai argumen, bukan dibaca ulang dari `req.body` di
  // dalam `nyalakanDarurat`. Membacanya dua kali berarti ada dua tempat yang
  // bisa berbeda pendapat tentang nilai mana yang sah, dan yang di dalam
  // transaksi akan melewatkan validasi di atas.
  return aksiMentah === mqttAlarm.PERINTAH.NYALA
    ? nyalakanDarurat(req, res, keterangan, legacyTanpaKeterangan)
    : matikanDarurat(req, res);
}

/**
 * ON — membuat TEPAT SATU kejadian darurat, lalu membunyikan sirene.
 *
 * ===================================================================
 * Akar masalah yang ditutup di sini
 * ===================================================================
 *
 * Sebelumnya endpoint ini TIDAK MENYENTUH DATABASE SAMA SEKALI. Ia hanya
 * menerbitkan MQTT. Akibatnya menekan NYALAKAN di dasbor tidak pernah membuat
 * kejadian, dan layar Status Darurat selalu kosong walau sirene benar-benar
 * meraung — riwayatnya hilang justru untuk peristiwa yang paling perlu dicatat.
 *
 * ===================================================================
 * Kenapa transaksi dan row lock
 * ===================================================================
 *
 * Dua orang menekan NYALAKAN pada detik yang sama harus tetap menghasilkan
 * SATU kejadian, bukan dua. `FOR UPDATE` membuat yang kalah menunggu, lalu
 * membaca keadaan SETELAH pemenang commit — bukan keadaan basi dari sebelum
 * transaksi. Pola yang sama sudah dipakai `payBill` dan penukaran tiket unduh.
 *
 * ===================================================================
 * Urutannya: buat baris -> terbitkan MQTT -> commit
 * ===================================================================
 *
 * Kalau penerbitan gagal, transaksi di-ROLLBACK sehingga tidak ada kejadian
 * yang tercatat untuk sirene yang tidak pernah berbunyi. Riwayat yang
 * menyatakan "darurat pukul 21.10" padahal tidak ada yang berbunyi lebih buruk
 * daripada tidak ada riwayat sama sekali: ia membuat orang mengira sistemnya
 * bekerja.
 */
async function nyalakanDarurat(req, res, keterangan, legacyTanpaKeterangan = false) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [KUNCI_DARURAT]);

    const aktif = await client.query(
      `SELECT id, user_id, message, created_at::timestamptz AS created_at
       FROM emergency_alerts
       WHERE status = 'active' ORDER BY created_at DESC LIMIT 1 FOR UPDATE`
    );

    let kejadian;
    let baru;

    if (aktif.rows.length > 0) {
      // IDEMPOTEN. Tekan dua kali, coba ulang setelah jaringan putus, atau dua
      // orang menekan bersamaan — semuanya menunjuk kejadian yang SAMA.
      //
      // Keterangan yang baru dikirim SENGAJA DIABAIKAN, bukan ditimpakan.
      // Kejadian ini sudah punya pelapor dan ceritanya sendiri; menimpanya
      // berarti orang kedua bisa menghapus keterangan orang pertama hanya
      // dengan menekan NYALAKAN — dan pemiliknya tetap tercatat orang pertama,
      // sehingga riwayat akan memasangkan nama satu orang dengan kalimat orang
      // lain. Mengubah keterangan menuntut alur suntingnya sendiri.
      kejadian = aktif.rows[0];
      baru = false;
    } else {
      const dibuat = await client.query(
        `INSERT INTO emergency_alerts (user_id, message, status)
         VALUES ($1, $2, 'active')
         RETURNING id, user_id, message, created_at::timestamptz AS created_at`,
        [req.user.id, keterangan]
      );
      kejadian = dibuat.rows[0];
      baru = true;
    }

    // Sirene tetap dibunyikan ulang walau kejadiannya sudah ada. Perintahnya
    // retained dan idempoten di sisi alat, dan menegaskan ulang jauh lebih
    // aman daripada berasumsi alat masih mendengar perintah sebelumnya.
    await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.NYALA, { kodeRt: req.user.rt_kode });

    await client.query('COMMIT');

    // Siaran SESUDAH commit, memakai format yang sama persis dengan
    // `triggerAlarm` — tipe, nama field, dan muatan perangkat yang direduksi.
    // Klien sudah mengenali bentuk ini, jadi tidak ada protokol baru.
    //
    // Ditembakkan juga pada penekanan berulang (`baru === false`), dan itu
    // disengaja: perangkat yang TIDAK sempat menerima siaran pertama akan
    // menganggapnya peristiwa baru lalu menyusul keadaan, sementara perangkat
    // yang sudah menerimanya menyaringnya sendiri karena `alert_id`-nya sama.
    // Alasannya sama dengan MQTT di atas yang juga selalu ditegaskan ulang.
    // Tetap SATU siaran untuk satu permintaan.
    siarkanPerubahanDarurat({
      type: 'ALARM_ON',
      event: 'emergency_alert',
      alert_id: kejadian.id,
      user_id: kejadian.user_id,
      nama: req.user?.nama || 'Warga/Admin',
      no_hp: req.user?.no_hp || '-',
      alamat: req.user?.alamat || '-',
      message: kejadian.message,
      timestamp: kejadian.created_at,
    }, {
      // Muatan perangkat tanpa akun: hanya cukup untuk membunyikan alarm,
      // tanpa nama, alamat, atau keterangan bebas dari pelapor.
      type: 'ALARM_ON',
      alert_id: kejadian.id,
      timestamp: kejadian.created_at,
    });

    // Siaran push notifikasi FCM hanya untuk kejadian baru (mencegah duplikasi pada re-trigger)
    if (baru) {
      dispatcher.dispatchAsync(() => sendEmergencyPushNotification(kejadian, req.user), 'Emergency');
    }

    await logActivity(
      req,
      TIPE.DARURAT,
      baru
        ? (legacyTanpaKeterangan
            // Jejaknya menyebut penyebabnya, bukan sekadar mencatat kejadian.
            // Inilah yang membedakan "warga tidak mengisi" dari "aplikasinya
            // memang belum bisa mengisi" saat kelak riwayatnya dibaca.
            ? `MENYALAKAN alarm darurat (kejadian ${kejadian.id}) TANPA keterangan — klien lama (legacy_without_keterangan)`
            : `MENYALAKAN alarm darurat lewat tombol dasbor (kejadian ${kejadian.id}) — "${ringkas(kejadian.message, 80)}"`)
        : `Menekan NYALAKAN saat kejadian ${kejadian.id} masih aktif — tidak membuat kejadian baru, keterangan asli dipertahankan`
    );

    return res.status(baru ? 201 : 200).json({
      success: true,
      message: baru
        ? 'Alarm dinyalakan.'
        : 'Alarm sudah menyala sejak sebelumnya. Sirene ditegaskan ulang.',
      data: {
        aksi: mqttAlarm.PERINTAH.NYALA,
        topik: mqttAlarm.topikAlarm(req.user.rt_kode),
        kejadian_baru: baru,
        emergency_id: kejadian.id,
        // Keterangan yang BERLAKU pada kejadian, bukan yang barusan dikirim.
        // Pada penekanan kedua keduanya berbeda, dan yang berhak tampil di
        // layar adalah milik kejadian yang benar-benar aktif.
        keterangan: kejadian.message,
        // Dibaca dari isi kejadian, bukan dari argumen: pada penekanan kedua
        // yang menentukan adalah kejadian yang sudah ada, bukan permintaan
        // yang barusan datang.
        legacy_without_keterangan: kejadian.message === PENANDA_LEGACY,
      },
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    return balasGagalAlarm(req, res, err, mqttAlarm.PERINTAH.NYALA);
  } finally {
    client.release();
  }
}

/**
 * OFF — menutup kejadian aktif, dengan otorisasi PEMILIK-atau-PENGURUS.
 *
 * ===================================================================
 * Otorisasi ditegakkan DI SINI, bukan dengan menyembunyikan tombol
 * ===================================================================
 *
 * Warga hanya boleh menutup kejadian yang ia sendiri nyalakan. Pengurus dan
 * admin boleh menutup milik siapa pun. Peran diambil dari `req.user` yang
 * sudah diverifikasi `authMiddleware` terhadap database pada setiap
 * permintaan — bukan dari apa pun yang dikirim klien.
 *
 * Daftar perannya memakai `PERAN_PENGURUS` yang sama dengan `dismissAlarm`,
 * supaya dua jalur mematikan alarm tidak mungkin berbeda aturan.
 *
 * ===================================================================
 * Ketika tidak ada kejadian aktif
 * ===================================================================
 *
 * Perintah MATI tetap diterbitkan, dan TIDAK ada riwayat yang dibuat.
 *
 * Terdengar longgar, tetapi kebalikannya berbahaya: bila sirene terlanjur
 * menyala tanpa kejadian tercatat — misalnya pesan retained dari sebelum
 * fitur ini ada, atau baris kejadian sudah ditutup lewat jalur lain — menolak
 * menerbitkan OFF berarti buzzer tidak bisa dihentikan dari aplikasi sama
 * sekali. Buzzer yang tidak bisa dihentikan lebih buruk daripada satu perintah
 * MATI yang berlebih.
 *
 * Yang dijaga tetap dijaga: begitu ADA kejadian aktif, pemeriksaan kepemilikan
 * berlaku penuh dan tidak bisa dilewati lewat cabang ini.
 */
async function matikanDarurat(req, res) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [KUNCI_DARURAT]);

    const aktif = await client.query(
      `SELECT id, user_id, created_at::timestamptz AS created_at FROM emergency_alerts
       WHERE status = 'active' ORDER BY created_at DESC LIMIT 1 FOR UPDATE`
    );

    if (aktif.rows.length === 0) {
      await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.MATI, { kodeRt: req.user.rt_kode });
      await client.query('COMMIT');

      await logActivity(req, TIPE.DARURAT, 'Menekan MATIKAN saat tidak ada kejadian darurat aktif');

      return res.status(200).json({
        success: true,
        message: 'Tidak ada darurat aktif. Perintah mati tetap dikirim ke alat.',
        data: {
          aksi: mqttAlarm.PERINTAH.MATI,
          topik: mqttAlarm.topikAlarm(req.user.rt_kode),
          emergency_id: null,
          kejadian_ditutup: false,
        },
      });
    }

    const kejadian = aktif.rows[0];
    if (!bolehMenutupDarurat(req.user, kejadian)) {
      await client.query('ROLLBACK');
      await logActivity(
        req,
        TIPE.DARURAT,
        `DITOLAK mematikan kejadian ${kejadian.id} milik warga lain`
      );
      return res.status(403).json({
        success: false,
        message: 'Darurat ini dinyalakan warga lain. Hanya pemiliknya atau Pengurus RT yang boleh mematikannya.',
      });
    }

    // `AND status = 'active'` diulang di sini walau barisnya sudah dikunci:
    // ia yang menjamin sebuah kejadian tidak bisa ditutup dua kali, dan nol
    // baris kembali berarti pemenang lain sudah mendahului.
    const ditutup = await client.query(
      `UPDATE emergency_alerts
       SET status = 'dismissed', dismissed_by = $1, dismissed_at = NOW()
       WHERE id = $2 AND status = 'active'
       RETURNING id, user_id, message,
                 created_at::timestamptz AS created_at,
                 dismissed_at::timestamptz AS dismissed_at`,
      [req.user.id, kejadian.id]
    );

    if (ditutup.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        success: false,
        message: 'Kejadian darurat itu sudah diselesaikan oleh orang lain.',
      });
    }

    await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.MATI, { kodeRt: req.user.rt_kode });
    await client.query('COMMIT');

    // Format sama dengan `dismissAlarm`. Hanya ditembakkan di cabang ini —
    // cabang "tidak ada kejadian aktif" di atas tidak mengubah satu baris pun,
    // jadi tidak ada perubahan yang perlu diumumkan ke perangkat lain.
    siarkanPerubahanDarurat({
      type: 'ALARM_OFF',
      event: 'emergency_dismissed',
      alert_id: ditutup.rows[0].id,
      dismissed_by: req.user.id,
      dismissed_by_nama: req.user?.nama || 'Pengurus/Pelapor',
      timestamp: ditutup.rows[0].dismissed_at,
    }, {
      // Perangkat WAJIB menerima perintah mati; nama yang mematikan tidak
      // dibutuhkannya.
      type: 'ALARM_OFF',
      alert_id: ditutup.rows[0].id,
      timestamp: ditutup.rows[0].dismissed_at,
    });

    await logActivity(
      req,
      TIPE.DARURAT,
      `Menyelesaikan kejadian darurat ${kejadian.id} lewat tombol dasbor`
    );

    return res.status(200).json({
      success: true,
      message: 'Alarm dimatikan.',
      data: {
        aksi: mqttAlarm.PERINTAH.MATI,
        topik: mqttAlarm.topikAlarm(req.user.rt_kode),
        emergency_id: ditutup.rows[0].id,
        kejadian_ditutup: true,
        // Keterangan kejadian yang baru saja ditutup. Sama barisnya, bukan
        // baris baru — OFF memperbarui kejadian yang sama menjadi selesai.
        keterangan: ditutup.rows[0].message,
      },
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    return balasGagalAlarm(req, res, err, mqttAlarm.PERINTAH.MATI);
  } finally {
    client.release();
  }
}

/**
 * Kegagalan menerbitkan TIDAK BOLEH dilaporkan sebagai berhasil. Pengguna yang
 * percaya alarmnya berbunyi akan berhenti mencari cara lain.
 */
async function balasGagalAlarm(req, res, err, aksi) {
  console.error('KendaliAlarm Error:', err.message);
  await logActivity(req, TIPE.DARURAT, `GAGAL ${aksi} alarm — ${ringkas(err.message, 80)}`);

  const kodeHttp = err.kode === 'MQTT_TIMEOUT' ? 504 : 503;
  return res.status(kodeHttp).json({
    success: false,
    message: err.kode === 'MQTT_TIMEOUT'
      ? 'Broker alarm tidak menjawab. Alarm BELUM tentu berubah — periksa alat secara langsung.'
      : 'Gagal mengirim perintah ke alarm. Keadaan alat TIDAK berubah.',
  });
}

/**
 * GET /api/emergency/alarm/status — kesiapan jalur alarm DAN kejadian aktif.
 *
 * Dasbor mengambil keadaan sirene dari sini, bukan dari tebakan lokalnya
 * sendiri. Aplikasi yang menyimpan keadaan di memori akan salah begitu ia
 * dibuka ulang, atau begitu orang lain menyalakan alarm dari perangkat lain.
 *
 * `boleh_matikan` dihitung DI SERVER dengan aturan yang sama persis dengan
 * yang menjaga endpoint OFF. Klien memakainya untuk memilih tombol mana yang
 * ditampilkan — tetapi bila klien mengabaikannya dan tetap mengirim OFF,
 * penjagaan di `matikanDarurat` yang menolak. Nilai ini kenyamanan, bukan
 * pengaman.
 *
 * Field lama (`terkonfigurasi`, `tersambung`, …) dipertahankan apa adanya
 * supaya klien yang sudah beredar tidak putus.
 */
async function statusAlarm(req, res) {
  let aktif = null;
  try {
    const r = await pool.query(
      `SELECT ea.id, ea.user_id, ea.message,
              ea.created_at::timestamptz AS created_at,
              COALESCE(u.nama, 'Tidak diketahui') AS nama_pengaktif
       FROM emergency_alerts ea
       LEFT JOIN users u ON u.id = ea.user_id
       WHERE ea.status = 'active'
       ORDER BY ea.created_at DESC LIMIT 1`
    );
    if (r.rows.length > 0) {
      const k = r.rows[0];
      aktif = {
        emergency_id: k.id,
        user_id: k.user_id,
        nama_pengaktif: k.nama_pengaktif,
        message: k.message,
        created_at: k.created_at,
        milik_saya: !!k.user_id && k.user_id === req.user.id,
        boleh_matikan: bolehMenutupDarurat(req.user, k),
      };
    }
  } catch (e) {
    // Kegagalan membaca kejadian tidak boleh menjatuhkan pembacaan kesiapan
    // broker — dua hal berbeda, dan yang satu masih berguna tanpa yang lain.
    console.error('StatusAlarm (kejadian aktif) Error:', e.message);
  }

  return res.status(200).json({
    success: true,
    data: {
      terkonfigurasi: mqttAlarm.terkonfigurasi(),
      tersambung: mqttAlarm.tersambung(),
      pernah_tersambung: mqttAlarm.pernahTersambung(),
      topik: mqttAlarm.topikAlarm(req.user.rt_kode),
      alarm_aktif: aktif !== null,
      kejadian_aktif: aktif,
    },
  });
}

module.exports = {
  triggerAlarm,
  dismissAlarm,
  getAlerts,
  getActiveAlerts,
  kendaliAlarm,
  statusAlarm,
  sendEmergencyPushNotification,
  resetSentEmergencyIds,
};
