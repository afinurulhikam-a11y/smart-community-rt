#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <time.h>

// ============================================================
//  Smart Community RT - Alarm ESP32
// ============================================================
//
//  Berlangganan perintah alarm lewat MQTT dan menggerakkan relay sirene
//  beserta dua LED penanda.
//
//  ------------------------------------------------------------
//  Arti kedua LED
//  ------------------------------------------------------------
//
//    LED 2  = SIAGA. Menyala terus saat keadaan aman.
//    LED 1  = ALARM. Berkedip saat sirene menyala.
//
//  Keduanya TIDAK PERNAH menyala bersamaan, dan itu disengaja: satu lampu
//  padam adalah tanda yang sama kuatnya dengan satu lampu menyala. Kalau
//  keduanya menyala saat alarm aktif, orang harus memperhatikan lampu mana
//  yang berkedip untuk tahu keadaannya — dari kejauhan, atau sekilas lewat,
//  itu tidak terbaca.
//
//  Dengan pembagian ini keadaan alat terbaca dari satu pandangan:
//
//    LED 2 menyala tenang        -> aman
//    LED 1 berkedip, LED 2 padam -> alarm menyala
//    keduanya padam              -> alat mati atau belum siap
//
//  Keadaan ketiga itu penting: sebelumnya "aman" dan "alat mati" sama-sama
//  ditandai kedua LED padam, sehingga alat yang mati diam-diam terlihat persis
//  seperti alat yang sedang berjaga.
// ============================================================


// ============================================================
//  KREDENSIAL SENGAJA DIKOSONGKAN
// ============================================================
//
//  Repositori ini PUBLIK. Nilai asli WiFi dan broker TIDAK ditulis di sini
//  karena riwayat git bersifat permanen: sekali ter-push, sandi itu terbit
//  selamanya walau barisnya dihapus di commit berikutnya.
//
//  Kredensial broker adalah yang paling berbahaya. Siapa pun yang memilikinya
//  bisa menyambung langsung ke broker dan menerbitkan "ON" sendiri - melewati
//  PIN darurat, melewati RBAC, dan tanpa meninggalkan satu baris pun di
//  activity_logs. Seluruh penjagaan di backend menjadi tidak berarti.
//
//  Isi kelima nilai di bawah pada salinan LOKAL sebelum flash, dan jangan
//  meng-commit salinan itu. Pola yang sama dipakai backend-node/.env.example.
// ============================================================

// ============================================================
// WiFi
// ============================================================
const char* WIFI_SSID = "GANTI_NAMA_WIFI";
const char* WIFI_PASSWORD = "GANTI_PASSWORD_WIFI";

// ============================================================
// MQTT / EMQX Cloud
// ============================================================
const char* MQTT_HOST = "GANTI_HOST_BROKER";
const uint16_t MQTT_PORT = 8883;

const char* MQTT_USER = "GANTI_USER_BROKER";
const char* MQTT_PASSWORD = "GANTI_PASSWORD_BROKER";

// ============================================================
// MQTT Topics
// ============================================================
const char* TOPIC_COMMAND = "smart-community/alarm/command";
const char* TOPIC_STATUS  = "smart-community/alarm/status";

// ============================================================
// GPIO
// ============================================================
// Sesuaikan dengan wiring rangkaian kamu.
constexpr uint8_t RELAY_PIN = 25;
constexpr uint8_t LED1_PIN  = 26;  // ALARM  - berkedip saat sirene menyala
constexpr uint8_t LED2_PIN  = 27;  // SIAGA  - menyala saat keadaan aman

// Relay module ACTIVE LOW:
// LOW  = relay ON
// HIGH = relay OFF
constexpr uint8_t RELAY_ON  = LOW;
constexpr uint8_t RELAY_OFF = HIGH;

// Jeda kedip LED alarm.
//
// 300 ms terbaca sebagai "darurat" tanpa membuat mata lelah. Di bawah ~150 ms
// kedipannya mulai terlihat seperti lampu rusak, bukan peringatan.
constexpr unsigned long BLINK_INTERVAL = 300;

// ============================================================
// State
// ============================================================
bool alarmActive = false;

// Keadaan kedip LED alarm. Dikelola di loop(), bukan dengan delay(), supaya
// alat tetap membaca jaringan selama LED berkedip - lihat catatan di
// blinkAlarmLed().
bool led1State = false;
unsigned long lastBlink = 0;

// ============================================================
// Network
// ============================================================
WiFiClientSecure espClient;
PubSubClient mqtt(espClient);

