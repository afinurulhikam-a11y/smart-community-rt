# Smart Community RT 🏙️
> **Sistem Informasi Manajemen & Layanan Rukun Tetangga Terintegrasi Berbasis Web, Mobile (Flutter) & IoT**

[![Node.js](https://img.shields.io/badge/Node.js-v18+-green.svg)](https://nodejs.org/)
[![Flutter](https://img.shields.io/badge/Flutter-v3.29+-blue.svg)](https://flutter.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-v15+-blue.svg)](https://www.postgresql.org/)
[![Firebase](https://img.shields.io/badge/Firebase-FCM-orange.svg)](https://firebase.google.com/)
[![License](https://img.shields.io/badge/License-ISC-brightgreen.svg)]()

---

## 📌 Tentang Proyek
**Smart Community RT** adalah platform tata kelola lingkungan digital yang dirancang untuk mendigitalkan seluruh aktivitas administrasi, operasional, keuangan, dan komunikasi antar warga serta pengurus RT secara transparan, akuntabel, dan *real-time*.

Platform ini dibangun dengan arsitektur multi-platform:
* **Frontend:** Flutter Cross-Platform (Responsif untuk Web Desktop, Tablet, dan Mobile Android).
* **Backend:** Node.js Express dengan arsitektur modular (*Layered Architecture*), database PostgreSQL, dan Firebase Admin SDK.
* **Hardware/IoT:** Modul ESP32 & Panic Button fisik terhubung melalui protokol MQTT dan WebSocket untuk deteksi dini situasi darurat warga.

---

## ✨ Fitur Utama Sistem

### 1. 👥 Manajemen Kependudukan
* **Data Warga & Kartu Keluarga (KK):** Pencatatan identitas warga, status keluarga, status kependudukan, e-KTP, dan relasi anggota keluarga dengan validasi Kepala Keluarga tunggal.
* **Statistik & Demografi:** Visualisasi grafik piramida usia, rasio gender, sebaran pekerjaan, pendidikan, dan status domisili.
* **Import & Export Data:** Dukungan impor/ekspor data warga dan KK via Excel (.xlsx) dan pencetakan laporan PDF.

### 2. 💰 Pengelolaan Keuangan & Iuran Warga
* **Master Iuran & Pembacaan Meteran Air:** Pengelolaan iuran periodik RT dan pencatatan meteran air digital mandiri/petugas.
* **Integrasi Pembayaran Digital (Midtrans):** Pembayaran tagihan iuran secara otomatis via QRIS, Virtual Account, dan e-Wallet dengan sinkronisasi status *webhook*.
* **Kas & Buku Kas Digital:** Pencatatan arus kas masuk/keluar, alokasi Biaya Operasional Pengurus (BOP), serta laporan keuangan bulanan transparan.

### 3. 📄 Layanan Mandiri Warga
* **Surat-Menyurat Online:** Permohonan surat pengantar RT (Surat Domisili, Pengantar SKCK, Keterangan Usaha, dll.) dengan penerbitan dokumen bertanda tangan digital dan kode verifikasi QR.
* **Peminjaman Inventaris:** Pengelolaan peminjaman aset barang inventaris RT dengan validasi stok dan riwayat pengembalian.
* **Buku Tamu Elektronik (E-Visitor):** Pencatatan kunjungan tamu warga luar dengan sistem check-in/check-out.

### 4. 🚨 Sistem Tanggap Darurat (*Emergency Alert* & IoT)
* **Panic Button Fisik (IoT ESP32):** Tombol darurat fisik di pos keamanan / lingkungan warga yang memicu sirine dan siaran sinyal darurat via MQTT.
* **Alarm Darurat Realtime & FCM:** Siaran darurat instan ke seluruh ponsel warga melalui *push notification* Firebase Cloud Messaging (FCM) dan WebSocket.

### 5. 🗳️ Partisipasi & Informasi Lingkungan
* **Pengaduan & Aspirasi Warga:** Pelaporan masalah lingkungan dengan lampiran foto, status penanganan, dan tanggapan dua arah.
* **Polling & Voting Warga:** Pemungutan suara digital yang aman dan transparan untuk keputusan bersama warga RT.
* **Agenda & Pengumuman:** Publikasi kegiatan kerja bakti, rapat warga, dan jadwal ronda malam.

### 6. 🔐 Keamanan & Hak Akses Berjenjang (*Role-Based Access Control*)
* Hak akses terisolasi untuk **Ketua RT**, **Sekretaris**, **Bendahara**, **Petugas Keamanan/Admin**, dan **Warga**.
* Fitur Reset Password Mandiri dan Audit Log Aktivitas Sistem untuk mencatat setiap interaksi data penting.

---

## 🏗️ Struktur Direktori Proyek

```text
smart-community-rt/
├── backend-node/               # Layanan Backend API (Express.js & PostgreSQL)
│   ├── database/               # Skema database, migrasi SQL/JS, dan data seeder
│   │   ├── migrations/         # File migrasi skema database bertahap
│   │   ├── seeds/              # Script seeder data master & dummy demo
│   │   └── schema.sql          # DDL skema database PostgreSQL lengkap
│   ├── scripts/                # Script utilitas administratif & audit sistem
│   ├── tests/                  # Test suite pengujian backend (Unit & Integration)
│   ├── src/                    # Source code utama aplikasi backend
│   │   ├── config/             # Konfigurasi database, firebase, midtrans, storage
│   │   ├── controllers/        # Request handlers & alur bisnis
│   │   ├── middleware/         # Auth JWT, permission guard, rate limiter
│   │   ├── routes/             # Definisi endpoint RESTful API
│   │   ├── services/           # Logika layanan (FCM, notification, WhatsApp)
│   │   ├── utils/              # Helper fungsi & validasi Joi
│   │   └── index.js            # Entry point server Express.js
│   ├── package.json
│   └── Dockerfile
│
├── frontend-flutter/           # Aplikasi Klien (Flutter Web & Mobile Android)
│   ├── lib/
│   │   ├── core/               # Konfigurasi tema, konstanta, routing, & responsif
│   │   ├── models/             # Data models (JSON deserialization)
│   │   ├── providers/          # State management (Provider pattern)
│   │   ├── screens/            # Antarmuka Admin & Warga
│   │   ├── widgets/            # Komponen UI modular (TabelResponsif, Dialogs, Cards)
│   │   └── main.dart           # Entry point aplikasi Flutter
│   ├── test/                   # Widget & unit test frontend Flutter
│   └── pubspec.yaml
│
├── iot-firmware/               # Firmware Arduino/C++ untuk modul ESP32 Panic Button
│   └── esp32_alarm/
│
├── docs/                       # Dokumentasi resmi & panduan pengembangan
│   ├── DEVELOPMENT.md          # Panduan workflow developer & standar kode
│   ├── PANDUAN-SIDANG.md       # Panduan demonstrasi sistem untuk sidang
│   ├── DOCKER-PANDUAN.md       # Panduan deployment menggunakan Docker
│   └── RELEASE-ANDROID.md      # Panduan build APK/AAB Android
│
├── data-sample/                # Contoh file spreadsheet Excel untuk pengujian import
├── docker-compose.yml          # Konfigurasi containerisasi Docker
└── README.md
```

---

## 🚀 Panduan Menjalankan Aplikasi Secara Lokal

### Prasyarat:
* **Node.js:** Versi 18.x atau lebih baru
* **PostgreSQL:** Versi 14.x atau lebih baru
* **Flutter SDK:** Versi 3.29.x atau lebih baru

---

### 1. Menjalankan Backend (`backend-node`)

```bash
# 1. Masuk ke direktori backend
cd backend-node

# 2. Salin environment variable
cp .env.example .env
# Sesuaikan DATABASE_URL, JWT_SECRET, FIREBASE_*, MIDTRANS_* pada file .env

# 3. Pasang dependensi
npm install

# 4. Inisialisasi Database & Seeder
npm run db:init
npm run db:seed:demo

# 5. Jalankan backend dalam mode development
npm run dev
```
> Server API akan berjalan di `http://localhost:3001` (atau port yang disetel pada `.env`).

---

### 2. Menjalankan Frontend (`frontend-flutter`)

```bash
# 1. Masuk ke direktori frontend
cd frontend-flutter

# 2. Ambil seluruh dependensi Flutter
flutter pub get

# 3. Jalankan aplikasi pada Chrome (Web) atau Device Android
flutter run -d chrome
```

---

## 🧪 Menjalankan Pengujian (*Automated Testing*)

* **Pengujian Backend:**
  ```bash
  cd backend-node
  npm test
  ```
* **Pengujian Frontend:**
  ```bash
  cd frontend-flutter
  flutter test
  ```

---

## 👨‍💻 Pengembang
* **Afi Nurul Hikam** - *Sistem Informasi Manajemen Smart Community RT*
