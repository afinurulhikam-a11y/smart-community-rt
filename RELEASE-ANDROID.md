# Kebijakan Rilis Android — Smart Community RT

Berkas ini **ter-commit dengan sengaja**. `CLAUDE.md` dan `PANDUAN-SIDANG.md`
gitignored, sehingga aturan yang hanya ditulis di sana tidak ikut saat repo
di-clone, tidak terbaca penguji, dan hilang bersama mesin ini. Aturan di bawah
justru yang paling mahal bila dilanggar — jadi tempatnya di sini.

---

## Identitas aplikasi — permanen

```
applicationId = id.smartcommunityrt.app
```

**Jangan pernah diubah.** Android memperlakukan `applicationId` yang berbeda
sebagai **aplikasi yang berbeda**, bukan pembaruan. Mengubahnya setelah APK
tersebar berarti setiap warga harus meng-uninstall lalu memasang ulang, dan
selama belum melakukannya mereka akan melihat dua ikon berdampingan.

Nilai ini muncul di tiga tempat yang harus selalu selaras:

| Berkas | Yang harus cocok |
|---|---|
| `frontend-flutter/android/app/build.gradle.kts` | `namespace` dan `applicationId` |
| `.../src/main/kotlin/id/smartcommunityrt/app/MainActivity.kt` | deklarasi `package` |
| jalur direktori berkas di atas | harus mencerminkan paketnya |

`namespace` menentukan paket kelas `R` yang dihasilkan; kalau ia berbeda dari
`package` di `MainActivity.kt`, build gagal.

Nama paket **Dart** (`pubspec.yaml` → `name: smart_community`) adalah hal yang
sama sekali lain dan tidak boleh ikut diubah — seluruh `import
'package:smart_community/…'` bergantung padanya.

---

## Penandatanganan rilis

### Aturan

**Build rilis WAJIB memakai keystore rilis. Kunci debug DILARANG.**

Ini ditegakkan oleh build, bukan oleh ingatan: `android/app/build.gradle.kts`
memeriksa graf task sebelum satu pun task berjalan, dan melempar `GradleException`
bila `android/key.properties` tidak ada. Tidak ada jalur mundur otomatis.

Alasannya: jalur mundur diam berarti build rilis bisa **berhasil** dengan kunci
debug dan menghasilkan APK yang tampak siap edar. Kegagalan seperti itu tidak
berbunyi — ia baru ketahuan bila seseorang ingat memeriksa `apksigner`.

Build `debug` dan `profile` **tidak** terpengaruh dan tetap berjalan tanpa
keystore, sehingga siapa pun bisa meng-clone repo lalu `flutter run`.

### Membuat keystore

Sekali saja, dan hasilnya dijaga seumur hidup aplikasi. `keytool` ada di JDK
yang dibundel Android Studio (`…\Android Studio\jbr\bin`):

```
keytool -genkeypair -v ^
  -keystore %USERPROFILE%\keystores\smartcommunityrt-release.jks ^
  -storetype JKS -keyalg RSA -keysize 4096 -validity 10000 ^
  -alias smartcommunityrt
```

RSA 4096 dan 10.000 hari (±27 tahun) dipilih karena kunci ini **tidak bisa
diganti**: pada jalur sideload, mengganti kunci memaksa setiap warga
uninstall-install ulang. Biaya kunci besar dibayar sekali; biaya kunci
kedaluwarsa dibayar oleh semua orang.

### `android/key.properties`

Sudah tercakup `android/.gitignore` bersama `**/*.jks` dan `**/*.keystore`.

```
storePassword=…
keyPassword=…
keyAlias=smartcommunityrt
storeFile=C:/Users/…/keystores/smartcommunityrt-release.jks
```

### Penitipan

- **Keystore disimpan DI LUAR repositori.** Pola `.gitignore` hanya melindungi
  dari commit tidak sengaja; menaruhnya di luar pohon repo menghapus seluruh
  kelas kecelakaan itu — termasuk `git add -f`, arsip zip, dan penyalinan folder.
