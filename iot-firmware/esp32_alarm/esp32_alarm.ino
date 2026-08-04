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
 * Wiring:
 *  - Buzzer   → GPIO 25 (atau sesuaikan)
 *  - LED Merah → GPIO 26 (atau sesuaikan)
 *  - LED Hijau → GPIO 27 (indikator koneksi)
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

// IP Backend server (ganti dengan IP komputer yang menjalankan backend)
const char* WS_HOST = "192.168.1.100";
const int   WS_PORT = 3000;
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

  // Connect WebSocket
  webSocket.begin(WS_HOST, WS_PORT, WS_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);  // Auto reconnect setiap 5 detik

  Serial.println("✅ Setup selesai. Menunggu sinyal alarm...");
}

// ========================
// MAIN LOOP
// ========================
void loop() {
  webSocket.loop();

  // Jika alarm aktif → LED merah berkedip + buzzer bunyi
  if (alarmActive) {
    unsigned long currentTime = millis();

    // LED berkedip setiap 300ms
    if (currentTime - lastBlinkTime >= 300) {
      lastBlinkTime = currentTime;
      ledState = !ledState;
      digitalWrite(LED_RED_PIN, ledState ? HIGH : LOW);
    }

    // Buzzer bunyi (tone pattern)
    tone(BUZZER_PIN, 2000, 200);  // 2kHz, 200ms
    delay(250);
    tone(BUZZER_PIN, 1500, 200);  // 1.5kHz, 200ms
    delay(250);
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
  digitalWrite(LED_RED_PIN, HIGH);
  Serial.println("🔴 Buzzer & LED AKTIF");
}

void deactivateAlarm() {
  alarmActive = false;
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_RED_PIN, LOW);
  noTone(BUZZER_PIN);
  ledState = false;
  Serial.println("🟢 Buzzer & LED MATI");
}
