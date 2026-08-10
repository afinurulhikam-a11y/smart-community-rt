import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/core/services/websocket_service.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/agenda_provider.dart';
import 'package:smart_community/providers/aksi_utama_provider.dart';
import 'package:smart_community/providers/tema_provider.dart';
import 'package:smart_community/providers/alokasi_bop_provider.dart';
import 'package:smart_community/providers/announcement_provider.dart';
import 'package:smart_community/providers/bantuan_sosial_provider.dart';
import 'package:smart_community/providers/bill_provider.dart';
import 'package:smart_community/providers/bop_provider.dart';
import 'package:smart_community/providers/complaint_provider.dart';
import 'package:smart_community/providers/demographic_provider.dart';
import 'package:smart_community/providers/emergency_provider.dart';
import 'package:smart_community/providers/family_provider.dart';
import 'package:smart_community/providers/finance_provider.dart';
import 'package:smart_community/providers/inventory_provider.dart';
import 'package:smart_community/providers/jenis_iuran_provider.dart';
import 'package:smart_community/providers/meteran_provider.dart';
import 'package:smart_community/providers/kategori_bop_provider.dart';
import 'package:smart_community/providers/kategori_kas_provider.dart';
import 'package:smart_community/providers/letter_provider.dart';
import 'package:smart_community/providers/log_provider.dart';
import 'package:smart_community/providers/payment_provider.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/providers/polling_provider.dart';
import 'package:smart_community/providers/reset_provider.dart';
import 'package:smart_community/providers/visitor_provider.dart';
import 'package:smart_community/providers/warga_provider.dart';
import 'package:smart_community/providers/koneksi_provider.dart';
import 'package:smart_community/screens/admin/main_dashboard.dart';

/// Perkakas bersama untuk pengujian widget.

/// WebSocket tiruan yang tidak pernah menyambung.
///
/// `MainDashboard` memanggil `connect()` saat dibuka. Di lingkungan pengujian
/// tidak ada server, dan kegagalannya menjadwalkan timer sambung-ulang 5 detik
/// — SETELAH frame selesai, jadi membubarkan servisnya pun tidak menolong dan
/// pengujian gagal dengan "Pending timers" alih-alih menyoal hal yang diuji.
class WsTanpaSambung extends WebSocketService {
  @override
  void connect() {}
}

/// Seluruh provider aplikasi, dalam keadaan kosong.
///
/// Tidak ada backend saat pengujian, jadi setiap provider tetap pada nilai
/// awalnya — itu justru keadaan yang ingin diuji.
List<SingleChildWidget> semuaProvider() => [
  // Wajib ada: MainDashboard membaca provider ini saat tombol mode gelap
  // ditekan. Tanpa ia terdaftar, uji gagal dengan ProviderNotFoundException —
  // bukan karena tata letaknya, melainkan karena kerangkanya kurang.
  ChangeNotifierProvider(create: (_) => TemaProvider()),
  // `pantau: false` — berlangganan connectivity_plus dan membuka SQLite
  // menuntut plugin yang tidak ada di lingkungan uji widget, dan langganan
  // yang tertinggal membuat uji gagal karena "pending timers" alih-alih
  // karena hal yang sedang diuji. Sama seperti WsTanpaSambung di bawah.
  ChangeNotifierProvider(create: (_) => KoneksiProvider(pantau: false)),
  ChangeNotifierProvider(create: (_) => AuthService()),
  ChangeNotifierProvider(create: (_) => PermissionProvider()),
  ChangeNotifierProvider<WebSocketService>(create: (_) => WsTanpaSambung()),
  ChangeNotifierProvider(create: (_) => BillProvider()),
  ChangeNotifierProvider(create: (_) => JenisIuranProvider()),
  ChangeNotifierProvider(create: (_) => MeteranProvider()),
  ChangeNotifierProvider(create: (_) => KategoriKasProvider()),
  ChangeNotifierProvider(create: (_) => KategoriBopProvider()),
  ChangeNotifierProvider(create: (_) => AlokasiBopProvider()),
  ChangeNotifierProvider(create: (_) => FinanceProvider()),
  ChangeNotifierProvider(create: (_) => BopProvider()),
  ChangeNotifierProvider(create: (_) => LetterProvider()),
  ChangeNotifierProvider(create: (_) => EmergencyProvider()),
  ChangeNotifierProvider(create: (_) => DemographicProvider()),
  ChangeNotifierProvider(create: (_) => AnnouncementProvider()),
  ChangeNotifierProvider(create: (_) => ComplaintProvider()),
  ChangeNotifierProvider(create: (_) => AgendaProvider()),
  ChangeNotifierProvider(create: (_) => PollingProvider()),
  ChangeNotifierProvider(create: (_) => VisitorProvider()),
  ChangeNotifierProvider(create: (_) => BantuanSosialProvider()),
  ChangeNotifierProvider(create: (_) => InventoryProvider()),
  ChangeNotifierProvider(create: (_) => FamilyProvider()),
  ChangeNotifierProvider(create: (_) => WargaProvider()),
  ChangeNotifierProvider(create: (_) => LogProvider()),
  ChangeNotifierProvider(create: (_) => ResetProvider()),
  ChangeNotifierProvider(create: (_) => PaymentProvider()),
  ChangeNotifierProvider(create: (_) => AksiUtamaProvider()),
];