- **Dua salinan luring** di media terpisah.
- **Kata sandi di pengelola kata sandi**, bukan di catatan yang sama dengan
  berkas keystore-nya, dan **tidak pernah dikirim lewat chat**.

### Kehilangan keystore

Pada jalur sideload tidak ada Play App Signing yang bisa memulihkan. Kehilangan
keystore berarti setiap pembaruan berikutnya **ditolak dipasang menimpa**, dan
seluruh warga harus uninstall-install ulang. Ini satu-satunya kegagalan dalam
alur rilis ini yang tidak bisa di-rollback.

---

## Versi

Sumber tunggalnya `frontend-flutter/pubspec.yaml`:

```yaml
version: 1.1.0+3      # versionName+versionCode
```

**Jangan memakai `--build-name` / `--build-number` untuk rilis.** Keduanya hanya
menulis ke `android/local.properties`, yang gitignored dan ditulis ulang setiap
build — sehingga build berikutnya diam-diam kembali ke nilai lama, menghasilkan
APK yang **tidak bisa dipasang menimpa** rilis sebelumnya, tanpa peringatan apa
pun. Cacat itu pernah terjadi di proyek ini.

**`versionCode` WAJIB naik pada setiap artefak yang dibagikan**, tanpa
pengecualian. Android menolak memasang `versionCode` yang sama atau lebih rendah.
Naikkan juga bila isinya berbeda walau belum pernah dibagikan, supaya catatan
rilis dan SHA-256 tidak saling bertabrakan.

---

## Kebijakan cleartext (HTTP polos)

| Varian | Berkas | Nilai |
|---|---|---|
| **release** | `app/src/main/res/xml/network_security_config.xml` | `false` |
| debug | `app/src/debug/res/xml/network_security_config.xml` | `true` |
| profile | `app/src/profile/res/xml/network_security_config.xml` | `true` |

AGP menggabungkan resource dengan build type menimpa `main`, jadi tidak ada
percabangan di kode dan tidak ada bendera yang bisa lupa disetel.

APK rilis **hanya bisa HTTPS**. Produksi memang HTTPS
(`https://smart-community-rt-production.up.railway.app`), jadi tidak ada yang
sah yang terputus. Yang ditutup adalah serangan downgrade di jaringan publik:
penyerang memblokir HTTPS agar aplikasi jatuh ke HTTP, lalu membaca seluruh
lalu lintasnya.

**Konsekuensi:** menjalankan Flutter dalam mode rilis terhadap `http://ip-lan:3001`
akan gagal. Itu bukan bug, itu tujuannya. Untuk menguji build rilis terhadap
backend lokal, pakai tunnel HTTPS (ngrok) lewat `--dart-define=API_BASE_URL`.
Pengujian LAN biasa (`flutter run`) tidak terpengaruh sama sekali.

Perhatikan saat menyunting ketiga berkas itu: **komentar XML tidak boleh memuat
dua tanda hubung berurutan**, jadi jangan menuliskan opsi baris perintah Flutter
apa adanya di dalamnya. Kompilasi resource akan gagal.

---

## Prosedur build rilis

```bash
cd frontend-flutter
flutter analyze                     # harus bersih
flutter test                        # 347 baseline
flutter clean
flutter build apk --release
```

### Verifikasi artefak

`JAVA_HOME` = JDK Android Studio; perkakas dari `<SDK>/build-tools/36.0.0/`.
Jangan biarkan APK keluar dari mesin build sebelum seluruhnya hijau.

