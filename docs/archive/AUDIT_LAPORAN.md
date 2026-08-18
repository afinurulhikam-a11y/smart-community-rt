# AUDIT LAPORAN — Smart Community RT (Backend & Integrasi)

Tanggal: 2026-08-09
Ruang lingkup: backend-node (Express + PostgreSQL), integrasi frontend-flutter (web), WebSocket,
auth/permission, business logic, konsistensi data, referensi modul terhapus, regression test.

Metodologi:
- Audit statis: seluruh 29 file route (142 rute), 26 controller, middleware, config, service.
- Audit dinamis: server nyata di localhost:3001 (Postgres hidup), login 3 role, uji CRUD,
  uji 401/403/404, uji endpoint mati.
- Pemeriksaan data: query konsistensi silang (bills↔bill_payments↔finances↔keluarga), 
  periksa-kesehatan.js, hitung saldo manual vs API.
- Regression: flutter test (201/201 lolos), eslint bersih.

Status: PASS | FAIL | WARNING | NOT TESTED

================================================================
RINGKASAN EKSEKUTIF
================================================================

Total temuan: 5 FAIL (2 kritis), 6 WARNING, 0 keamanan kritis aktif,
12+ modul PASS.

Dua masalah kritis (keduanya ketidaksesuaian frontend-backend yang
mengakibatkan fitur tidak berfungsi untuk pengguna non-admin):

1. [FAIL-KRITIS] Modul PENGUMUMAN tidak dapat diakses oleh siapa pun
   selain admin. Rute GET/POST/PUT /api/announcements menuntut izin
   `kegiatan.pengumuman`, tetapi menu itu TIDAK PERNAH didaftarkan di
   MENU_ITEMS (src/config/permissions.js) maupun role_permissions DB.
   Semua non-admin (termasuk warga, yang melihat tab Pengumuman di
   Agenda & Kegiatan) menerima 403 "Modul tidak dikenali".

2. [FAIL-KRITIS] Modul SISKAMLING/RONDA terhapus dari backend
   (tidak ada route/controller patrol), tetapi sisa-sisanya masih ada:
   tabel patrol_schedules/patrol_attendances/patrol_qr_tokens dibuat
   auto-setup.js; menu `kegiatan.ronda` masih di menu_items &
   role_permissions; frontend masih punya 4 konstanta API patrol
   (dead code), label "Jadwal & Absensi Ronda" di navigasi_bawah
   (case 51), dan tile "Jadwal Ronda" di dashboard warga yang menekan
   tidak menghasilkan apa-apa (main_dashboard tidak punya case 51).

================================================================
RINCIAN TEMUAN PER MODUL
================================================================

----------------------------------------------------------------
A. AUTENTIKASI & SESI
----------------------------------------------------------------
[PASS] POST /api/auth/login — email/username/NIK + bcrypt, rate limit
  5/menit/IP, mencatat LOGIN_GAGAL utk akun tak terdaftar, non-aktif,
  dan sandi salah (log.service).
[PASS] POST /api/auth/register — sengaja 403 (registrasi mandiri
  ditutup; akun dibuat via Data Warga). Terverifikasi via API.
[PASS] GET /api/auth/me & PUT /profile & PUT /change-password —
  authMiddleware global; change-password di rate-limit ketat.
[PASS] authMiddleware — verifikasi JWT + cek akun ke DB per request
  (role dari DB, bukan token), cache 30 detik, invalidate saat
  status/role berubah. Akun nonaktif => 401. DB error => fallback ke
  payload JWT (catatan: CLAUDE.md menyebut 503, kode memakai fallback;
  lihat WARNING-1).
[PASS] Token via query ?token= utk unduhan file.

----------------------------------------------------------------
B. OTORISASI & PERMISSION
----------------------------------------------------------------
[PASS] requirePermission membaca menu_items + role_permissions; admin
  selalu lolos; menu is_sistem ditolak utk non-admin; fail-closed.
[PASS] roleGuard('admin') pada rute pengaturan/reset/menu-akses/users
  sensitive.
