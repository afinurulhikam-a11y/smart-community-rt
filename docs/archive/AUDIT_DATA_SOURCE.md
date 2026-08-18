# AUDIT DATA TESTING — SMART COMMUNITY RT

Tanggal audit: 2026-08-09 (read-only; TIDAK ada perubahan kode/data/file)
Metode: inventarisasi source data (seeder/fixture/hardcode/mock), pemetaan alur data FE→BE→DB, query langsung DB, verifikasi API live terhadap DB, cross-check manual saldo/statistik.

## RINGKASAN EKSEKUTIF

Semua data yang tampil di aplikasi modern berasal dari **backend → database PostgreSQL**. Tidak ditemukan dummy/hardcode/fixture di kode aplikasi (`lib/`) yang dipakai untuk menampilkan data. Semua statistik dashboard (warga, saldo kas, sisa BOP, progress iuran) dihitung **di backend** (`/demographics/summary`, `/finances/summary`, `/bills/stats`, `/bop/summary`) dan dikonsumsi provider → UI.

Data testing yang ada di DB berasal dari **seed script eksplisit** (`seed-demo.js`, `seed-demo-lengkap.js`, `seed_dummy_inventory.js`) dan jejak pengujian manual (beberapa baris). Tidak ada data "tersembunyi" — semuanya dapat ditelusuri.

Status per komponen: lihat tabel di bawah.

## 1. SEEDER / INIT SCRIPT (backend-node/)
| Script | Isi data | Status | Fungsi | Risk | Rekomendasi |
|---|---|---|---|---|---|
| `init-db.js` | Schema + DB kosong | PASS | Init struktur DB | — | — |
| `seed-master.js` | menu, permissions, master (jenis_iuran/kategori_kas/bop), admin | PASS | Konfigurasi inti | — | — |
| `seed-demo.js` | 1 KK + 3 anggota + 3 bills + user warga demo | PASS (uji, bukan bug) | Alur pembayaran | Bila dijalankan di produksi menambah data demo | JANGAN jalan di produksi |
| `seed-demo-lengkap.js` | 6 KK baris² + anggota + bills + finances + surat + pengaduan + polling + dll (tipe demo) | PASS (uji) | Latihan semua modul | Ini sumber hampir semua data demo saat ini | Selektif; alternatif: gunakan `kosongkan-data.js` di produksi |
| `seed_dummy_inventory.js` | 10 item inventaris (kursi, tenda, dll) | PASS (uji) | Stok contoh | — | Jangan jalan di produksi |
| `kosongkan-data.js` | kosongkan operasional | PASS | Reset | — | — |

**Keputusan:** semua seeder eksplisit → data di DB asalnya dari sini (bukan AI/hardcode).

## 2. DATA SAAT INI DI DATABASE (per tabel, hanya >0 baris)
| Tabel | Baris | Status | Asal |
|---|---|---|---|
| role_permissions | 95 | PASS | seed-master (konfigurasi) |
| activity_logs | 76 | PASS | operasional (log) |
| anggota_keluarga | 36 | PASS | seed-demo-lengkap² |
| bills | 29 | PASS | seed-demo + seed-demo-lengkap + generate uji |
| menu_items | 19 | PASS | seed-master |
| users | 19 | PASS | seed-master (admin) + seed-demo + uji manual ("Uji Analisis") |
| finances | 18 | PASS | seed-demo-lengkap (11 iuran + 5 manual + 2 BOP?) |
| sensor_logs | 16 | PASS | seed-demo-lengkap (si sensor `[DEMO]`) |
| keluarga | 12 | PASS | seed-demo-lengkap (6 + 6 varian) |
| bill_payments | 11 | PASS | seed-demo-lengkap (11 pembayaran iuran) |
| bop_finances | 6 | PASS | seed-demo-lengkap |
| complaints | 6 | PASS | seed-demo-lengkap (5) + 1 uji (TKT20260809388) |
| polling | 2 | PASS | seed-demo-lengkap |
| polling_options | 6 | PASS | seed-demo-lengkap |
| visitors | 6 | PASS | seed-demo-lengkap |
| agenda | 5 | PASS | seed-demo-lengkap + 1 uji (Uji Audit A-EDIT) |
| jenis_iuran | 5 | PASS | seed-master |
| kategori_kas | 5 | PASS | seed-master |
| kategori_bop | 7 | PASS | seed-master |
| letters | 5 | PASS | seed-demo-lengkap |
| announcement | 4 | PASS | seed-demo-lengkap |
| bantuan_sosial | 4 | PASS | seed-demo-lengkap |
| borrowings | 4 | PASS | seed-demo-lengkap |
| polling_votes | 3 | PASS | seed-demo-lengkap (suara) |
| emergency_alerts | 2 | PASS | seed-demo-lengkap ([DEMO]) |
| alokasi_bop | 1 | PASS | seed-demo-lengkap |
| polling | 2 | PASS | seed-demo-lengkap |
| — (31 tabel total, 27 berisi) | | | |

