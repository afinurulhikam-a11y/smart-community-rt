# Walkthrough Fase B — pencabutan sesi & tiket unduh

Auth Hardening Fase B menutup dua lubang yang tersisa dari audit: **sesi yang
tidak bisa dicabut**, dan **token sesi yang melintas di URL**. Fase C (refresh
token, cookie, CSRF) tidak disentuh sama sekali, dan **RBAC tidak berubah**.

---

## 1. Sesi kini bisa dicabut

Sebelumnya menekan "Keluar" tidak mencabut apa pun: tidak ada endpoint logout di
seluruh backend, klien hanya menghapus token dari perangkatnya sendiri, dan token
yang sempat disalin tetap dijawab `200` sampai kedaluwarsa alaminya — 24 jam.

| Bagian | Berkas |
|---|---|
| Kolom `users.token_versi` | `database/migrations-lama/migration_v29_token_versi.js` |
| Klaim `tv` di JWT | `src/controllers/auth.controller.js` (`login`) |
| Penolakan token basi | `src/middleware/auth.middleware.js` |
| `POST /api/auth/logout` | `src/controllers/auth.controller.js` (`logout`) |
| Dialog peringatan | `lib/screens/admin/main_dashboard.dart` (`_konfirmasiKeluar`) |

**Logout bersifat GLOBAL.** Versinya melekat pada *pengguna*, bukan pada sesi,
jadi menekan Keluar di ponsel juga mengakhiri sesi di desktop. Dialog Keluar
menyebutkannya sebelum tombolnya ditekan — perilaku yang mengejutkan tanpa
peringatan adalah cacat tersendiri, walau amannya benar.

**Integer, bukan timestamp.** `iat` berasal dari jam proses Node dan `NOW()` dari
jam Postgres — sumber berbeda, presisi berbeda (detik vs mikrodetik), di Railway
kontainer terpisah. Rancangan timestamp punya satu cacat yang tidak bisa ditambal
tanpa menukarnya dengan cacat lain: logout lalu **login ulang pada detik yang
sama** menghasilkan token sah yang justru ikut tertolak. Perbandingan bilangan
bulat menghapus seluruh kelas masalah itu.

**Migrasinya tidak mengeluarkan siapa pun.** Kolomnya lahir `0`, dan token lama
tanpa klaim `tv` dibaca sebagai `0` juga. Token yang sedang beredar tetap
berlaku sampai pemiliknya menekan Keluar sekali, atau sampai kedaluwarsa.

### Dua perubahan penyerta yang membuat pencabutan itu benar-benar berlaku

1. **Jalur galat database kini `503`, bukan `next()`.** Sebelumnya `catch`
   menyetel `req.user = decoded` lalu meneruskan, sehingga gangguan database
   memberikan akses dengan **tidak satu pun** pemeriksaan di atasnya berjalan —
   akun nonaktif lolos, akun terhapus lolos, sesi yang baru dicabut lolos.
2. **Cache sesi 30 detik dibongkar**, beserta `invalidateAuthCache` dan dua
   pemanggilnya di `user.controller.js`. `token_versi`, `is_active`, dan
   `deleted_at` menentukan hidup-matinya sesi; menyimpannya berarti token yang
   dicabut sedetik lalu masih diterima, dan pada Railway yang bisa menjalankan
   lebih dari satu instance, `invalidateAuthCache` di satu proses tidak pernah
   terlihat proses lain. Karena ketiganya wajib segar, `SELECT`-nya berjalan tiap
   permintaan dan cache tidak lagi menghemat apa pun.

   **Konsekuensi operasional:** satu `SELECT` terindeks per permintaan kembali
   berjalan. Bila pool terasa sesak, naikkan `DB_POOL_MAX` — jangan kembalikan
   cache di jalur ini.

---

## 2. Tiket unduh sekali pakai

Sebuah **navigasi browser tidak bisa membawa header**, jadi setiap tombol Export
menempelkan `?token=<jwt>` ke URL-nya — sembilan tempat. Akibatnya kredensial
sesi ikut tercatat di log akses server dan setiap proxy di jalur, di riwayat
browser, dan di header `Referer`.

