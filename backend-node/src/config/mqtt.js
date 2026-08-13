const mqtt = require('mqtt');

/**
 * Penerbit perintah alarm lewat MQTT.
 *
 * ===================================================================
 * Kredensial TIDAK PERNAH meninggalkan proses ini
 * ===================================================================
 *
 * Broker, nama pengguna, dan kata sandi dibaca dari environment dan dipakai di
 * sini saja. Klien Flutter maupun Web tidak pernah menerimanya, tidak pernah
 * menyambung ke broker, dan tidak perlu tahu broker itu ada: mereka memanggil
 * endpoint HTTP biasa yang sudah dijaga `authMiddleware`, lalu server ini yang
 * menerbitkan perintahnya.
 *
 * Kalau kredensial dikirim ke klien, siapa pun yang memasang APK bisa
 * menerbitkan `ON` ke topik alarm tanpa melewati PIN, tanpa melewati RBAC, dan
 * tanpa meninggalkan jejak di `activity_logs`.
 *
 * ===================================================================
 * Sambungan dibuat malas, dan kegagalannya tidak boleh mendiamkan server
 * ===================================================================
 *
 * Broker bisa saja belum disetel — `MQTT_URL` kosong pada pemasangan yang belum
 * dikonfigurasi. Dalam keadaan itu modul ini TIDAK melempar saat dimuat dan
 * TIDAK menghentikan server; ia melaporkan dirinya tidak siap, dan endpoint
 * alarm menjawab 503 dengan menyebut sebabnya.
 *
 * Alasannya sama dengan yang sudah dipakai `EMERGENCY_PIN`: satu variabel yang
 * lupa diisi tidak boleh menjatuhkan SELURUH aplikasi demi satu fitur. Yang
 * dituntut adalah kegagalannya berbunyi jelas, bukan diam.
 */

const URL_BROKER = (process.env.MQTT_URL || '').trim();
const TOPIK_ALARM = (process.env.MQTT_TOPIC_ALARM || 'smart-community/alarm/command').trim();

/** Perintah yang boleh diterbitkan. Daftar tertutup, bukan string bebas. */
const PERINTAH = Object.freeze({ NYALA: 'ON', MATI: 'OFF' });

let klien = null;
let siapPernah = false;

/** Menyambung sekali, lalu dipakai ulang. Null bila broker belum disetel. */
function ambilKlien() {
  if (!URL_BROKER) return null;
  if (klien) return klien;

  klien = mqtt.connect(URL_BROKER, {
    username: process.env.MQTT_USERNAME || undefined,
    password: process.env.MQTT_PASSWORD || undefined,
    clientId: `smart-community-backend-${Math.random().toString(16).slice(2, 10)}`,
    // Sesi bersih: server ini tidak pernah berlangganan apa pun, ia hanya
    // menerbitkan. Menyimpan sesi hanya menumpuk state di broker tanpa guna.
    clean: true,
    reconnectPeriod: 5000,
    connectTimeout: 10000,
  });

  klien.on('connect', () => {
    siapPernah = true;
    console.log(`✅ MQTT tersambung ke broker — topik alarm: ${TOPIK_ALARM}`);
  });
  klien.on('error', (e) => console.error('❌ MQTT Error:', e.message));
  klien.on('offline', () => console.warn('⚠️  MQTT offline — perintah alarm akan gagal sampai tersambung lagi'));
  klien.on('reconnect', () => console.log('… MQTT mencoba menyambung ulang'));

  return klien;
}

/** Apakah broker sudah dikonfigurasi sama sekali. */
function terkonfigurasi() {
  return URL_BROKER !== '';
}

/** Apakah sambungan sedang hidup saat ini. */
function tersambung() {
  return !!(klien && klien.connected);
}

/**
 * Menerbitkan perintah alarm, dan MENUNGGU konfirmasi broker.
 *
 * Sengaja menunggu ack, bukan "kirim lalu lupakan". Sebuah tombol darurat yang
 * melaporkan "berhasil" padahal pesannya tidak pernah sampai ke broker adalah
 * kegagalan yang paling buruk di seluruh aplikasi ini — pengguna berhenti
 * mencari cara lain justru ketika alarmnya tidak berbunyi.
 *
 * QoS 1: broker wajib mengonfirmasi penerimaan. QoS 0 boleh hilang diam-diam.
 * `retain` true supaya perangkat yang baru menyala langsung tahu keadaan alarm
 * terakhir, bukan menunggu perintah berikutnya.
 */
function terbitkanPerintahAlarm(perintah, { timeoutMs = 8000 } = {}) {
  const nilai = String(perintah).toUpperCase();
  if (nilai !== PERINTAH.NYALA && nilai !== PERINTAH.MATI) {
    return Promise.reject(new Error(`Perintah alarm tidak dikenal: "${perintah}"`));
  }

  const c = ambilKlien();
  if (!c) {
    return Promise.reject(Object.assign(
      new Error('MQTT_URL belum disetel, jadi perintah alarm tidak bisa diterbitkan.'),
      { kode: 'MQTT_BELUM_DISETEL' }
    ));
  }

  return new Promise((resolve, reject) => {
    let selesai = false;
    const jam = setTimeout(() => {
      if (selesai) return;
      selesai = true;
      reject(Object.assign(
        new Error('Broker MQTT tidak menjawab dalam batas waktu.'),
        { kode: 'MQTT_TIMEOUT' }
      ));
    }, timeoutMs);

    c.publish(TOPIK_ALARM, nilai, { qos: 1, retain: true }, (err) => {
      if (selesai) return;
      selesai = true;
      clearTimeout(jam);
      if (err) {
        reject(Object.assign(err, { kode: 'MQTT_GAGAL_TERBIT' }));
        return;
      }
      console.log(`📡 MQTT → ${TOPIK_ALARM}: ${nilai}`);
      resolve({ topik: TOPIK_ALARM, perintah: nilai });
    });
  });
}

/** Dipanggil saat startup agar sambungan sudah hangat sebelum ada keadaan darurat. */
function initMqtt() {
  if (!terkonfigurasi()) {
    console.warn('\n⚠️  MQTT_URL belum disetel — tombol darurat NONAKTIF sampai variabel ini diisi.\n');
    return null;
  }
  return ambilKlien();
}

module.exports = {
  initMqtt,
  terbitkanPerintahAlarm,
  terkonfigurasi,
  tersambung,
  pernahTersambung: () => siapPernah,
  TOPIK_ALARM,
  PERINTAH,
};