**WARNA/TEMUAN penting di data:**
- **users**: 4 pengurus demo + admin + **1 user "Uji Analisis" (NIK 3578123456780001)** + 12 warga data (2 × 6 KK).
- **ganda no_kk**: dua set KK dengan nomor 10-digit dan 16-digit (contoh `3201990001` vs `3201990000000001`) — keduanya di DB, anggota berbeda; bukan duplikat.
- **complaints**: 1 tiket `TKT20260809388` "Uji komplain audit" — jejak uji manual audit lalu.
- **agenda**: 1 `"Uji Audit A-EDIT"` — jejak uji manual (audit ini sendiri / A-EDIT).

**Status rekomendasi:**
- Data demo (seed-demo/blengkap) = **PASS sebagai data uji** — memang untuk pengujian alur, tidak dianggap bug, TETAPI di produksi (Railway) TIDAK ADA data ini (DB produksi kosong operasional) — aman.
- Jejak uji manual ("Uji Analisis", "Uji Audit A-EDIT", "TKT20260809…") = **WARNING** (bukan bug, tapi merupakn jejak yang tidak perlu di produksi; di DB lokal hanya).

## 3. ALUR DATA FE → DB (dashboard/statistik/kartu/saldo/pagination)
| Komponen | Data dari | Endpoint | Status | Risk |
|---|---|---|---|---|
| Kartu TOTAL WARGA | `demografi.data.summary.totalWarga` | `GET /demographics/summary` | **PASS** | backend |
| Kartu SALDO KAS | `finance.summary.saldo` | `GET /finances/summary` | **PASS** | backend |
| Kartu SISA DANA BOP | `context.watch<BopProvider>().summary.sisaPagu` | `GET /bop/summary` | **PASS** | backend |
| Progress Iuran | `bills.statsBulanIni` (total/jumlahLunas) | `GET /bills/stats` | **PASS** | backend (komentar eksplisit: "hitungan BACKEND") |
| Statistik penduduk | `demographic.data....` | `GET /demographics/summary` | **PASS** | backend |
| Data Warga (list/tabel) | `WargaProvider` | `GET /warga` | **PASS** | backend |
| Semua tabel modul (agenda, surat, inventori, bansos, polling, dll) | provider → ApiService | endpoint masing | **PASS** | backend |
| Tabel responsif | `BarisTabel`/`SelTabel` (only rendering) | — | PASS (tidak data) | — |
| Saldo/status lain | provider → ApiService | endpoint masing-masing | **PASS** | backend |

- **Tidak ada dummy/hardcode data di `lib`** — beserdasarkan scan 30+ file: semua provider memakai `ApiService.get/post/put/delete`; UI membaca `provider.data` (dari JSON API).
- **Tidak ada fixture/factory** di `lib/test` yang masuk runtime (test saja).
- Satu-satunya List literal statis: `antrean_offline.dart` (daftar endpoint izin queue) — bukan data.

## 4. TEST FIXTURE / MOCK (frontend-flutter/test/)
| File | Isi | Status | Fungsi |
|---|---|---|---|
| `bantuan_uji.dart` | `semuaProvider()`, `bungkusLayar()`, `WsTanpaSambung` — provider apa adanya (ApiService) | PASS | scaffolding uji, tidak ada data statis |
| `widget_test.dart` | smoke test (tanpa token) | PASS | tidak ada mock data |
| `login_screen_test.dart` | ukuran layar | PASS | layout |
| `mobile_layout_test.dart` | 13 screen + dashboard | PASS | layout |
| `tabel_responsif_test.dart` | `contohBaris()` data contoh | PASS | HANYA test (tidak dipakai app) |
| `statistik_kartu_test.dart` | statistik kartu | PASS | test (tidak data app) |
| dll. | | | |
**Kesimpulan:** fixture test hanya untuk widget/test, bukan sumber data app.

