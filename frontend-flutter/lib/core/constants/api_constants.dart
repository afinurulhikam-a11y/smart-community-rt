import 'package:flutter/foundation.dart';

class ApiConstants {
  /// Alamat backend LENGKAP — dipakai untuk tunnel (ngrok, Cloudflare) atau
  /// server yang sudah dideploy:
  ///
  ///     flutter run --dart-define=API_BASE_URL=https://abc123.ngrok-free.app
  ///
  /// Ini yang membuat aplikasi bisa diuji dari luar jaringan rumah. Sebelumnya
  /// hanya bagian host yang bisa diganti sementara `http://` dan `:3001`
  /// ditulis mati, sehingga alamat ngrok akan berubah menjadi
  /// `http://abc123.ngrok-free.app:3001` — salah protokol DAN salah port.
  static const String _baseOverride = String.fromEnvironment('API_BASE_URL');

  /// Hanya bagian host, untuk pemakaian di jaringan lokal:
  ///
  ///     flutter run --dart-define=API_HOST=192.168.1.10
  ///
  /// Bentuk `http://<host>:3001` tetap dipakai, jadi ini lebih ringkas
  /// dibanding menulis alamat penuh saat menguji di LAN.
  static const String _hostOverride = String.fromEnvironment('API_HOST');

  /// IP LAN PC pengembang, dipakai bila tidak ada override sama sekali.
  ///
  /// Nilai ini PASTI basi cepat atau lambat karena IP dari DHCP berganti —
  /// karena itu jangan diandalkan; pakai --dart-define di atas.
  static const String _hostBawaan = '192.168.50.85';
  static const int _portBawaan = 3001;

