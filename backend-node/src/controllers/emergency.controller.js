const { pool } = require('../config/database');
const { logActivity, ringkas, TIPE } = require('../services/log.service');
const { broadcast } = require('../config/websocket');
const mqttAlarm = require('../config/mqtt');

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
      `INSERT INTO emergency_alerts (user_id, message, latitude, longitude) VALUES ($1, $2, $3, $4) RETURNING *`,
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
      await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.NYALA);
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
      `UPDATE emergency_alerts SET status = 'dismissed', dismissed_by = $1, dismissed_at = NOW() WHERE id = $2 AND status = 'active' RETURNING *`,
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
      await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.MATI);
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

    let query = `SELECT ea.*, 
      COALESCE(u.nama, 'Administrator') AS nama_warga, 
      COALESCE(u.alamat, '') AS alamat, 
      u.no_hp, 
      COALESCE(d.nama, CASE WHEN ea.dismissed_by IS NOT NULL THEN 'Pengurus RT' ELSE NULL END) AS dismissed_by_nama
      FROM emergency_alerts ea 
      LEFT JOIN users u ON ea.user_id = u.id 
      LEFT JOIN users d ON ea.dismissed_by = d.id 
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
    const result = await pool.query(
      `SELECT ea.*, 
        COALESCE(u.nama, 'Administrator') AS nama_warga, 
        COALESCE(u.alamat, '') AS alamat, 
        u.no_hp 
        FROM emergency_alerts ea 
        LEFT JOIN users u ON ea.user_id = u.id 
        WHERE ea.status = 'active' 
        ORDER BY ea.created_at DESC`
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

  // Broker belum disetel → 503 yang MENYEBUT sebabnya. Bukan 500 yang
  // membiarkan orang menebak, dan bukan diam-diam sukses.
  if (!mqttAlarm.terkonfigurasi()) {
    await logActivity(req, TIPE.DARURAT, `Gagal ${aksiMentah} alarm — MQTT_URL belum disetel`);
    return res.status(503).json({
      success: false,
      message: 'Alarm belum bisa dipakai: MQTT_URL belum disetel di server. Hubungi administrator.',
    });
  }

  return aksiMentah === mqttAlarm.PERINTAH.NYALA
    ? nyalakanDarurat(req, res)
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
async function nyalakanDarurat(req, res) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [KUNCI_DARURAT]);

    const aktif = await client.query(
      `SELECT id, user_id, created_at FROM emergency_alerts
       WHERE status = 'active' ORDER BY created_at DESC LIMIT 1 FOR UPDATE`
    );

    let kejadian;
    let baru;

    if (aktif.rows.length > 0) {
      // IDEMPOTEN. Tekan dua kali, coba ulang setelah jaringan putus, atau dua
      // orang menekan bersamaan — semuanya menunjuk kejadian yang SAMA.
      kejadian = aktif.rows[0];
      baru = false;
    } else {
      const dibuat = await client.query(
        `INSERT INTO emergency_alerts (user_id, message, status)
         VALUES ($1, $2, 'active') RETURNING id, user_id, created_at`,
        [req.user.id, (req.body?.message || 'Alarm darurat dinyalakan dari dasbor').toString().slice(0, 500)]
      );
      kejadian = dibuat.rows[0];
      baru = true;
    }

    // Sirene tetap dibunyikan ulang walau kejadiannya sudah ada. Perintahnya
    // retained dan idempoten di sisi alat, dan menegaskan ulang jauh lebih
    // aman daripada berasumsi alat masih mendengar perintah sebelumnya.
    await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.NYALA);

    await client.query('COMMIT');

    await logActivity(
      req,
      TIPE.DARURAT,
      baru
        ? `MENYALAKAN alarm darurat lewat tombol dasbor (kejadian ${kejadian.id})`
        : `Menekan NYALAKAN saat kejadian ${kejadian.id} masih aktif — tidak membuat kejadian baru`
    );

    return res.status(baru ? 201 : 200).json({
      success: true,
      message: baru
        ? 'Alarm dinyalakan.'
        : 'Alarm sudah menyala sejak sebelumnya. Sirene ditegaskan ulang.',
      data: {
        aksi: mqttAlarm.PERINTAH.NYALA,
        topik: mqttAlarm.TOPIK_ALARM,
        kejadian_baru: baru,
        emergency_id: kejadian.id,
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
      `SELECT id, user_id, created_at FROM emergency_alerts
       WHERE status = 'active' ORDER BY created_at DESC LIMIT 1 FOR UPDATE`
    );

    if (aktif.rows.length === 0) {
      await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.MATI);
      await client.query('COMMIT');

      await logActivity(req, TIPE.DARURAT, 'Menekan MATIKAN saat tidak ada kejadian darurat aktif');

      return res.status(200).json({
        success: true,
        message: 'Tidak ada darurat aktif. Perintah mati tetap dikirim ke alat.',
        data: {
          aksi: mqttAlarm.PERINTAH.MATI,
          topik: mqttAlarm.TOPIK_ALARM,
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
       RETURNING id, user_id, created_at, dismissed_at`,
      [req.user.id, kejadian.id]
    );

    if (ditutup.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        success: false,
        message: 'Kejadian darurat itu sudah diselesaikan oleh orang lain.',
      });
    }

    await mqttAlarm.terbitkanPerintahAlarm(mqttAlarm.PERINTAH.MATI);
    await client.query('COMMIT');

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
        topik: mqttAlarm.TOPIK_ALARM,
        emergency_id: ditutup.rows[0].id,
        kejadian_ditutup: true,
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
      `SELECT ea.id, ea.user_id, ea.message, ea.created_at,
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
      topik: mqttAlarm.TOPIK_ALARM,
      alarm_aktif: aktif !== null,
      kejadian_aktif: aktif,
    },
  });
}

module.exports = {
  triggerAlarm, dismissAlarm, getAlerts, getActiveAlerts, kendaliAlarm, statusAlarm,
};