## 5. Data dari AI / Generate
- Tidak ada data hasil generate AI di codebase (tidak ada file "generated" selain Flutter standard).
- Sebagian string deskripsi demo (`[DEMO] ...`) di seed-demo-lengkap ditulis manusia/manual, bukan data dari AI.

## 6. VERIFIKASI KONSISTENSI API vs DB (live)
| Metrik | API | DB (manual) | Banding |
|---|---|---|---|
| total_warga | 36 | 36 | COCOK |
| total_kk | 12 | 12 | COCOK |
| laki_laki / perempuan | 18 / 18 | L=18/P=18 | COCOK |
| saldo kas | 1.075.000 | 1.075.000 | COCOK |
| jumlah_transaksi | 18 | 18 | COCOK |
| total_tagihan 2026-08 | 17 | 17 (7@25rb+5@50rb+5) | COCOK |
| lunas / tunggakan | 1 / 16 | 1 / 16 | COCOK |

## 7. TEMUAN & STATUS
| # | Temuan | Status | Sumber data | File/lokasi | Jenis | Fungsi | Risiko | Rekomendasi |
|---|---|---|---|---|---|---|---|---|
| 1 | Data demo (seed) dipakai utk pengujian alur backend | **PASS** (fitur tersedia, bukan bug) | `seed-demo.js`, `seed-demo-lengkap.js`, `seed_dummy_inventory.js` | backend-node/ | Seeder | Uji alur | — | Jangan jalan di produksi; gunakan `kosongkan-data.js` |
| 2 | Semua dashboard/statistik/kartu/saldo/iuran dari **backend API** | **PASS** | `main_dashboard.dart`, provider | lib/screens/admin + providers | Backend | Data live | — | — |
| 3 | Tidak ada dummy/hardcode di UI | **PASS** | (scan 30+ file) | lib/ | — | — | — | — |
| 4 | Data uji manual tersisa di DB lokal: "Uji Analisis" (user), "Uji Audit A-EDIT" (agenda), "TKT20260809..." (komplain) | **WARNING** | DB (lokal) | — | Jejak uji | — | Penampilan data asing di demo | Hapus bila ingin bersih; bukan bug produksi |
| 5 | `bills` 2026-08 punya 1 lunas 50rb → saldo 1.075.000 konsisten | **PASS** | DB+API | — | — | — | — | — |
| 6 | Item inventaris `seed_dummy_inventory` (10 item) | **PASS** | script | — | Uji stok | — | — | — |
| 7 | Fixture/mock di test tidak dipakai di app | **PASS** | test/ | — | — | — | — | — |
| 8 | `antrean_offline.dart` allow-list (bukan data) | **PASS** | lib | — | — | — | — | — |

## KESIMPULAN
1. **Seluruh data yang tampil di aplikasi berasal dari PostgreSQL melalui backend** — tidak ada dummy/hardcode/fixture di UI.
2. Data demo/seeder adalah **uji** yang sah (bukan bug) — dimaksudkan utk menguji alur backend realistis. Di produksi (Railway) tidak ada data demo (hanya master/konfig).
3. Jejak uji manual kecil di DB **lokal** (Uji Analisis, agenda A-EDIT, tiket TKT2026..) = WARNING non-blokir, boleh dibersihkan kapan pun tanpa memengaruhi fungsional.
4. Semua metrik dashboard/statistik/saldo/pagination diambil langsung dari endpoint backend yang terhubung ke DB — konsisten & akurat.

**Rekomendasi aksi (opsional, tidak mengubah kode):** bersihkan 3-4 jejak uji manual di DB lokal (`Uji Analisis`, agenda "Uji Audit A-EDIT", komplain "Uji komplain audit", tiket TKT2026...) bila diinginkan; jangan jalankan seed-demo* di produksi.
