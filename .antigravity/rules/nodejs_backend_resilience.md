---
name: Node.js Backend Resilience
description: Aturan wajib untuk setiap setup Node.js/Express.js, menangani masalah EADDRINUSE dan pemblokiran CORS/Private Network Access pada browser.
---

# Node.js Backend Resilience Rule

Aturan ini harus SELALU diterapkan setiap kali Agen membantu mengonfigurasi, mengedit, atau membuat server backend Node.js (terutama menggunakan Express.js) di lingkungan pengembangan lokal.

## 1. Menerapkan Graceful Shutdown
Setiap kali server HTTP diinisialisasi (`server.listen` atau `app.listen`), Anda **HARUS** menambahkan penangan sinyal (signal handlers) untuk mematikan server secara elegan dan melepaskan port.

### Implementasi Wajib:
```javascript
// Contoh Implementasi Graceful Shutdown
function gracefulShutdown(signal) {
  console.log(`\n[${signal}] Mematikan server secara aman...`);
  server.close(() => {
    console.log('Server berhasil dimatikan. Port telah dibebaskan.');
    process.exit(0);
  });
  
  // Jika dalam 5 detik tidak mati juga, matikan paksa
  setTimeout(() => {
    console.error('Server gagal dimatikan dengan aman, mematikan paksa...');
    process.exit(1);
  }, 5000);
}

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
  gracefulShutdown('uncaughtException');
});
```

## 2. CORS & Private Network Access (PNA)
Browser modern seperti Chrome sering kali memblokir akses ke `localhost` dari klien `localhost` lain jika konfigurasi CORS tidak eksplisit atau tidak mengizinkan PNA.

### Implementasi Wajib:
Anda harus selalu menerapkan dua middleware ini SEBELUM mendefinisikan *routes* Anda:

```javascript
const cors = require('cors');

// 1. Izinkan Chrome Private Network Access
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Private-Network', 'true');
  next();
});

// 2. Konfigurasi CORS eksplisit (jangan gunakan `app.use(cors())` kosong)
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Origin', 'Accept']
}));
```

## 3. Rationale
Menghindari dua *error* membuang-buang waktu yang sering terjadi di Windows:
- **EADDRINUSE (Address already in use):** Terjadi karena terminal *crash* tetapi proses Node.js masih menahan port di *background*.
- **ClientException: Failed to fetch:** Terjadi di *frontend* (misal: Flutter Web) karena *request* ditolak di tingkat koneksi *browser* akibat aturan PNA Chrome atau CORS *preflight* yang tidak lengkap.
