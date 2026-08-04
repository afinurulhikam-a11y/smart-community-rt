# Panduan Menjalankan untuk Sidang

Urut dari nol. Setiap langkah punya **cara memastikan berhasil** — jangan lanjut sebelum tandanya muncul, karena kegagalan di lapisan bawah selalu menyamar sebagai kegagalan di lapisan atas.

---

## Bagian 0 — Pilih dulu: LAN atau ngrok

Ini keputusan pertama dan menentukan sisanya.

| | **LAN / Wi-Fi** (disarankan) | **ngrok** |
|---|---|---|
| Butuh internet | Tidak | Ya |
| Alamat berubah tiap restart | Tidak | **Ya** |
| Export Excel/PDF | Lancar | Perlu satu langkah tambahan |
| Webhook Midtrans otomatis | Tidak jalan | Jalan |
| Risiko saat sidang | Rendah | Sedang |

**Pakai LAN.** Satu-satunya yang hilang adalah pembaruan status tagihan otomatis dari Midtrans — dan itu bisa Anda tunjukkan lewat rekaman layar, atau dengan menekan tombol muat ulang setelah membayar.

Kalau penguji minta melihat pembayaran online sungguhan, siapkan ngrok sebagai **cadangan**, bukan sebagai jalur utama.

---

## Bagian 1 — Persiapan H-1 (cukup sekali)

### 1.1 Buka firewall untuk port 3001

Backend sudah mendengarkan di `0.0.0.0`, tetapi Windows memblokir sambungan masuk dari Wi-Fi secara bawaan. **Ini penyebab paling sering "aplikasi di HP tidak konek padahal backend jalan".**

Buka PowerShell **sebagai Administrator**, lalu:

```powershell
New-NetFirewallRule -DisplayName "Smart Community RT backend" -Direction Inbound -Protocol TCP -LocalPort 3001 -Action Allow -Profile Private
```

**Cek berhasil:**
```powershell
Get-NetFirewallRule -DisplayName "Smart Community RT backend"
```
Harus muncul satu baris, `Enabled: True`.

### 1.2 Catat IP laptop Anda

```powershell
(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL' -and $_.IPAddress -notmatch '^169\.254' }).IPAddress
```

Saat panduan ini ditulis hasilnya **`192.168.1.115`**. **Angka ini berubah** setiap kali laptop pindah jaringan Wi-Fi — periksa lagi di lokasi sidang, jangan mengandalkan catatan lama.

> Nilai bawaan di `api_constants.dart` (`192.168.50.85`) sudah basi. Jangan diandalkan; selalu pakai `--dart-define`.

### 1.3 Pastikan database siap

Cukup sekali, dan **hanya jika database belum ada atau ingin mulai bersih**:

```bash
cd backend-node
node init-db.js        # menghapus lalu membuat ulang database
node seed-master.js    # menu, izin, tabel master, akun admin
node seed-demo.js      # OPSIONAL: 1 KK + 3 anggota + 3 tagihan untuk demo
```

> `init-db.js` **menghapus seluruh data**. Jangan dijalankan di hari-H kalau data demo Anda sudah tertata.

### 1.4 Siapkan data demo secukupnya

Sidang akan terlihat kosong kalau tabelnya kosong. Minimal isi:
- 1–2 kartu keluarga di **Data Warga**
- 1 jenis iuran + terbitkan tagihan 1 bulan di **Iuran Warga**
- 2–3 transaksi di **Kas RT**
- 1 barang + 1 peminjaman di **Inventaris**

### 1.5 Jalankan audit kesehatan

Dengan backend hidup:

```bash
cd backend-node
node periksa-kesehatan.js
```

Hanya membaca, aman terhadap data asli. Harus berakhir dengan **`Semuanya sehat.`** Kalau ada baris `[ MASALAH ]`, perbaiki sebelum hari-H — audit ini memeriksa keutuhan data uang dan kesehatan endpoint untuk kelima peran.

### 1.6 Uji coba penuh sehari sebelumnya

Jalankan Bagian 2 dari awal sampai akhir, di jaringan yang sama dengan yang akan dipakai. Kalau bisa, di ruangan yang sama.

---

## Bagian 2 — Langkah hari-H

### Langkah 1 — Nyalakan PostgreSQL

Pastikan servis PostgreSQL berjalan (lewat pgAdmin, Services, atau Laragon).

**Cek berhasil:**
```bash
cd backend-node
node -e "require('dotenv').config();require('./src/config/database').testConnection()"
```
Harus muncul `✅ Terhubung ke PostgreSQL — <waktu>`.

> `require('dotenv').config()` di depan itu wajib: tanpa itu kata sandi database
> tidak terbaca dan galatnya berbunyi *"client password must be a string"* —
> terdengar seperti masalah kode, padahal cuma berkas `.env` yang belum dimuat.

### Langkah 2 — Jalankan backend

```bash
cd backend-node
npm start
```

Biarkan jendela ini **terbuka selama sidang**. Menutupnya mematikan backend.

**Cek berhasil** — dari browser laptop:
```
http://localhost:3001/api/health
```
Harus muncul JSON `"Backend API is running 🚀"`.

**Cek dari HP** (kalau akan demo di Android) — buka di browser HP:
```
http://192.168.1.115:3001/api/health
```
Ganti IP-nya sesuai hasil langkah 1.2. **Kalau ini gagal, jangan buang waktu men-debug aplikasinya** — masalahnya di jaringan atau firewall, bukan di aplikasi.

### Langkah 3 — Jalankan klien