  /// Skema + host (+ port), tanpa akhiran `/api`.
  static String get _origin {
    if (_baseOverride.isNotEmpty) {
      var s = _baseOverride.trim();
      // Toleran terhadap cara orang menempelkan alamat: garis miring di
      // ujung, atau `/api` yang ikut tersalin dari dokumentasi.
      while (s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
      if (s.endsWith('/api')) s = s.substring(0, s.length - 4);
      return s;
    }

    // Jika di-build untuk Release (Deploy Vercel / APK Production)
    if (kReleaseMode) {
      return 'https://smart-community-rt-production.up.railway.app';
    }

    final host = _hostOverride.isNotEmpty
        ? _hostOverride
        // Flutter Web berjalan di mesin yang sama dengan backend saat dev lokal.
        : (kIsWeb ? 'localhost' : _hostBawaan);
    return 'http://$host:$_portBawaan';
  }

  static String get baseUrl => '$_origin/api';

  /// WebSocket mengikuti skema HTTP-nya: https wajib berpasangan dengan wss,
  /// dan tunnel seperti ngrok selalu HTTPS. Menyambung ke `ws://` dari halaman
  /// HTTPS akan ditolak, dan panic button diam-diam tidak berfungsi.
  static String get wsUrl {
    final o = _origin;
    if (o.startsWith('https://')) return 'wss://${o.substring(8)}';
    if (o.startsWith('http://')) return 'ws://${o.substring(7)}';
    return o;
  }

  /// Ditampilkan di layar Profil untuk memudahkan memastikan aplikasi menunjuk
  /// ke backend yang benar saat menguji dari beberapa jaringan.
  static String get alamatAktif => _origin;

  // Auth
  static String get login => '$baseUrl/auth/login';
  static String get register => '$baseUrl/auth/register';
  static String get me => '$baseUrl/auth/me';
  static String get updateProfile => '$baseUrl/auth/profile';
  static String get changePassword => '$baseUrl/auth/change-password';

  // Users
  static String get users => '$baseUrl/users';
  static String user(String id) => '$baseUrl/users/$id';
  static String userByNik(String nik) => '$baseUrl/users/by-nik/$nik';
  static String get userCredentials => '$baseUrl/users/credentials';
  static String get pendingUsers => '$baseUrl/users/pending';
  static String userStatus(String id) => '$baseUrl/users/$id/status';
  static String userRole(String id) => '$baseUrl/users/$id/role';

  // System Activity Logs
  static String get activityLogs => '$baseUrl/activity-logs';

  // Reset Sistem — seluruhnya khusus admin
  static String get resetRingkasan => '$baseUrl/reset/ringkasan';
  static String get resetPratinjau => '$baseUrl/reset/pratinjau';
  static String get resetCadangan => '$baseUrl/reset/cadangan';
  static String get resetEksekusi => '$baseUrl/reset/eksekusi';
  static String get resetRiwayat => '$baseUrl/reset/riwayat';

  // Menu & Hak Akses per Role
  static String get menuAkses => '$baseUrl/menu-akses';
  static String get menuAksesSaya => '$baseUrl/menu-akses/me';
  static String get menuAksesReset => '$baseUrl/menu-akses/reset';
  static String menuAktif(String kode) => '$baseUrl/menu-akses/menu/$kode/aktif';

  // Bills (Iuran Warga) — tagihan melekat pada kartu keluarga sejak migrasi v6
  static String get bills => '$baseUrl/bills';
  static String get billStats => '$baseUrl/bills/stats';
  static String get billExport => '$baseUrl/bills/export';
  static String get billsGenerate => '$baseUrl/bills/generate';
  static String get billsPayBulk => '$baseUrl/bills/pay-bulk';
  static String get billsTagihWa => '$baseUrl/bills/tagih-wa';
  static String payBill(String id) => '$baseUrl/bills/$id/pay';
  static String billReceipt(String id) => '$baseUrl/bills/$id/receipt';
  static String bill(String id) => '$baseUrl/bills/$id';

  // Pembayaran iuran lewat Midtrans
  static String get payMulai => '$baseUrl/payments/iuran';
  static String get payRiwayat => '$baseUrl/payments/riwayat';
  static String payStatus(String orderId) => '$baseUrl/payments/$orderId/status';
  static String payBatal(String orderId) => '$baseUrl/payments/$orderId/batal';
  // `paySimulasiLunas` dihapus — endpoint-nya sudah tidak ada di backend.
  // Lihat komentar di payment.routes.js untuk alasannya.

  // Master Jenis Iuran
  static String get jenisIuran => '$baseUrl/jenis-iuran';
  static String jenisIuranById(int id) => '$baseUrl/jenis-iuran/$id';

  // Finances (Kas RT)
  static String get finances => '$baseUrl/finances';
  static String get financeSummary => '$baseUrl/finances/summary';
  static String get financeBulanan => '$baseUrl/finances/bulanan';
  static String get financeExport => '$baseUrl/finances/export';
  static String finance(String id) => '$baseUrl/finances/$id';

  // Master Kategori Kas
  static String get kategoriKas => '$baseUrl/kategori-kas';
  static String kategoriKasById(int id) => '$baseUrl/kategori-kas/$id';

  // BOP
  static String get bop => '$baseUrl/bop';
  static String get bopSummary => '$baseUrl/bop/summary';
  static String get bopBulanan => '$baseUrl/bop/bulanan';
  static String get bopExport => '$baseUrl/bop/export';
  static String bopById(String id) => '$baseUrl/bop/$id';

  // Master Kategori BOP & Alokasi (pagu) BOP
  static String get kategoriBop => '$baseUrl/kategori-bop';
  static String kategoriBopById(int id) => '$baseUrl/kategori-bop/$id';
  static String get alokasiBop => '$baseUrl/alokasi-bop';
  static String alokasiBopById(int id) => '$baseUrl/alokasi-bop/$id';

  // Letters
  static String get letters => '$baseUrl/letters';
  static String approveLetter(String id) => '$baseUrl/letters/$id/approve';

  // Emergency
  static String get emergencyTrigger => '$baseUrl/emergency/trigger';
  static String emergencyDismiss(String id) => '$baseUrl/emergency/dismiss/$id';
  static String get emergencyAlerts => '$baseUrl/emergency/alerts';
  static String get emergencyActive => '$baseUrl/emergency/active';

  // Sensors
  static String get sensorLogs => '$baseUrl/sensors/logs';
  static String get sensorLatest => '$baseUrl/sensors/latest';

  // Demographics
  static String get demographicsSummary => '$baseUrl/demographics/summary';

  // Announcements (Pengumuman)
  static String get announcements => '$baseUrl/announcements';

  // Complaints (Pengaduan)
  static String get complaints => '$baseUrl/complaints';
  static String complaintStatus(int id) => '$baseUrl/complaints/$id/status';

  // Agenda (Kegiatan)
  static String get agenda => '$baseUrl/agenda';

  // Polling
  static String get polling => '$baseUrl/polling';
  static String pollingVote(int id) => '$baseUrl/polling/$id/vote';
  static String pollingStatus(int id) => '$baseUrl/polling/$id/status';

  // Visitors (E-Visitor)
  static String get visitors => '$baseUrl/visitors';
  static String get visitorStats => '$baseUrl/visitors/stats';
  static String visitorCheckout(int id) => '$baseUrl/visitors/$id/checkout';

  // Bantuan Sosial
  static String get bantuanSosial => '$baseUrl/bantuan-sosial';
  static String get bantuanSosialStats => '$baseUrl/bantuan-sosial/stats';

  // Inventory (Data Barang) & Peminjaman
  static String get inventory => '$baseUrl/inventory';
  static String get inventoryStats => '$baseUrl/inventory/stats';
  static String get inventoryExport => '$baseUrl/inventory/export';
  static String inventoryById(int id) => '$baseUrl/inventory/$id';
  static String get borrowings => '$baseUrl/inventory/borrowings';
  // Dijaga izin peminjaman, bukan izin barang — supaya warga bisa memilih
  // barang di form pinjam tanpa diberi akses ke daftar inventaris.
  static String get barangTersedia => '$baseUrl/inventory/borrowings/barang-tersedia';
  static String get borrowingStats => '$baseUrl/inventory/borrowings/stats';
  static String get borrowingExport => '$baseUrl/inventory/borrowings/export';
  static String borrowingById(int id) => '$baseUrl/inventory/borrowings/$id';
  static String returnBorrowing(int id) => '$baseUrl/inventory/borrowings/$id/return';

  // Families (Kartu Keluarga) & Warga
  static String get families => '$baseUrl/families';
  static String get warga => '$baseUrl/warga';

  // Siskamling (Jadwal Ronda & Absensi Pos Ronda)
  static String get patrolSchedules => '$baseUrl/patrol/schedules';
  static String get patrolAttendances => '$baseUrl/patrol/attendances';
  static String get patrolQr => '$baseUrl/patrol/qr';
  static String get patrolQrRegenerate => '$baseUrl/patrol/qr/regenerate';
}