// ============================================================
// NTP
// ============================================================
void syncTime() {
  Serial.println("[NTP] Synchronizing time...");

  configTime(
    0,
    0,
    "pool.ntp.org",
    "time.nist.gov",
    "time.google.com"
  );

  struct tm timeinfo;

  for (int i = 0; i < 20; i++) {
    if (getLocalTime(&timeinfo, 1000)) {
      Serial.println("[NTP] Time synchronized");

      Serial.printf(
        "[NTP] %04d-%02d-%02d %02d:%02d:%02d\n",
        timeinfo.tm_year + 1900,
        timeinfo.tm_mon + 1,
        timeinfo.tm_mday,
        timeinfo.tm_hour,
        timeinfo.tm_min,
        timeinfo.tm_sec
      );

      return;
    }

    Serial.print(".");
  }

  Serial.println();
  Serial.println("[NTP] FAILED");
}

// ============================================================
// LED Siaga
// ============================================================
// Dipakai saat boot dan setiap kali alarm mati, supaya "aman" selalu ditandai
// hal yang sama di seluruh berkas ini.
void setIdleLeds() {
  digitalWrite(LED1_PIN, LOW);   // alarm padam
  digitalWrite(LED2_PIN, HIGH);  // siaga menyala
  led1State = false;
}

// ============================================================
// Alarm Control
// ============================================================
void setAlarm(bool active) {
  alarmActive = active;

  if (active) {
    // Alarm ON
    digitalWrite(RELAY_PIN, RELAY_ON);

    // LED siaga DIPADAMKAN. Ia menandakan "aman", dan keadaan sekarang
    // bukan aman.
    digitalWrite(LED2_PIN, LOW);

    // Kedip dimulai dari padam lalu langsung dibalik oleh loop().
    // lastBlink = 0 membuat kedipan pertama terjadi seketika, bukan setelah
    // menunggu satu interval - pada alarm, jeda 300 ms di awal terasa seperti
    // alat yang tidak merespons.
    led1State = false;
    digitalWrite(LED1_PIN, LOW);
    lastBlink = 0;

    if (mqtt.connected()) {
      mqtt.publish(TOPIC_STATUS, "ON", true);
    }

    Serial.println("[ALARM] ON  - LED1 berkedip, LED2 padam");
  } else {
    // Alarm OFF
    digitalWrite(RELAY_PIN, RELAY_OFF);

    // Kembali ke tanda siaga: alarm padam, siaga menyala.
    setIdleLeds();

    if (mqtt.connected()) {
      mqtt.publish(TOPIC_STATUS, "OFF", true);
    }

    Serial.println("[ALARM] OFF - LED1 padam, LED2 menyala");
  }
}

// ============================================================
// Kedip LED alarm
// ============================================================
// Ditulis TANPA delay() dengan sengaja.
//
// Versi ber-delay membuat alat berhenti membaca jaringan selama ratusan
// milidetik pada setiap kedipan. Perintah OFF yang tiba pada jeda itu bisa
// terlewat, dan gejalanya adalah sirene yang terus berbunyi setelah pengurus
// menekan tombol mati - kegagalan yang jauh lebih terasa daripada LED yang
// berkedip tidak rapi.
void blinkAlarmLed() {
  if (!alarmActive) {
    return;
  }

  const unsigned long now = millis();

  if (now - lastBlink >= BLINK_INTERVAL) {
    lastBlink = now;
    led1State = !led1State;
    digitalWrite(LED1_PIN, led1State ? HIGH : LOW);
  }
}

// ============================================================
// MQTT Callback
// ============================================================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message;

  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }

  message.trim();
  message.toUpperCase();

  Serial.println();
  Serial.println("[MQTT] Message received");

  Serial.print("[MQTT] Topic   : ");
  Serial.println(topic);

  Serial.print("[MQTT] Payload : ");
  Serial.println(message);

  // Hanya proses topic command
  if (String(topic) != TOPIC_COMMAND) {
    Serial.println("[MQTT] Topic ignored");
    return;
  }

  // Alarm ON
  if (
    message == "ON" ||
    message == "ALARM_ON" ||
    message == "TEST"
  ) {
    setAlarm(true);
  }

  // Alarm OFF
  else if (
    message == "OFF" ||
    message == "ALARM_OFF"
  ) {
    setAlarm(false);
  }

  // Command tidak dikenal DIABAIKAN, bukan ditebak. Menebak di sini berarti
  // satu pesan rusak bisa membangunkan satu kampung.
  else {
    Serial.print("[MQTT] Unknown command: ");
    Serial.println(message);
  }
}

// ============================================================
// WiFi Connection
// ============================================================
void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  Serial.println();
  Serial.print("[WiFi] Connecting to ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("[WiFi] Connected");

  Serial.print("[WiFi] IP: ");
  Serial.println(WiFi.localIP());

  Serial.print("[WiFi] RSSI: ");
  Serial.print(WiFi.RSSI());
  Serial.println(" dBm");
}

