/*
 * ============================================================================
 *  Smart Community RT — Alarm Darurat (ESP32)
 * ============================================================================
 *
 *  Alat ini berlangganan satu topik MQTT dan menyalakan buzzer + LED merah
 *  ketika menerima "ON", lalu mematikannya ketika menerima "OFF".
 *
 *  ---------------------------------------------------------------------------
 *  PERUBAHAN BESAR: WebSocket -> MQTT
 *  ---------------------------------------------------------------------------
 *
 *  Versi sebelumnya menyambung ke WebSocket backend dan membaca field `type`
 *  dari pesan JSON. Sekarang alat berlangganan topik MQTT, dan muatannya
 *  bukan lagi JSON melainkan teks polos "ON" / "OFF".
 *
 *  Akibatnya: PERANGKAT YANG MASIH MEMAKAI FIRMWARE LAMA TIDAK AKAN BERBUNYI.
 *  Backend tidak lagi mengirim perintah alarm lewat WebSocket, jadi setiap
 *  ESP32 wajib di-flash ulang dengan berkas ini. Tidak ada masa tumpang tindih
 *  di mana keduanya bekerja.
 *
 *  Yang TIDAK berubah: WebSocket di backend tetap hidup, tetapi tugasnya kini
 *  hanya memunculkan popup darurat di aplikasi pengurus. Alat tidak lagi
 *  terlibat di sana.
 *
 *  ---------------------------------------------------------------------------
 *  Kenapa muatannya teks polos, bukan JSON
 *  ---------------------------------------------------------------------------
 *
 *  Alat ini hanya perlu tahu satu hal: nyala atau mati. Ia tidak membaca nama
 *  pelapor, alamat, maupun koordinat — buzzer tidak membacakan apa pun. Muatan
 *  sekecil "ON" menghapus seluruh kelas kegagalan parsing JSON, dan menghapus
 *  kemungkinan data pribadi warga sampai ke perangkat yang topiknya bisa
 *  didengar siapa saja yang punya kredensial broker.
 *
 *  ---------------------------------------------------------------------------
 *  Pustaka yang dibutuhkan (Arduino IDE -> Library Manager)
 *  ---------------------------------------------------------------------------
 *   - PubSubClient  (Nick O'Leary)   <- MENGGANTIKAN "WebSockets"
 *   - WiFiClientSecure sudah termasuk paket board ESP32
 *
 *  ArduinoJson TIDAK lagi diperlukan.
 *
 *  ---------------------------------------------------------------------------
 *  Isi tiga blok di bawah sebelum flash: WiFi, broker, dan topik.
 * ============================================================================
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

// ============================================================================
// KONFIGURASI — WAJIB DIISI
// ============================================================================
const char* WIFI_SSID     = "NamaWiFi_Anda";
const char* WIFI_PASSWORD = "PasswordWiFi_Anda";

// Broker MQTT. Harus SAMA dengan MQTT_URL di backend-node/.env.
//
// Port 8883 = TLS (dianjurkan). Port 1883 = tanpa enkripsi; pada jaringan
// bersama, siapa pun yang menyadap bisa membaca dan menyuntikkan perintah
// alarm. Pakai 1883 hanya di LAN tertutup saat pengujian.
const char* MQTT_HOST = "broker.contoh.com";
const int   MQTT_PORT = 8883;
const bool  MQTT_PAKAI_TLS = true;

const char* MQTT_USERNAME = "";   // kosongkan bila broker anonim
const char* MQTT_PASSWORD = "";

// Harus SAMA PERSIS dengan MQTT_TOPIC_ALARM di backend.
const char* TOPIK_ALARM = "smart-community/alarm/command";

// Id klien wajib unik per perangkat. Dua alat dengan id sama akan saling
// memutus sambungan bergantian, dan gejalanya adalah alarm yang berbunyi
// putus-putus tanpa sebab yang jelas.
const char* MQTT_CLIENT_ID = "smart-community-esp32-01";

// ============================================================================
// PIN
// ============================================================================
#define BUZZER_PIN    25
#define LED_RED_PIN   26
#define LED_GREEN_PIN 27

// ============================================================================
// STATE
// ============================================================================
WiFiClientSecure clientAman;
WiFiClient       clientPolos;
PubSubClient     mqtt(clientAman);

bool alarmAktif = false;

unsigned long tandaKedip = 0;
unsigned long tandaBip   = 0;
bool ledState  = false;
bool beepState = false;

const unsigned long JEDA_KEDIP = 300;  // ms — LED merah
const unsigned long JEDA_BIP   = 400;  // ms — buzzer hidup/mati

unsigned long tandaSambungUlang = 0;
const unsigned long JEDA_SAMBUNG_ULANG = 5000;

// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);

  matikanAlarm();
  digitalWrite(LED_GREEN_PIN, LOW);

  Serial.println();
  Serial.println("=== Smart Community RT — Alarm (MQTT) ===");

  sambungWifi();

  if (MQTT_PAKAI_TLS) {
    // Tanpa sertifikat CA, sambungan TLS tetap terenkripsi tetapi TIDAK
    // memverifikasi identitas broker. Untuk pemasangan sungguhan, ganti dengan
    // clientAman.setCACert(ca_root) memakai sertifikat broker Anda.
    clientAman.setInsecure();
    mqtt.setClient(clientAman);
  } else {
    mqtt.setClient(clientPolos);
  }

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(pesanMasuk);
  mqtt.setKeepAlive(30);
}

// ============================================================================
void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    digitalWrite(LED_GREEN_PIN, LOW);
    sambungWifi();
  }

  if (!mqtt.connected()) {
    digitalWrite(LED_GREEN_PIN, LOW);
    sambungUlangMqtt();
  } else {
    digitalWrite(LED_GREEN_PIN, HIGH);  // hijau menyala = siap menerima perintah
    mqtt.loop();
  }

  jalankanAlarm();
}

// ============================================================================
void sambungWifi() {
  if (WiFi.status() == WL_CONNECTED) return;

  Serial.print("Menyambung WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long mulai = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - mulai < 20000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("WiFi tersambung. IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi GAGAL — akan dicoba lagi.");
  }
}

// ============================================================================
void sambungUlangMqtt() {
  // Tidak memakai delay(): alarm yang sedang berbunyi harus terus berbunyi
  // selama percobaan sambung ulang. delay() akan membekukan jalankanAlarm()
  // dan buzzer justru diam pada saat paling dibutuhkan.
  if (millis() - tandaSambungUlang < JEDA_SAMBUNG_ULANG) return;
  tandaSambungUlang = millis();

  Serial.print("Menyambung broker MQTT... ");

  bool ok;
  if (strlen(MQTT_USERNAME) > 0) {
    ok = mqtt.connect(MQTT_CLIENT_ID, MQTT_USERNAME, MQTT_PASSWORD);
  } else {
    ok = mqtt.connect(MQTT_CLIENT_ID);
  }

  if (ok) {
    Serial.println("tersambung.");
    // QoS 1: broker mengulang pengiriman sampai alat mengonfirmasi. QoS 0 boleh
    // hilang diam-diam, dan perintah alarm yang hilang diam-diam adalah
    // kegagalan terburuk pada alat ini.
    mqtt.subscribe(TOPIK_ALARM, 1);
    Serial.print("Berlangganan topik: ");
    Serial.println(TOPIK_ALARM);
    // Pesan retained dari broker akan langsung menyusul di sini, sehingga alat
    // yang baru menyala tahu apakah alarm sedang aktif.
  } else {
    Serial.print("gagal, kode=");
    Serial.println(mqtt.state());
  }
}

// ============================================================================
void pesanMasuk(char* topik, byte* muatan, unsigned int panjang) {
  // Muatan MQTT bukan string ber-null. Menyalinnya ke buffer sendiri adalah
  // satu-satunya cara aman membacanya.
  char perintah[16];
  unsigned int n = panjang < sizeof(perintah) - 1 ? panjang : sizeof(perintah) - 1;
  memcpy(perintah, muatan, n);
  perintah[n] = '\0';

  Serial.print("MQTT [");
  Serial.print(topik);
  Serial.print("] -> ");
  Serial.println(perintah);

  if (strcasecmp(perintah, "ON") == 0) {
    nyalakanAlarm();
  } else if (strcasecmp(perintah, "OFF") == 0) {
    matikanAlarm();
  } else {
    // Perintah tak dikenal DIABAIKAN, bukan ditafsirkan. Menebak-nebak di sini
    // berarti sebuah pesan rusak bisa membangunkan satu kampung.
    Serial.println("Perintah tidak dikenal — diabaikan.");
  }
}

// ============================================================================
void nyalakanAlarm() {
  if (alarmAktif) return;   // sudah menyala, jangan mengulang dari awal
  alarmAktif = true;
  tandaKedip = millis();
  tandaBip   = millis();
  Serial.println(">>> ALARM MENYALA");
}

void matikanAlarm() {
  alarmAktif = false;
  ledState   = false;
  beepState  = false;
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_RED_PIN, LOW);
  Serial.println(">>> alarm mati");
}

// ============================================================================
void jalankanAlarm() {
  if (!alarmAktif) return;

  const unsigned long sekarang = millis();

  // LED merah berkedip.
  if (sekarang - tandaKedip >= JEDA_KEDIP) {
    tandaKedip = sekarang;
    ledState = !ledState;
    digitalWrite(LED_RED_PIN, ledState ? HIGH : LOW);
  }

  // Buzzer AKTIF digerakkan on/off, bukan tone(): buzzer aktif punya osilator
  // sendiri dan hanya perlu tegangan.
  //
  // Ditulis tanpa delay() dengan sengaja. Versi ber-delay membuat alat berhenti
  // membaca jaringan selama ratusan milidetik — dan perintah OFF yang tiba pada
  // jeda itu bisa terlewat, sehingga buzzer terus berbunyi setelah pengurus
  // menekan tombol mati.
  if (sekarang - tandaBip >= JEDA_BIP) {
    tandaBip = sekarang;
    beepState = !beepState;
    digitalWrite(BUZZER_PIN, beepState ? HIGH : LOW);
  }
}
