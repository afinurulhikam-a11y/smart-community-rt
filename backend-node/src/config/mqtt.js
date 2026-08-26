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
/**
 * Pola topik alarm; `{rt}` diganti kode RT saat diterbitkan.
 *
 * Sejak satu pemasangan melayani beberapa RT, satu topik datar berarti tombol
 * darurat di RT mana pun membunyikan SELURUH sirene di RW. Topiknya karena itu
 * dibedakan per RT, dan tiap ESP32 hanya berlangganan topik RT-nya sendiri.
 *
 * JALAN KELUAR yang sengaja disediakan: bila `MQTT_TOPIC_ALARM` disetel TANPA
 * `{rt}`, nilainya dipakai apa adanya dan seluruh RT berbagi satu perangkat.
 * Itu bukan kelalaian melainkan syarat pemasangan bertahap — perangkat yang
 * sudah terpasang di lapangan masih memakai topik lama sampai diflash ulang,
 * dan sirene yang berhenti berbunyi adalah kegagalan terburuk di aplikasi ini.
 * Lebih baik satu perangkat yang tetap berbunyi daripada beberapa yang bisu.
 */
const POLA_TOPIK = (process.env.MQTT_TOPIC_ALARM || 'smart-community/rt/{rt}/alarm/command').trim();
const TOPIK_PER_RT = POLA_TOPIK.includes('{rt}');

/**
 * Topik untuk sebuah RT.
 *
 * Kode RT yang kosong DITOLAK, bukan diganti nilai bawaan: menebak di sini
 * berarti membunyikan sirene di RT yang salah, dan tidak ada cara bagi warga
 * untuk tahu bahwa yang berbunyi bukan peringatan untuk mereka.
 */
function topikAlarm(kodeRt) {
  if (!TOPIK_PER_RT) return POLA_TOPIK;
  const kode = String(kodeRt ?? '').trim();
  if (!kode) {
    throw Object.assign(
      new Error('Kode RT tidak diketahui, jadi perintah alarm tidak bisa dialamatkan.'),
      { kode: 'MQTT_RT_KOSONG' }
    );
  }
  return POLA_TOPIK.replace('{rt}', kode);
}

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
    console.log(`✅ MQTT tersambung ke broker — pola topik alarm: ${POLA_TOPIK}`);
    if (!TOPIK_PER_RT) {
      console.warn('⚠️  MQTT_TOPIC_ALARM disetel tanpa {rt} — SELURUH RT berbagi satu perangkat alarm.');
    }
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
function terbitkanPerintahAlarm(perintah, { kodeRt, timeoutMs = 8000 } = {}) {
  const nilai = String(perintah).toUpperCase();
  if (nilai !== PERINTAH.NYALA && nilai !== PERINTAH.MATI) {
    return Promise.reject(new Error(`Perintah alarm tidak dikenal: "${perintah}"`));
  }

  let topik;
  try {
    topik = topikAlarm(kodeRt);
  } catch (e) {
    return Promise.reject(e);
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

    c.publish(topik, nilai, { qos: 1, retain: true }, (err) => {
      if (selesai) return;
      selesai = true;
      clearTimeout(jam);
      if (err) {
        reject(Object.assign(err, { kode: 'MQTT_GAGAL_TERBIT' }));
        return;
      }
      console.log(`📡 MQTT → ${topik}: ${nilai}`);
      resolve({ topik, perintah: nilai });
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
  topikAlarm,
  POLA_TOPIK,
  TOPIK_PER_RT,
  PERINTAH,
};
