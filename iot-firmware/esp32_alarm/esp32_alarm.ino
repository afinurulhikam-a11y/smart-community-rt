/**
 * ============================================================
 * ESP32 Alarm Firmware
 * Smart Community Management Platform
 * ============================================================
 * 
 * Fungsi:
 *  - Konek ke WiFi
 *  - Konek ke WebSocket server backend
 *  - Mendengarkan pesan ALARM_ON / ALARM_OFF
 *  - Menyalakan/mematikan Buzzer & LED
 * 
 * Wiring (DevKit V1 30 pin — keempatnya di deretan KIRI, USB menghadap bawah):
 *  - GPIO 25 (kiri ke-8) → Buzzer AKTIF (+)   ·  buzzer (−) → GND
 *  - GPIO 26 (kiri ke-7) → resistor 220 Ω → LED merah  (penanda alarm)
 *  - GPIO 27 (kiri ke-6) → resistor 220 Ω → LED hijau  (penanda koneksi)
 *  - GND     (kiri ke-2) → jalur ground bersama
 *
 * Buzzernya harus AKTIF, bukan pasif: firmware ini menghidup-matikan pin
 * (digitalWrite), tidak membangkitkan nada. Buzzer pasif hanya akan berdecit.
 *
 * Library yang dibutuhkan:
 *  - WiFi.h (built-in ESP32)
 *  - WebSocketsClient (install: "WebSockets" by Markus Sattler)
 *  - ArduinoJson (install: "ArduinoJson" by Benoit Blanchon)
 * ============================================================
 */

#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>

// ========================
// KONFIGURASI - Sesuaikan!
// ========================
const char* WIFI_SSID     = "NamaWiFi_Anda";
const char* WIFI_PASSWORD = "PasswordWiFi_Anda";

// Alamat backend di Railway.
//
// Ditulis TANPA "https://" — pustaka WebSockets hanya menerima nama host.
//
// Port 443, bukan 3001. Angka 3001 itu port INTERNAL kontainer dan tidak
// pernah dibuka ke publik: Railway menaruh proxy di depannya, mengakhiri TLS
// di sana, lalu meneruskan ke kontainer. Dari luar yang ada hanya 443.
const char* WS_HOST = "smart-community-rt-production.up.railway.app";
const int   WS_PORT = 443;
const char* WS_PATH = "/";

// ========================
// PIN DEFINITIONS
// ========================
#define BUZZER_PIN    25
#define LED_RED_PIN   26
#define LED_GREEN_PIN 27

// ========================
// GLOBAL VARIABLES
// ========================
WebSocketsClient webSocket;
bool alarmActive = false;
unsigned long lastBlinkTime = 0;
bool ledState = false;

// Pola bunyi buzzer, dikelola dengan millis() seperti kedip LED.
unsigned long lastBeepTime = 0;
bool beepState = false;

const unsigned long JEDA_KEDIP = 300;  // ms — LED merah
const unsigned long JEDA_BIP   = 400;  // ms — buzzer hidup/mati

// ========================
// SETUP
// ========================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("╔═══════════════════════════════════════╗");
  Serial.println("║  ESP32 Alarm - Smart Community RT     ║");
  Serial.println("╚═══════════════════════════════════════╝");

  // Setup pins
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);

  // Initial state: semua OFF
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_RED_PIN, LOW);
  digitalWrite(LED_GREEN_PIN, LOW);

  // Connect WiFi
  connectWiFi();

  // beginSSL, BUKAN begin.
  //
  // `begin()` membuka WebSocket polos (ws://). Railway sama sekali tidak
  // melayani itu — yang ada hanya wss:// di port 443. Dengan `begin()`
  // sambungannya ditolak tanpa pesan galat yang menunjuk sebabnya; perangkatnya
  // hanya diam seolah tidak ada apa-apa.
  //
  // Tanpa fingerprint, pustaka ini memakai setInsecure() di ESP32: lalu lintasnya
  // tetap terenkripsi, tetapi sertifikat server tidak diverifikasi. Cukup untuk
  // perangkat di jaringan sendiri; bukan yang saya sarankan bila alat ini kelak
  // dipasang di jaringan publik.
  webSocket.beginSSL(WS_HOST, WS_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);  // Auto reconnect setiap 5 detik

  Serial.println("✅ Setup selesai. Menunggu sinyal alarm...");
}

