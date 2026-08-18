# 🐳 Panduan Implementasi Docker & Deployment (Smart Community RT)

Projek ini telah dilengkapi dengan konfigurasi **Docker & Docker Compose** berstandar industri (*Production-Ready*) untuk mempermudah pengujian, eksekusi lokal, dan deployment ke cloud.

---

## 📁 Struktur File Docker

```
smart-community-rt/
├── docker-compose.yml             # Mengatur 3 service sekaligus (DB, Backend, Frontend)
├── backend-node/
│   ├── Dockerfile                 # Konfigurasi container Node.js + Express
│   └── .dockerignore
└── frontend-flutter/
    ├── Dockerfile                 # Multi-stage build Flutter Web + Nginx Web Server
    └── .dockerignore
```

---

## 🚀 Cara Menjalankan Aplikasi Menggunakan Docker

Jika di komputer sudah terpasang **Docker Desktop**:

### 1. Menjalankan Seluruh Sistem (Database, Backend, & Frontend Web)
Buka terminal di direktori utama projek (`smart-community-rt`) lalu ketik:
```bash
docker compose up -d --build
```

Sistem akan otomatis:
- Menyalakan Database PostgreSQL di port `5432`
- Menyalakan Backend REST API Node.js di port `3001`
- Menyalakan Frontend Flutter Web App (`frontend_webapp`) di port `8080`

Akses di Browser: **`http://localhost:8080`**

### 2. Menghentikan Docker Container
```bash
docker compose down
```

---

## ☁️ Petunjuk Deployment Cloud Gratis / Terjangkau

| Komponen | Platform Cloud Disarankan | Cara Deployment |
| :--- | :--- | :--- |
| **Database PostgreSQL** | Supabase / Neon.tech / Railway | Buat database baru & ambil string koneksinya |
| **Backend Node.js** | Railway / Render | Connect repositori GitHub ➔ Railway akan otomatis mendeteksi `backend-node/Dockerfile` |
| **Frontend Web** | Vercel / Netlify / Railway | Connect repositori GitHub ➔ Deploy folder `frontend-flutter` |

---

## 🎓 Catatan Tambahan untuk Laporan & Sidang Skripsi

Dalam naskah skripsi (Bab III / Bab IV Metodologi & Implementasi), Anda dapat mencantumkan:
- **Teknologi Containerization**: Menggunakan Docker & Docker Compose untuk konsistensi lingkungan pengembangan (*Development*) dan penyebaran (*Deployment*).
- **Arsitektur Multi-Service**: Terbagi menjadi 3 Container independen (Database Container, API Server Container, dan Web Server Container) yang saling berkomunikasi melalui *Docker Virtual Network*.