| Bagian | Berkas |
|---|---|
| Tabel `tiket_unduh` | `database/migrations-lama/migration_v30_tiket_unduh.js` |
| Daftar tertutup jenis unduhan | `src/config/jenis-unduh.js` |
| Terbit & tukar | `src/controllers/unduh.controller.js` |
| Rute | `src/routes/unduh.routes.js` |
| Helper klien | `ApiService.unduhDenganTiket` di `lib/core/services/api_service.dart` |

Alurnya: `POST /api/unduh/tiket` menukar sesi yang sah dengan nilai acak 32 byte
berumur 60 detik → klien membuka `GET /api/unduh/:tiket` → server menebusnya dan
menyerahkan berkasnya.

**Yang disimpan hanya SHA-256-nya.** Bocornya isi tabel `tiket_unduh` tidak
memberi siapa pun satu unduhan pun — alasan yang sama kenapa kata sandi tidak
pernah disimpan apa adanya.

**Satu `UPDATE` atomik menutup enam hal sekaligus** — sekali pakai, kedaluwarsa,
akun terhapus, akun nonaktif, dan **sesi yang sudah dicabut**. Pola yang sama
dipakai `payBill`: dua permintaan bersamaan, hanya satu yang menemukan baris
dengan `dipakai_pada IS NULL`.

**Izin diperiksa DUA KALI** — saat tiket dibuat dan saat ditukar — karena Menu &
Akses bisa mencabut izin di dalam jendela 60 detik itu. Tiket bukan izin beku.
Penukaran memanggil controller export yang **sudah ada** dengan `req` yang
disusun ulang, sehingga pemeriksaan kepemilikan di dalamnya
(`bolehMengaksesTagihan`) ikut berjalan: jalur tiket sama ketatnya dengan jalur
bearer, tidak pernah lebih longgar.

---

## 3. KEPUTUSAN DEPLOYMENT — `?token=` dipertahankan sementara

> **Backend dan klien tidak naik pada detik yang sama.** Flutter Web produksi
> yang berjalan hari ini masih menyusun URL unduhan dengan `?token=`. Kalau
> backend Fase B naik dengan jalur itu sudah tertutup, **setiap tombol Export di
> produksi mati seketika** — dan matinya tidak terbaca sebagai galat yang bisa
> ditebak, melainkan sebagai "aplikasi tiba-tiba rusak".

Karena itu urutannya dipisah:

| | |
|---|---|
| **Sekarang** | Tiket unduh dipasang, diuji, dan dipakai klien baru. `?token=` **tetap hidup** berdampingan. |
| **Nanti** | `?token=` dicabut, setelah Flutter Web produksi terverifikasi memakai `unduhDenganTiket()` pada seluruh pemanggil. |

Saklarnya: **`IZINKAN_TOKEN_QUERY`** di `src/config/kompatibilitas.js`.

**Bawaannya `true` — permisif, dan itu disengaja.** Deploy yang lupa mengisi
baris itu tidak boleh mematikan klien lama; justru itu kejadian yang saklar ini
ada untuk mencegah. Arah amannya baru berbalik setelah klien baru terbukti jalan.

**Kenapa saklar env, bukan sekadar "nanti dihapus".** "Nanti dihapus" tidak punya
tanggal dan tidak punya cara diuji. Sebuah saklar punya keduanya: pencabutannya
bisa dicoba lebih dulu (`IZINKAN_TOKEN_QUERY=false`) tanpa mengubah satu baris
kode, dan dibalikkan seketika bila masih ada pemanggil yang tertinggal.

### Yang TIDAK dilonggarkan oleh saklar ini

Token dari query menjalani pemeriksaan yang **sama persis** dengan token dari
header — tanda tangan, allowlist algoritma, kedaluwarsa, akun, **dan
`token_versi`**. Sesi yang sudah dicabut tetap ditolak walau tokennya dikirim
lewat URL. Yang dikembalikan saklar ini hanyalah **cara token dibawa**, bukan
kelonggaran atas siapa yang boleh masuk. Bagian B3 uji penerimaan membuktikan
ketiganya satu per satu.

### Risiko yang tetap terbuka selama saklarnya `true`