// ============================================================
// MQTT Connection
// ============================================================
void connectMQTT() {
  while (!mqtt.connected()) {
    Serial.println();
    Serial.print("[MQTT] Connecting to ");
    Serial.print(MQTT_HOST);
    Serial.print(":");
    Serial.println(MQTT_PORT);

    String clientId =
      "ESP32-ALARM-" +
      String((uint32_t)ESP.getEfuseMac(), HEX);

    bool connected = false;

    if (strlen(MQTT_USER) > 0) {
      connected = mqtt.connect(
        clientId.c_str(),
        MQTT_USER,
        MQTT_PASSWORD
      );
    } else {
      connected = mqtt.connect(clientId.c_str());
    }

    if (connected) {
      Serial.println("[MQTT] Connected");

      bool subscribed = mqtt.subscribe(TOPIC_COMMAND);

      Serial.print("[MQTT] Subscribe: ");
      Serial.println(subscribed ? "OK" : "FAILED");

      Serial.print("[MQTT] Topic: ");
      Serial.println(TOPIC_COMMAND);

      // Publish current alarm state
      mqtt.publish(
        TOPIC_STATUS,
        alarmActive ? "ON" : "OFF",
        true
      );
    } else {
      Serial.print("[MQTT] Connection failed, state=");
      Serial.println(mqtt.state());

      // Sirene TIDAK dipadamkan di sini. Kalau alarm sedang menyala dan
      // jaringan terputus, relay harus tetap menahan sirene - memadamkannya
      // karena WiFi bermasalah berarti alarm mati justru saat orang paling
      // membutuhkannya.
      //
      // Kedipan LED memang berhenti selama menunggu di sini, karena loop()
      // tidak berjalan. Itu kosmetik; yang menentukan adalah relay tetap ON.
      delay(3000);
    }
  }
}

// ============================================================
// Setup
// ============================================================
void setup() {
  Serial.begin(115200);

  delay(500);

  Serial.println();
  Serial.println("========================================");
  Serial.println(" Smart Community RT - Alarm ESP32");
  Serial.println("========================================");

  // ----------------------------------------------------------
  // GPIO
  // ----------------------------------------------------------
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(LED1_PIN, OUTPUT);
  pinMode(LED2_PIN, OUTPUT);

  // Kondisi AMAN saat boot
  // Active LOW relay -> HIGH = OFF
  digitalWrite(RELAY_PIN, RELAY_OFF);
  setIdleLeds();

  alarmActive = false;

  Serial.println("[BOOT] Relay : OFF");
  Serial.println("[BOOT] LED 1 : OFF (alarm)");
  Serial.println("[BOOT] LED 2 : ON  (siaga)");
  Serial.println("[BOOT] Alarm : OFF");

  // ----------------------------------------------------------
  // WiFi
  // ----------------------------------------------------------
  connectWiFi();

  // ----------------------------------------------------------
  // NTP
  // ----------------------------------------------------------
  syncTime();

  // ----------------------------------------------------------
  // TLS
  // ----------------------------------------------------------
  // SEMENTARA untuk testing.
  // Jangan gunakan setInsecure() untuk deployment final.
  espClient.setInsecure();

  // ----------------------------------------------------------
  // MQTT
  // ----------------------------------------------------------
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(256);

  connectMQTT();

  // Pastikan output tetap pada keadaan siaga setelah koneksi MQTT.
  //
  // Dijaga dengan `if (!alarmActive)`: broker mengirim pesan retained segera
  // setelah subscribe, jadi alat yang menyala saat alarm sedang aktif bisa
  // SUDAH menerima "ON" sebelum baris ini dijalankan. Memaksa siaga tanpa
  // pemeriksaan itu akan memadamkan alarm yang seharusnya berbunyi.
  if (!alarmActive) {
    digitalWrite(RELAY_PIN, RELAY_OFF);
    setIdleLeds();
  }

  Serial.println();
  Serial.println("[SYSTEM] Ready");
  Serial.println("[SYSTEM] Alarm akan tetap ON sampai menerima OFF");
}

// ============================================================
// Loop
// ============================================================
void loop() {
  // ----------------------------------------------------------
  // WiFi
  // ----------------------------------------------------------
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WiFi] Disconnected");
    connectWiFi();
    syncTime();
  }

  // ----------------------------------------------------------
  // MQTT
  // ----------------------------------------------------------
  if (!mqtt.connected()) {
    Serial.println("[MQTT] Disconnected");
    connectMQTT();
  }

  mqtt.loop();

  // ----------------------------------------------------------
  // LED alarm
  // ----------------------------------------------------------
  blinkAlarmLed();

  // ----------------------------------------------------------
  // Tidak ada auto-off.
  //
  // Alarm hanya mati jika:
  // 1. menerima command OFF
  // 2. ESP32 direstart / kehilangan daya
  // ----------------------------------------------------------

  delay(10);
}
