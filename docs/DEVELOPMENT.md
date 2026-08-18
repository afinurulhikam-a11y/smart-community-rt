# Pedoman Pengembangan & Standar Codebase (DEVELOPMENT.md)

Dokumen ini memuat standar arsitektur, konvensi penulisan kode, alur pengujian (*testing workflow*), dan prosedur rilis (*deployment pipeline*) untuk proyek **Smart Community RT**.

---

## 1. Arsitektur & Prinsip Desain

### A. Backend Architecture (Layered Clean Architecture)
Backend dibangun menggunakan Node.js dan Express.js dengan pemisahan tanggung jawab yang ketat (*Separation of Concerns*):

* `src/config/`: Tempat konfigurasi koneksi eksternal (Database pool, Firebase Admin SDK, Payment Gateway Midtrans, dll.). Dilarang menaruh logika bisnis di dalam folder config.
* `src/controllers/`: Menangani HTTP request/response, ekstraksi parameter, dan format data output JSON.
* `src/middleware/`: Validasi JWT, otorisasi peran (*Role Guard*), rate limiting, dan sanitasi input.
* `src/services/`: Logika bisnis murni (misalnya pengiriman notifikasi FCM, kalkulasi tagihan air, dll.).
* `src/utils/`: Fungsi pembantu independen (formatting tanggal, helper mata uang, schema validator Joi).

### B. Frontend Architecture (Flutter Provider Pattern)
Frontend Flutter memisahkan lapisan tampilan (*view layer*) dengan lapisan data/keadaan (*state layer*):

* `lib/core/`: Menyimpan konfigurasi tema, warna dinamis konteks (*dark/light mode*), utilitas responsif, dan klien HTTP dasar.
* `lib/models/`: Representasi objek data dengan serialisasi/deserialisasi JSON yang aman (`fromJson` / `toJson`).
* `lib/providers/`: State management menggunakan `ChangeNotifier` untuk mengelola data reaktif aplikasi dan komunikasi dengan API backend.
* `lib/screens/`: Halaman-halaman antarmuka yang terbagi menjadi modul `admin/`, `warga/`, dan `auth/`.
* `lib/widgets/`: Komponen antarmuka yang dapat digunakan kembali (*reusable widgets*), seperti `TabelResponsif`, dialogs, dan status cards.

---

## 2. Standar Kode & Konvensi Git

### A. Konvensi Pesan Commit (Conventional Commits)
Setiap commit git wajib menggunakan awalan deskriptif standar industri:
* `feat:` Penambahan fitur baru pada sistem.
* `fix:` Perbaikan bug atau galat pada logika/tampilan.
* `refactor:` Restrukturisasi kode tanpa mengubah fungsionalitas eksternal.
* `docs:` Penambahan atau pembaruan dokumentasi.
* `test:` Penambahan atau perbaikan unit test / integration test.
* `chore:` Pembaruan dependensi, konfigurasi build, atau file pemeliharaan.

### B. Konvensi Penamaan File & Direktori
* **Backend:** Menggunakan format `kebab-case` atau `camelCase` (contoh: `warga.controller.js`, `fcm.service.js`).
* **Frontend Flutter:** Menggunakan format `snake_case` (contoh: `tabel_responsif.dart`, `data_warga_screen.dart`).

---

## 3. Alur Pengujian (*Testing Workflow*)

Sebelum melakukan commit atau rilis ke branch utama, seluruh pengujian otomatis wajib dijalankan:

### Backend Testing:
```bash
cd backend-node
npm run lint         # Memeriksa kepatuhan linter ESLint
npm run test:guard   # Memeriksa integritas database guard & skema
npm test             # Menjalankan seluruh test suite backend
```

### Frontend Testing:
```bash
cd frontend-flutter
dart analyze         # Memastikan tidak ada issue atau warning Dart
flutter test         # Menjalankan seluruh widget & unit test Flutter
```

---

## 4. Pipeline CI/CD & Deployment Otomatis

Proyek ini telah terhubung dengan alur otomatisasi *Continuous Integration / Continuous Deployment* (CI/CD):
1. **Frontend (Vercel):** Setiap push ke branch `master` secara otomatis memicu build Flutter Web dan mendeploy ke CDN Vercel.
2. **Backend (Railway):** Setiap push ke branch `master` secara otomatis memicu container build Docker dan mendeploy layanan API ke Railway Cloud.

---

## 5. Manajemen Kredensial & Lingkungan

* **Dilarang keras** menyimpan kunci rahasia (*secret keys*), token API, atau URL database secara hardcode di dalam repositori Git.
* Seluruh kredensial dikonfigurasi melalui *Environment Variables* (`.env` lokal, Railway Variables, atau Vercel Environment).