URL lengkap beserta tokennya tercatat di log akses server dan proxy, riwayat
browser, dan header `Referer`. **Sasaran Fase B "token tidak pernah muncul di
URL" karena itu belum tercapai — ia ditunda, bukan selesai.** Yang meringankan,
dan itu bukan kebetulan: sejak Fase B, token yang bocor lewat log bisa
**dimatikan** dengan menekan Keluar. Sebelumnya ia hidup 24 jam tanpa satu pun
cara menghentikannya.

`GET /reset/cadangan` ikut dipertahankan di balik saklar yang sama — ia hanya
berguna lewat `?token=`. Begitu saklarnya mati, rutenya **tidak didaftarkan sama
sekali**, bukan sekadar menjawab 401; itu lebih jujur daripada meninggalkan rute
yang menyisakan kesan jalurnya masih ada. Ini URL yang paling tidak boleh
tercatat di log — ia menstreamkan dump mentah seluruh tabel dalam satu grup
reset, data warga termasuk — jadi ia yang pertama harus ditinggalkan.

### Kapan saklarnya boleh dimatikan

Penandanya ada di log, dan sengaja dibuat ada. Setiap pemakaian jalur legacy
mencetak (dibatasi satu baris per menit supaya tidak membanjiri log):

```
[LEGACY] ?token= masih dipakai → GET /api/warga/export/excel
  — klien lama belum diperbarui; jangan setel IZINKAN_TOKEN_QUERY=false dulu.
```

Tokennya sendiri **tidak** ikut dicetak — menuliskannya ke log adalah persis
kebocoran yang sedang dibicarakan.

**Selama baris itu masih muncul, masih ada klien lama di luar sana.** Setelah ia
berhenti muncul selama beberapa hari sejak Flutter Web produksi yang baru
di-deploy, pencabutannya aman:

1. Setel `IZINKAN_TOKEN_QUERY=false` di Railway. Tidak perlu deploy kode.
2. Jalankan ulang uji penerimaan dengan saklar mati (lihat di bawah) — harus
   58 lulus.
3. Bila ada yang tertinggal, kembalikan ke `true`; efeknya seketika.
4. Setelah tenang, hapus saklarnya beserta cabang `?token=` dan
   `GET /reset/cadangan` dari kode.

---

## 4. Residual security issue — WebSocket `?token=`

**Fase B tidak menutup ini.** `src/config/websocket.js` membaca token dari
`url.searchParams.get('token')`, dan tetap begitu. Setelah `?token=` kelak
dicabut dari `authMiddleware`, WebSocket menjadi **satu-satunya tempat tersisa**
yang membawa kredensial di dalam URL.

**Kenapa tidak ditutup:** WebSocket API di browser tidak menyediakan cara
menyetel header pada handshake. Batasan platform, bukan pilihan.

| | |
|---|---|
| Bocor ke `Referer` | tidak — handshake WS tidak mengirimnya |
| Riwayat browser | tidak |
| **Log server / proxy** | **YA** |
| Umur token yang bocor | ≤24 jam, **dan sejak Fase B bisa dimatikan dari tombol Keluar** |

Jalan menutupnya bila kelak dikerjakan: perluas mekanisme tiket ke handshake WS
(`jenis: 'ws.connect'`). Tidak dikerjakan sekarang karena menyentuh alur tombol
panik, dan alarm yang gagal berbunyi lebih buruk daripada risiko ini.

---

## 5. Uji penerimaan

### Uji keamanan & kompatibilitas

> Suite-suite `uji-*.js` di bawah hidup di **scratchpad, bukan di dalam repo** —
> mengikuti kebiasaan yang sudah dipakai `uji-iuran-air.js` dan
> `uji-penjadwal.js`. Karena itu tabel kriterianya ditulis lengkap di sini:
> siapa pun bisa mengulanginya dengan `curl` tanpa berkas skripnya.

Suite `scratchpad/uji-auth-fase-b.js`, dijalankan **dua kali** dengan server
ber-env berbeda, karena kedua sisi saklar tidak bisa hidup bersamaan:

```bash
# Sisi klien lama — keadaan saat deploy Fase B
node src/index.js                                   # IZINKAN_TOKEN_QUERY default true
node scratchpad/uji-auth-fase-b.js                  # → 60 lulus

# Sisi setelah pencabutan — dijalankan sebelum mematikannya di produksi
IZINKAN_TOKEN_QUERY=false node src/index.js
IZINKAN_TOKEN_QUERY=false node scratchpad/uji-auth-fase-b.js   # → 58 lulus
```