/// Satu kondisi perangkat yang ingin ditiru.
///
/// Ukuran layar bukan satu-satunya hal yang membedakan ponsel dari Chrome, dan
/// justru yang BUKAN ukuran itulah yang meloloskan cacat sampai ke perangkat:
/// aplikasi ini dikembangkan sambil diuji di web, lalu berantakan begitu dibuka
/// di HP Android.
class KondisiPerangkat {
  final String nama;
  final Size ukuran;

  /// Poni kamera / bilah status di atas, bilah gestur di bawah.
  ///
  /// Inilah yang membuat widget tanpa `SafeArea` tertutup takik. Bug logo
  /// "AUTO RT" tertimpa kamera lolos dari 105 pengujian justru karena tidak
  /// satu pun menyetel nilai ini.
  final double poniAtas;
  final double gesturBawah;

  /// Penskalaan font sistem Android.
  ///
  /// 1,0 = bawaan, 1,3 = setelan "Besar" yang lazim dipakai orang. Semua teks
  /// ikut membesar, sehingga kotak berukuran tinggi TETAP akan terpotong —
  /// penyebab jebolnya tata letak yang paling sering dan paling tak terlihat
  /// di Chrome.
  final double skalaFont;

  const KondisiPerangkat({
    required this.nama,
    required this.ukuran,
    this.poniAtas = 0,
    this.gesturBawah = 0,
    this.skalaFont = 1.0,
  });
}

/// Kondisi yang diuji untuk setiap layar.
///
/// Tiga yang pertama meniru Chrome (hanya ukuran), dua terakhir meniru HP
/// Android sungguhan. Memisahkannya begini membuat kegagalan langsung terbaca:
/// "gagal pada ponsel umum + poni + font 1,3x" jauh lebih menunjuk daripada
/// sekadar "gagal pada 360px".
const List<KondisiPerangkat> kondisiUji = [
  KondisiPerangkat(nama: 'ponsel kecil (320x568)', ukuran: Size(320, 568)),
  KondisiPerangkat(nama: 'ponsel umum (360x800)', ukuran: Size(360, 800)),
  KondisiPerangkat(nama: 'ponsel besar (412x915)', ukuran: Size(412, 915)),
  KondisiPerangkat(nama: 'tablet (800x1280)', ukuran: Size(800, 1280)),
  KondisiPerangkat(nama: 'desktop (1440x900)', ukuran: Size(1440, 900)),

  // Meniru RMX2001 milik pengguna: berponi, berbilah gestur, dan dipakai
  // dengan font sistem diperbesar.
  KondisiPerangkat(
    nama: 'HP berponi (360x800 + poni)',
    ukuran: Size(360, 800),
    poniAtas: 48,
    gesturBawah: 24,
  ),
  KondisiPerangkat(
    nama: 'HP berponi + font besar 1,3x',
    ukuran: Size(360, 800),
    poniAtas: 48,
    gesturBawah: 24,
    skalaFont: 1.3,
  ),
];

/// Pasang kondisi perangkat pada tester.
///
/// `padding` diberi nilai lewat `FakeViewPadding`; itulah yang dibaca
/// `MediaQuery.padding`, dan dari sanalah `SafeArea` tahu berapa banyak ruang
/// yang harus dihindari.
void pasangKondisi(WidgetTester tester, KondisiPerangkat k) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = k.ukuran;
  tester.view.padding = FakeViewPadding(top: k.poniAtas, bottom: k.gesturBawah);
  tester.view.viewPadding = FakeViewPadding(top: k.poniAtas, bottom: k.gesturBawah);
  addTearDown(tester.view.reset);
}

/// Menerapkan penskalaan font ke seluruh pohon widget.
///
/// Lewat `MaterialApp.builder` supaya berlaku juga pada dialog dan lembar
/// bawah, yang dirender di luar `home`.
Widget Function(BuildContext, Widget?) _pembungkusSkala(double skala) {
  return (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(skala)),
    child: child!,
  );
}

/// Pembungkus untuk layar modul, yang berupa widget biasa (bukan Scaffold).
///
/// [gelap] merender layar dalam tema gelap. Ini bukan sekadar kelengkapan:
/// mode gelap dulu rusak justru karena tidak ada satu pun uji yang pernah
/// merender apa pun dalam tema gelap.
Widget bungkusLayar(Widget layar, {double skalaFont = 1.0, bool gelap = false}) {
  return MultiProvider(
    providers: semuaProvider(),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: gelap ? ThemeMode.dark : ThemeMode.light,
      builder: _pembungkusSkala(skalaFont),
      home: Scaffold(
        // Meniru kerangka MainDashboard: konten berada di dalam scroll
        // vertikal. Itu penting — beberapa cacat tata letak hanya muncul
        // ketika tinggi induknya tak terbatas.
        //
        // SafeArea juga ikut, persis seperti Scaffold sungguhan yang
        // ber-AppBar: tanpa ini poni tidak berpengaruh apa-apa dan
        // pengujiannya jadi bohong.
        body: SafeArea(
          child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: layar),
        ),
      ),
    ),
  );
}

/// Pembungkus untuk MainDashboard, yang membawa Scaffold-nya sendiri.
Widget bungkusDasbor({double skalaFont = 1.0, bool gelap = false}) {
  return MultiProvider(
    providers: semuaProvider(),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: gelap ? ThemeMode.dark : ThemeMode.light,
      builder: _pembungkusSkala(skalaFont),
      home: const MainDashboard(),
    ),
  );
}