[PASS] Matriks izin default per role (permissions.js) konsisten dgn
  DB; 19 menu x 5 role = 95 baris role_permissions, semua cocok.
[FAIL-KRITIS] `kegiatan.pengumuman` TIDAK ADA di MENU_ITEMS maupun
  DEFAULT_PERMISSIONS (permissions.js:29-56). Akibat: semua rute
  announcements -> 403 untuk setiap non-admin. Lihat D.
[WARNING] `kegiatan.ronda` ada di menu_items/role_permissions DB tetapi
  TIDAK di permissions.js (sumber kebenaran) — menu yatim yg
  menunjuk modul yang sudah tidak ada. Lihat E.
[PASS] menu-akses/me mengembalikan daftar menu + izin efektif per role
  (terverifikasi utk warga & bendahara).

----------------------------------------------------------------
C. MIDDLEWARE & PENGAMANAN HTTP
----------------------------------------------------------------
[PASS] helmet (CSP nonaktif), CORS explicit dgn
  ngrok-skip-browser-warning + Private-Network, preflight OPTIONS
  manual (index.js:106-120), compression, JSON body limit 1MB,
  morgan, rate limiter login & jalur sensitif.
[PASS] Graceful shutdown SIGINT/SIGTERM + uncaughtException handler
  (index.js:283-304) sesuai rule .antigravity.
[PASS] 404 handler & global error handler (500) ada.
[WARNING] uncaughtException TIDAK mematikan proses — handler hanya
  mencatat. EADDRINUSE saat port dipakai tetap "Server Kept Alive"
  tanpa listener aktif (teramati saat start kedua). Ini konsisten
  dgn desain "jangan mati", tapi menyulitkan diagnosa.

----------------------------------------------------------------
D. PENGUMUMAN (announcements)
----------------------------------------------------------------
[FAIL-KRITIS] Rute GET/POST/PUT /api/announcements menuntut izin
  `kegiatan.pengumuman`, tapi menu tsb tidak pernah dibuat.
  Terverifikasi langsung: GET /api/announcements dengan token
  bendahara & warga -> 403 "Modul tidak dikenali".
  Dampak: tab Pengumuman di AgendaKegiatanScreen (menu 50) KOSONG
  untuk semua non-admin — sekretaris & warga TIDAK BISA melihat
  pengumuman. Admin bisa (lolos requirePermission), jadi bug ini
  mungkin tidak terlihat saat demo dengan admin.
  Lokasi: backend-node/src/config/permissions.js (MENU_ITEMS);
  backend-node/src/routes/announcement.routes.js:8-11.
  Rekomendasi: tambahkan `kegiatan.pengumuman` ke MENU_ITEMS
  (grup Kegiatan & Info, menu_index 50 sama dgn agenda atau indeks
  terpisah) + baris DEFAULT_PERMISSIONS utk tiap role (warga V,
  pengurus F/V sesuai pola agenda), lalu jalankan seed/auto-setup
  atau POST /api/menu-akses/reset.