Bagian **B3 — KOMPATIBILITAS DEPLOYMENT** yang menjaga keputusan di atas:

| Saklar | Yang diperiksa | Harapan |
|---|---|---|
| `true` | `?token=` pada endpoint biasa | **200** — klien lama tidak putus |
| `true` | Tombol Export klien lama | **200** |
| `true` | `GET /reset/cadangan` klien lama | **200** |
| `true` | **Token yang sudah di-logout, lewat `?token=`** | **401** — jalur legacy bukan pintu belakang |
| `true` | HS512 lewat `?token=` | **401** — allowlist tetap berlaku |
| `true` | Warga menembak export lewat `?token=` | **403** — RBAC tetap berlaku |
| `false` | `?token=`, export, cadangan | **401** |
| `false` | `GET /reset/cadangan` dengan Bearer sah | **404** — rutenya benar-benar tidak terdaftar |
| keduanya | **Jalur tiket** | **200** — pencabutan nanti hanya menghapus jalur lama |

### Bukti bergigi

`scratchpad/bukti-bergigi-fase-b.js` merusak setiap penjaga satu per satu dan
memastikan suite-nya **jatuh** — sebuah uji yang tetap hijau setelah penjaganya
dicopot tidak menguji apa pun. Setelahnya kode dikembalikan dan suite hijau lagi,
dan pemulihan itu ikut dibuktikan, bukan diasumsikan.

| # | Yang dirusak | Yang harus tertangkap |
|---|---|---|
| 1 | Pemeriksaan `token_versi` di `authMiddleware` | logout tidak lagi mencabut |
| 2 | **Jalur legacy `?token=` dimatikan diam-diam** | klien lama putus pada deploy |
| 3 | **Jalur legacy meloloskan token tanpa cek akun** | legacy jadi pintu belakang yang melewati pencabutan |
| 4 | Pencocokan `token_versi` pada penukaran tiket | tiket hidup lebih lama daripada sesinya |
| 5 | Pemeriksaan izin **kedua** saat tiket ditukar | tiket membekukan izin |
| 6 | `dipakai_pada IS NULL` | tiket tidak lagi sekali pakai |

Nomor 2 dan 3 adalah pasangan yang menjaga keputusan deployment dari dua arah
yang berlawanan: yang satu memastikan jalur lama **tidak mati diam-diam**, yang
lain memastikan ia **tidak menjadi celah**.

### Regresi

| | |
|---|---|
| `uji-auth-fase-a.js` | 35/35 |
| `flutter test` | 347 hijau (termasuk 4 uji `logout_test.dart`) |
| `npx eslint src/` · `flutter analyze` | bersih |
| `schema.sql` | ditangkap ulang, terbukti termuat dari nol — 33 tabel |
| `periksa-kesehatan.js` | 29 endpoint sehat untuk admin dan warga |

**Yang merah dan bukan karena Fase B:** `uji-iuran-air.js` (6 gagal) dan satu
pemeriksaan `uji-penjaga-generate.js`. Keduanya bergantung kalender dan fixture —
`uji-iuran-air` dijalankan ulang terhadap kode pra-Fase B lewat `git stash` dan
**gagal identik, 6 yang sama persis**. Penyebabnya penjaga `POST /bills/generate`
dari pekerjaan sebelumnya, bukan perubahan di sini.

---

## 6. Urutan penerapan ke Railway

**`git push` tidak pernah menjalankan migrasi.** Kode Fase B menulis `tv` dari
`users.token_versi` dan membaca tabel `tiket_unduh`; keduanya harus ada lebih
dulu, atau login galat begitu deploy naik.

1. Buka TCP proxy Railway.
2. Jalankan `migration_v29_token_versi.js` dan `migration_v30_tiket_unduh.js`
   terhadap `RAILWAY_DB_URL` (bukan `DATABASE_URL` internal). Keduanya idempoten.
3. Verifikasi strukturnya di sana.
4. **Cabut kembali TCP proxy-nya.**
5. Pastikan `IZINKAN_TOKEN_QUERY` **tidak** disetel `false` di Railway.
6. Baru deploy kode.

Skema dulu, kode menyusul — sama seperti v28.