Pilih salah satu, atau keduanya.

#### 3a. Versi web (React)

```bash
cd frontend-web
npm run dev
```

Buka `http://localhost:5173`.

Kalau backend **bukan** di laptop yang sama, buat berkas `frontend-web/.env.local`:
```
VITE_API_HOST=192.168.1.115
```
lalu jalankan ulang `npm run dev`.

#### 3b. Versi web (Flutter)

```bash
cd frontend-flutter
flutter run -d chrome
```

#### 3c. Versi Android — HP terhubung kabel

```bash
cd frontend-flutter
flutter run -d <id-device> --dart-define=API_HOST=192.168.1.115
```

Lihat daftar device dengan `flutter devices`.

#### 3d. Versi Android — APK terpasang (paling aman untuk sidang)

Buat APK-nya **H-1**, jangan hari-H:

```bash
cd frontend-flutter
flutter build apk --release --dart-define=API_HOST=192.168.1.115
```

Hasilnya di `build/app/outputs/flutter-apk/app-release.apk`. Salin ke HP dan pasang.

> **IP-nya tertanam saat build.** Kalau IP laptop berubah di lokasi sidang, APK ini tidak akan konek dan harus dibangun ulang — itu sebabnya cek IP di langkah 1.2 penting dilakukan lagi di tempat.

### Langkah 4 — Masuk

| Peran | Email | Sandi |
|---|---|---|
| Administrator | `admin@example.com` | `admin123` |
| Warga | `warga@example.com` | `warga123` |

Akun warga yang dibuat lewat Data Warga memakai **NIK** sebagai email sekaligus username, dengan sandi `123456`.

---

## Bagian 3 — Kalau memakai ngrok

Hanya bila Anda butuh webhook Midtrans.

```bash
ngrok http 3001
```

Salin alamat `https://xxxx.ngrok-free.app` yang muncul, lalu:

1. **Klien web:** isi `frontend-web/.env.local` →
   `VITE_API_BASE_URL=https://xxxx.ngrok-free.app`, jalankan ulang `npm run dev`
2. **Klien Flutter:** `flutter run --dart-define=API_BASE_URL=https://xxxx.ngrok-free.app`
3. **Midtrans:** perbarui *Notification URL* di dashboard sandbox ke
   `https://xxxx.ngrok-free.app/api/payments/notifikasi`

**Alamatnya berganti setiap ngrok direstart.** Ketiga hal di atas harus diperbarui setiap kali.

### Wajib: buka alamat ngrok sekali di browser lebih dulu

ngrok paket gratis menyodorkan halaman peringatan untuk apa pun yang tampak seperti browser. Buka `https://xxxx.ngrok-free.app` di browser laptop **dan** di browser HP, tekan **"Visit Site"** satu kali. Setelah itu ngrok menandai peramban tersebut dan berhenti mengganggu.

Lakukan ini **sebelum** demo, bukan saat penguji sedang menonton.

---

## Bagian 4 — Kalau ada yang bermasalah

| Gejala | Penyebab paling mungkin | Tindakan |
|---|---|---|
| Aplikasi bilang "gagal terhubung" | Backend mati, atau IP salah | Buka `http://<ip>:3001/api/health` dari HP. Gagal → jaringan. Berhasil → alamat di klien salah |
| HP tidak konek, laptop bisa | Firewall port 3001 | Jalankan perintah di 1.1 sebagai Administrator |
| HP tidak konek, `/api/health` juga gagal | Beda jaringan Wi-Fi | Samakan jaringannya, atau jadikan HP hotspot lalu sambungkan laptop ke situ |
| **Export Excel/PDF membuka halaman ngrok** | Halaman peringatan ngrok | Buka alamat ngrok sekali, tekan "Visit Site" (Bagian 3). Di klien web sudah diperbaiki lewat unduhan `fetch` |
| Semua fitur jalan, hanya export gagal | Sama seperti di atas | Bukan backend — endpoint export-nya sehat |
| Tabel kosong padahal data ada | Peran tidak punya izin, atau penyaring bulan | Cek Menu & Akses; periksa penyaring periode di layar itu |
| Tagihan Saya kosong untuk warga | Akun warga tidak punya `no_kk` | Tagihan disaring lewat kartu keluarga. Pakai akun warga yang dibuat dari Data Warga |
| Port 3001 dipakai proses lain | Node lama belum mati | `npm start` sudah menjalankan `kill-port` otomatis; kalau tetap gagal, restart laptop |
| Alarm/tombol panik tidak bunyi | WebSocket putus | Lihat ikon sinyal di kanan atas — abu-abu berarti terputus. Jalankan ulang backend |

---

## Bagian 5 — Ringkasan satu layar

Cetak atau tempel bagian ini.

```
1. PostgreSQL nyala
2. cd backend-node && npm start          → biarkan terbuka
3. Cek: http://localhost:3001/api/health → harus JSON
4. Cek dari HP: http://<IP>:3001/api/health
5. cd frontend-web && npm run dev        → http://localhost:5173
   (atau buka APK di HP)
6. Masuk: admin@example.com / admin123

IP laptop hari ini: ____________________
(cek ulang di lokasi, jangan pakai catatan lama)
```

**Tiga hal yang paling sering menggagalkan demo, semuanya bisa dicegah:**
1. IP laptop berubah di lokasi sidang → cek ulang, bangun ulang APK bila perlu
2. Firewall belum dibuka → jalankan perintah 1.1 sekali, permanen
3. Halaman peringatan ngrok → buka sekali, tekan "Visit Site"