// ========================
// MAIN LOOP
// ========================
void loop() {
  // Satu-satunya yang benar-benar membaca data masuk dari jaringan. Harus
  // dipanggil sesering mungkin — dan tidak boleh ada delay() di bawahnya.
  webSocket.loop();

  if (!alarmActive) return;

  const unsigned long sekarang = millis();

  // LED merah berkedip.
  if (sekarang - lastBlinkTime >= JEDA_KEDIP) {
    lastBlinkTime = sekarang;
    ledState = !ledState;
    digitalWrite(LED_RED_PIN, ledState ? HIGH : LOW);
  }

  // Buzzer AKTIF cukup dihidup-matikan; ia punya osilator sendiri dan tidak
  // mengenal nada, jadi tone() tidak berlaku di sini.
  //
  // Dulu blok ini memakai tone() + dua delay(250). Selama 500 ms itu
  // webSocket.loop() di atas tidak pernah jalan, sehingga ALARM_OFF menunggu
  // di antrean sampai setengah detik — dan urusan keepalive pustaka ikut
  // tertahan, yang di atas TLS memperbesar peluang sambungan dianggap mati.
  if (sekarang - lastBeepTime >= JEDA_BIP) {
    lastBeepTime = sekarang;
    beepState = !beepState;
    digitalWrite(BUZZER_PIN, beepState ? HIGH : LOW);
  }
}

// ========================
// WIFI CONNECTION
// ========================
void connectWiFi() {
  Serial.print("📡 Menghubungkan ke WiFi: ");
  Serial.println(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("✅ WiFi terhubung! IP: ");
    Serial.println(WiFi.localIP());
    digitalWrite(LED_GREEN_PIN, HIGH);  // LED hijau ON = connected
  } else {
    Serial.println();
    Serial.println("❌ Gagal terhubung ke WiFi. Restart ESP32...");
    delay(3000);
    ESP.restart();
  }
}

// ========================
// WEBSOCKET EVENT HANDLER
// ========================
void webSocketEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      Serial.println("❌ WebSocket terputus");
      digitalWrite(LED_GREEN_PIN, LOW);
      break;

    case WStype_CONNECTED:
      Serial.println("✅ WebSocket terhubung ke backend");
      digitalWrite(LED_GREEN_PIN, HIGH);
      break;

    case WStype_TEXT: {
      Serial.print("📨 Pesan diterima: ");
      Serial.println((char*)payload);

      // Parse JSON
      JsonDocument doc;
      DeserializationError error = deserializeJson(doc, payload, length);

      if (error) {
        Serial.print("⚠️ JSON parse error: ");
        Serial.println(error.c_str());
        return;
      }

      const char* messageType = doc["type"];

      if (messageType == NULL) {
        Serial.println("⚠️ Tidak ada field 'type' dalam pesan");
        return;
      }

      // ========================
      // HANDLE ALARM_ON
      // ========================
      if (strcmp(messageType, "ALARM_ON") == 0) {
        Serial.println("🚨 === ALARM AKTIF! ===");

        const char* nama   = doc["nama"]   | "Tidak diketahui";
        const char* alamat = doc["alamat"]  | "-";
        const char* pesan  = doc["message"] | "DARURAT!";

        Serial.print("   Dari   : "); Serial.println(nama);
        Serial.print("   Alamat : "); Serial.println(alamat);
        Serial.print("   Pesan  : "); Serial.println(pesan);

        activateAlarm();
      }

      // ========================
      // HANDLE ALARM_OFF
      // ========================
      else if (strcmp(messageType, "ALARM_OFF") == 0) {
        Serial.println("✅ === ALARM DIMATIKAN ===");
        deactivateAlarm();
      }

      // ========================
      // HANDLE CONNECTED (welcome message)
      // ========================
      else if (strcmp(messageType, "CONNECTED") == 0) {
        Serial.println("📡 Terhubung ke Smart Community RT Server");
      }

      break;
    }

    case WStype_ERROR:
      Serial.println("⚠️ WebSocket error");
      break;

    default:
      break;
  }
}

// ========================
// ALARM CONTROL
// ========================
void activateAlarm() {
  alarmActive = true;

  // Pewaktu di-nol-kan supaya bip dan kedip dimulai dari awal, bukan melanjutkan
  // sisa hitungan alarm sebelumnya.
  lastBlinkTime = millis();
  lastBeepTime  = millis();

  ledState  = true;
  beepState = true;
  digitalWrite(LED_RED_PIN, HIGH);
  digitalWrite(BUZZER_PIN, HIGH);

  Serial.println("🔴 Buzzer & LED AKTIF");
}

void deactivateAlarm() {
  alarmActive = false;
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_RED_PIN, LOW);
  ledState  = false;
  beepState = false;
  Serial.println("🟢 Buzzer & LED MATI");
}