----------------------------------------------------------------
E. SISKAMLING / RONDA (patrol) — modul terhapus yg masih meninggalkan jejak
----------------------------------------------------------------
[FAIL-KRITIS] Frontend masih memanggil /patrol/* (4 konstanta di
  api_constants.dart:212-215) dan menampilkan label/tile menu 51,
  sedangkan backend TIDAK punya route patrol (404 terverifikasi:
  "Route GET /api/patrol/schedules tidak ditemukan").
  Yang tertinggal:
   - backend-node/src/config/auto-setup.js — membuat tabel
     patrol_schedules/patrol_attendances/patrol_qr_tokens tiap start,
     + UPDATE role_permissions utk kegiatan.ronda (bug matriks awal).
   - DB: menu_items.kegiatan.ronda (is_aktif=true), role_permissions
     utk semua role.
   - frontend-flutter/lib/core/constants/api_constants.dart:212-215
     (patrolSchedules, patrolAttendances, patrolQr, patrolQrRegenerate)
     — dead code, tidak dipakai screen mana pun.
   - frontend-flutter/lib/widgets/navigasi_bawah.dart:63-64 — case 51
     "Jadwal & Absensi Ronda".
   - frontend-flutter/lib/screens/warga/warga_dashboard_content.dart:
     573-581 — tile "Jadwal Ronda" (menu 51) utk warga; ditekan => 
     tidak terjadi apa-apa (main_dashboard tidak punya case 51).
  Dampak: tile dashboard warga adalah jalan buntu; konstanta mati;
  tabel patrol tetap dibuat (sampah skema); izin kegiatan.ronda
  menampilkan menu di dashboard tapi tidak ada layar.
  Rekomendasi (per skill removing-modules-safely): putuskan hapus
  total atau hidupkan kembali. Jika hapus: buang CREATE TABLE patrol
  dari auto-setup.js, hapus menu kegiatan.ronda + role_permissions-nya
  (via migration), hapus 4 konstanta + case 51 + tile warga. Jika
  hidupkan: buat route/controller patrol + screen Flutter.
  Catatan: karena MENU_ITEMS (permissions.js) TIDAK memuat
  kegiatan.ronda, rute requirePermission apapun utk ronda akan 403 —
  jadi "hidupkan kembali" juga perlu menambahkannya ke permissions.js.

----------------------------------------------------------------
F. KEUANGAN — IURAN (bills) & KAS RT (finances)
----------------------------------------------------------------
[PASS] GET /bills — pagination (LIMIT/OFFSET param), scoping warga
  via keluarga.no_kk (terverifikasi: warga melihat tagihan KK-nya).
[PASS] GET /bills/stats — angka dari SQL agregat (total_tagihan,
  jumlah_lunas, tunggakan, nominal, persentase). Konsisten dgn data:
  total 18, lunas 11, tunggakan 7, nominal_total 900000 (benar).
[PASS] POST /bills/generate — idempoten (unique bills_kk_jenis_bulan),
  satu baris per keluarga.
[PASS] POST /bills/:id/pay — requirePermission keuangan.iuran.update,
  transaksi + row lock, catatKeKasRt() dalam transaksi yg sama.
[PASS] payBillsBulk — lock + unique bill_payments(bill_id) (double
  payment dicegah).
[PASS] Konsistensi data terverifikasi: 11 bill_payments ↔ 11 baris
  finances sumber='iuran' (ref_id uuid match, 0 yatim), saldo manual
  (pem 4.050.000 − peng 2.975.000 = 1.075.000) SAMA dgn
  GET /finances/summary (saldo_total 1.075.000).
[PASS] GET /finances — pagination param, filter bulan.
[PASS] POST /finances — validasi kategori, tipe, nominal >= 0;
  updateTransaction menolak sumber='iuran' (harus lewat Iuran Warga).
[WARNING] GET /finances/bulanan dan summary memakai window function
  ROWS UNBOUNDED PRECEDING (sudah benar). Namun POST /finances
  menerima `tanggal` bebas (bisa masa lalu/bulan lain) — perlu cek
  validasi konsistensi laporan bulanan (lihat K).

----------------------------------------------------------------
G. DANA BOP
----------------------------------------------------------------
[PASS] GET /bop/summary — sisaPagu (alokasi − terpakai) & saldo kas
  terpisah, benar sesuai CLAUDE.md. Terverifikasi: summary berisi
  alokasi, terpakai, sisa_pagu, saldo.
[PASS] CRUD bop + alokasi_bop + kategori_bop — permission yg benar,
  over-budget hanya peringatan (tidak diblokir).
[PASS] Konsistensi alokasi vs bop_finances: 1 alokasi, 6 baris
  bop_finances, tidak ada yatim.

----------------------------------------------------------------
H. KEPENDUDUKAN — keluarga, warga, statistik, bansos
----------------------------------------------------------------
[PASS] GET /families & /warga — pagination, search ILIKE parameterized,
  scoping warga (role==='warga' => hanya KK sendiri) di list, export
  Excel & PDF (buildWargaQuery dipakai bersama).
[PASS] POST /warga (tambahWargaLengkap) — membuat keluarga + anggota +
  akun user (NIK=username, sandi acak via utils/sandi.js), log CREATE.
[PASS] GET /demographics/summary — data riil: total_warga 36,
  total_kk 12, L/P 18/18 (cocok dgn anggota_keluarga 36 baris).
[PASS] Bansos — validasi user_id/jenis/tahun, history log, stats.
[WARNING] Data uji saat ini: akun `warga@example.com` (seed-master)
  TIDAK punya no_kk -> Tagihan Saya selalu kosong (bukan bug, tapi
  perilaku yang membingungkan saat demo; seed-demo mengikat warga ini
  ke KK lewat no_kk? — verifikasi: seed-demo membuat KK terpisah).
  periksa-kesehatan.js melaporkan [MASALAH] utk ini. Bukan bug kode.

----------------------------------------------------------------
I. LAYANAN — surat, e-visitor
----------------------------------------------------------------
[PASS] GET/POST /letters, PUT /:id/approve — scoping warga via
  user_id, permission layanan.surat.view/create/update. Terverifikasi
  bendahara ditolak (tidak punya izin) dgn 403 yg tepat.
[PASS] Visitors — validasi wajib lengkap (Blok Tujuan, No HP, detail,
  jenis kendaraan, plat), checkout idempoten, stats per hari.
[WARNING] Pesan error validasi visitor membocorkan daftar field wajib
  (informatif, bukan bocor data) — fine.

----------------------------------------------------------------
J. ASPIRASI — pengaduan, polling, darurat
----------------------------------------------------------------
[PASS] Complaints — create (warga), update status, delete (admin),
  scoping user_id utk warga, audit log (terverifikasi CREATE/UPDATE/
  DELETE tercatat di activity_logs).
[PASS] Polling — create (admin/pengurus), vote (view), unique
  (polling_id,user_id), hasil sudah_vote/pilihan_saya; konsistensi
  votes↔options terverifikasi 0 yatim.
[PASS] Emergency — trigger/dismiss butuh EMERGENCY_PIN (fail-closed
  503 jika kosong; rate limit ketat), broadcast WebSocket dgn payload
  dikurangi utk klien tanpa token. GET /alerts & /active utk yg punya
  izin aspirasi.darurat.
[WARNING] CLAUDE.md menyebut "roleGuard('warga') pada emergency/trigger"
  tetapi kode hanya authMiddleware + PIN. Semua role terautentikasi
  yg tahu PIN bisa trigger. PIN adalah kontrol utama — ini lebih kuat
  drpd roleGuard, tapi dokumentasi tidak sinkron dgn kode.
[WARNING] POST /emergency/dismiss/:id — siapa pun yg terautentikasi
  bisa dismiss alarm orang lain (tanpa cek kepemilikan). PIN hanya
  utk trigger, bukan dismiss. Pertimbangkan batasi ke admin/pengurus
  atau butuh PIN juga.

----------------------------------------------------------------
K. INVENTARIS
----------------------------------------------------------------
[PASS] GET /inventory — jumlah total (tidak dikurangi peminjaman),
  status Terlambat derived di read time, /borrowings sebelum /:id
  (sudah benar urutannya).
[PASS] Borrowings — create (warga dipaksa user_id sendiri), approve/
  reject/return, barang-tersedia utk warga (tanpa nilai_barang).
[PASS] Konsistensi: 4 borrowings ↔ 8 inventory, 0 yatim.

----------------------------------------------------------------
L. SENSOR (IoT)
----------------------------------------------------------------
[PASS] POST /sensors/log — roleGuard admin (atau akun sistem),
  GET /logs & /latest admin. Sensor logs 16 baris, ok.
[WARNING] CLAUDE.md: "Semua warga boleh melihat data sensor"
  (komentar di sensor.routes.js:10) tetapi kode TIDAK punya
  requirePermission — GET /logs & /latest hanya roleGuard admin
  (semua non-admin 403). Konsistensi: komentar vs kode tidak sinkron.

----------------------------------------------------------------
M. LOG AKTIVITAS & AUDIT TRAIL
----------------------------------------------------------------
[PASS] activity_logs append-only: trigger BEFORE DELETE/UPDATE +
  BEFORE TRUNCATE (migration_v19/v20), FK ke users dilepas (v20),
  reset_logs terproteksi.
[PASS] logActivity dipanggil dari hampir semua write path
  (24 controller), TIPE lengkap (LOGIN, LOGIN_GAGAL, CREATE, UPDATE,
  DELETE, PEMBAYARAN, IMPORT, AKSES, RESET, DARURAT). Terverifikasi:
  CRUD agenda/komplain saya tercatat lengkap dgn aktor & detail.
[PASS] GET /activity-logs — filter dari/sampai/user_id/offset, total;
  layar Flutter memakai parameter tsb (per CLAUDE.md).

----------------------------------------------------------------
N. RESET SISTEM
----------------------------------------------------------------
[PASS] reset.routes.js — seluruh rute roleGuard('admin') global
  (ringkasan, riwayat, pratinjau, cadangan GET/POST, eksekusi).
  Tidak menerima nama tabel dari klien (hanya kode grup);
  reset-groups.js self-check melindungi tabel protected.
[PASS] /reset/cadangan butuh ?grup= (400 utk grup tak dikenal).
[NOT TESTED] Eksekusi reset TIDAK dijalankan (menghapus data uji
  tidak diinginkan saat audit). Logika transaksi & ROLLBACK
  diverifikasi statis.

----------------------------------------------------------------
O. PAYMENT ONLINE (Midtrans)
----------------------------------------------------------------
[PASS] 4 money guards lengkap: verifikasiTandaTangan (sha512),
  re-fetch status ke Midtrans (webhook tdk percaya body),
  gross_amount match, idempotency 3 lapis (order_id UNIQUE, transisi
  hanya dari pending, finances_ref_uniq).
[PASS] POST /payments/iuran — requirePermission keuangan.iuran.view
  (bukan create), ownership warga via no_kk, transaksi + FOR UPDATE,
  nominal disalin ke payment_transaction_bills.
[PASS] Webhook & selesai dipasang di atas router.use(authMiddleware).
[NOT TESTED] Alur sandbox Midtrans penuh (butuh kredensial) — hanya
  verifikasi statis + simulasi error handling.

----------------------------------------------------------------
P. WEBSOCKET
----------------------------------------------------------------
[PASS] initWebSocket pada server HTTP yg sama, broadcast utk semua
  klien; payload dikurangi utk koneksi tanpa token (device ESP32).
[PASS] Health check melaporkan websocket_clients.
[NOT TESTED] Trigger alarm nyata dgn broadcast (butuh EMERGENCY_PIN
  terkonfigurasi) — hanya diverifikasi logika.

----------------------------------------------------------------
Q. FRONTEND — DATA & REGRESI
----------------------------------------------------------------
[PASS] Tidak ada data dummy/hardcode utk tampilan: semua kartu
  dashboard, statistik, dan daftar dari provider (yang membaca API).
  Scan "dummy/contoh/fake/placeholder" -> hanya komentar.
[PASS] Dashboard admin: TOTAL WARGA (demografi.summary.totalWarga),
  SALDO KAS (finance.summary.saldo), SISA DANA BOP (sisaPagu),
  Progress Iuran (bills.statsBulanIni dari backend, bukan hitung
  lokal), Status Darurat, Surat pending — semua dari API.
[PASS] flutter test: 201/201 lolos (termasuk layout 13+ layar,
  auto-login, tabel responsif). eslint backend: 0 error.
[WARNING] navigasi_bawah.dart masih punya case 51 (Ronda) dan 82
  (Manajemen Pengguna) yg TIDAK ada di main_dashboard — label mati
  yg tidak pernah dirender (defensive default 'Dashboard'). Bukan
  bug visual (tidak muncul), tapi sisa kode mati.
[WARNING] api_constants.dart: 4 konstanta patrol tak terpakai + tak
  ada endpoint backend (dead code).
[WARNING] index menu 81 (Profil Saya) tidak ada di menu_items DB —
  sengaja (layar sistem tanpa izin), bukan bug.

================================================================
PRIORITAS PERBAIKAN
================================================================

KRITIS (harus diperbaiki):
 P1. Daftarkan kegiatan.pengumuman di MENU_ITEMS + DEFAULT_PERMISSIONS
     (permissions.js) → jalankan seed atau POST /menu-akses/reset.
     Tanpa ini warga & pengurus tidak bisa melihat pengumuman sama
     sekali.
 P2. Ronda/patrol: hapus total (auto-setup CREATE TABLE, menu
     kegiatan.ronda, role_permissions, konstanta, case 51, tile) ATAU
     hidupkan kembali lengkap. Putuskan dulu — jangan dibiarkan
     setengah.

PENTING (WARNING, perlu keputusan):
 P3. Dismiss alarm tanpa batas kepemilikan (emergency).
 P4. Sinkronkan komentar/kode: sensor (roleGuard admin vs "semua
     warga"), emergency (roleGuard vs PIN), CLAUDE.md vs kode.
 P5. auto-setup.js masih membuat tabel patrol (sampah skema) meski
     modul mati — ikut P2.
 P6. Dokumentasi CLAUDE.md mengklaim 13 tabel terhapus; verifikasi
     patrol tidak tercantum (patrol BUKAN bagian dari 13 itu) — perlu
     update.

================================================================
CATATAN PENGUJIAN
================================================================
- Backend: POSTGRES lokal (smart_community_rt), server :3001.
- Login terverifikasi: admin@example.com/admin123, warga@example.com/
  warga123, bendahara.demo@rt.local/Demo1234.
- Data uji yang saya buat (agenda "Uji Audit", komplain "Uji komplain
  audit", jenis iuran uji) SUDAH DIHAPUS; tidak ada sisa data audit.
- periksa-kesehatan.js: 1 temuan (warga@example.com tanpa no_kk —
  perilaku seed, bukan bug); 1 uji dilewati krn rate limit login.
- flutter test 201/201; eslint 0; tidak ada error di console server
  selama audit (kecuali EADDRINUSE saat start duplikat yg saya buat).

================================================================
STATUS TINDAK LANJUT (2026-08-09)
================================================================
Perbaikan sudah dieksekusi & diverifikasi:

[FIXED] P1. kegiatan.pengumuman didaftarkan di MENU_ITEMS +
  DEFAULT_PERMISSIONS (permissions.js) + di-seed ke DB. Warga &
  semua pengurus kini bisa membaca pengumuman (diverifikasi via API:
  GET /announcements as warga & bendahara -> success).
  Izin: admin/ketua/sekretaris/bendahara = F, warga = V.

[FIXED] P2 + P5. Modul ronda/patrol DIHAPUS TOTAL:
  - backend: blok CREATE TABLE patrol di auto-setup.js diganti no-op;
    koreksi 'kegiatan.ronda' dihapus; reset-groups.js dibersihkan;
    seed-demo-lengkap.js tanpa blok Siskamling.
  - DB: DROP TABLE patrol_attendances, patrol_schedules,
    patrol_qr_tokens; DELETE role_permissions & menu_items
    kegiatan.ronda (cadangan data demo tersimpan saat hapus).
  - frontend: konstanta patrol di api_constants.dart, case 51 di
    navigasi_bawah.dart, tile 'Jadwal Ronda' di
    warga_dashboard_content.dart dihapus.
  Verifikasi: menu-akses/me warga tanpa kegiatan.ronda; flutter
  analyze 'No issues'; flutter test 203/203 PASS; eslint 0;
  hermes verify (build docker + Flutter web) ok:true.

Sisa catatan (belum dieksekusi, butuh keputusan Anda):
 P3. Dismiss alarm tanpa batas kepemilikan (emergency).
 P4. Sinkronkan komentar/kode: sensor roleGuard, emergency PIN,
     CLAUDE.md vs kode.
 P6. CLAUDE.md tulis patrol ke daftar tabel yang dihapus.