| # | Perintah | Harapan |
|---|---|---|
| 0a | Rename `key.properties`, lalu build `--release` | **GAGAL**, menyebut `key.properties` |
| 0b | Idem, build `--debug` | **BERHASIL** |
| 1 | `apksigner verify --print-certs <apk>` | DN **bukan** `CN=Android Debug`; v2 `true` |
| 2 | `aapt2 dump badging <apk>` | `name='id.smartcommunityrt.app'`, `versionCode`, `versionName`, `targetSdkVersion:'36'` |
| 3 | `aapt2 dump badging <apk>` | `application-label:'Smart Community RT'` |
| 4 | Lihat catatan di bawah — nama resource di-obfuscate pada rilis | `cleartextTrafficPermitted=false` |
| 5 | `unzip -p <apk> lib/arm64-v8a/libapp.so \| grep -c "/unduh/tiket"` | **> 0** |
| 6 | idem, `grep -c "export/excel?token"` | **0** |
| 7 | idem, `grep -c "?token="` | **1** (fragmen WebSocket) |
| 8 | idem, kesepuluh jenis unduhan | semuanya ada |
| 9 | `sha256sum <apk>` | dicatat ke catatan rilis |

**Butir 4 menuntut satu langkah tambahan pada build rilis.** Nama resource
di-obfuscate (`xml/network_security_config` → misalnya `res/8G.xml`), sehingga
menunjuk `--file res/xml/network_security_config.xml` gagal tanpa pesan yang
menjelaskan — persis jebakan yang membuat pemeriksaan ini tampak "kosong" dan
mudah dianggap lolos. Resolusikan namanya dulu:

```bash
aapt2 dump resources <apk> | grep -A1 "xml/network_security_config"
#   resource 0x7f100002 xml/network_security_config
#     () (file) res/8G.xml type=XML
aapt2 dump xmltree <apk> --file res/8G.xml
```

Nama acaknya berubah setiap build, jadi selalu resolusikan ulang; jangan menyalin
`res/8G.xml` dari catatan lama. Pada build debug namanya tidak di-obfuscate dan
jalur aslinya bisa dipakai langsung.

Butir 5–8 menjaga hasil Auth Hardening Fase B: seluruh unduhan lewat tiket sekali
pakai, dan satu-satunya `?token=` yang tersisa adalah handshake WebSocket.
Kesepuluh jenisnya: `iuran.export`, `iuran.kuitansi`, `kas.export`, `bop.export`,
`warga.excel`, `warga.pdf`, `bansos.export`, `inventaris.export`,
`peminjaman.export`, `reset.cadangan`.

Catatan teknis: teks dialog panjang tersimpan **UTF-16** di snapshot AOT (karena
memuat em-dash), jadi cari dengan encoding itu — bukan latin1.

---

## Verifikasi di perangkat — WAJIB sebelum dibagikan

Seluruh verifikasi di atas bersifat **statis**: ia memeriksa isi berkas, bukan
perilaku. Sebelum APK sampai ke warga, uji di Android sungguhan:

- Login sampai dasbor
- **Unduhan lewat tiket** (Excel, PDF, kuitansi) — `url_launcher` membuka Intent
  di Android, dan perilakunya berbeda dari Web
- Tombol **Keluar** beserta dialog "SEMUA PERANGKAT"
- Panggilan HTTPS ke produksi — membuktikan pembatasan cleartext tidak salah
  memblokir jalur yang sah
- WebSocket / tombol panik
- Kamera QR (izin runtime CAMERA)
- Pasang menimpa versi sebelumnya

Yang **hanya** bisa ketahuan di perangkat: apakah pembatasan cleartext memutus
sesuatu yang tak terduga. Tidak ada saklar runtime untuk itu — perbaikannya
menuntut build baru.

---

## Distribusi

Jalur saat ini **sideload**: APK dibagikan langsung, bukan lewat Play Store.
Konsekuensinya sudah tercakup di atas — keystore sepenuhnya tanggung jawab
sendiri, dan artefaknya APK (bukan AAB).

Bila kelak pindah ke Play Store: `applicationId` sudah aman dan tidak perlu
berubah, tetapi artefaknya menjadi AAB dan Play App Signing akan memegang kunci
penandatangan sementara keystore ini menjadi *upload key*.
