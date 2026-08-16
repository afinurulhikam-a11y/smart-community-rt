import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/models/emergency_model.dart';
import 'package:smart_community/providers/emergency_provider.dart';
import 'package:smart_community/screens/admin/status_darurat_screen.dart';
import 'package:smart_community/widgets/kartu_alarm_darurat.dart';

import 'bantuan_uji.dart';

/// Sinkronisasi keadaan darurat LINTAS LAYAR.
///
/// ===================================================================
/// Cacat yang dijaga berkas ini
/// ===================================================================
///
/// Kartu dasbor membaca `alarm_aktif`/`kejadian_aktif`, sedangkan Status
/// Darurat membaca `alerts`. Keduanya dari provider yang sama, tetapi tiap
/// mutasi dulu hanya menyegarkan separuhnya:
///
///   kendaliAlarm → hanya status  → riwayat basi
///   dismissAlarm → hanya riwayat → kartu dasbor MASIH "AKTIF"
///
/// Sehingga menyelesaikan darurat dari Status Darurat meninggalkan dasbor
/// menyala merah untuk kejadian yang sudah ditutup.
///
/// ===================================================================
/// Kenapa palsuannya meniru BACKEND, bukan menyetel getter
/// ===================================================================
///
/// Kalau setiap keadaan disetel langsung, ujinya hanya membuktikan widget bisa
/// menggambar keadaan yang diberikan — bukan bahwa keadaan itu SAMPAI ke sana
/// setelah sebuah aksi. Palsuan di bawah menyimpan satu "kejadian" seperti
/// database, dan `muatStatusAlarm`/`fetchAlerts` membacanya ulang. Jadi bila
/// sebuah mutasi lupa menyegarkan, uji ini gagal — persis seperti bug aslinya.
class _BackendPalsu {
  bool aktif = false;
  String? idKejadian;
  String pemilik = 'warga-1';
  String namaPemilik = 'Warga A';
  String keterangan = 'Kebakaran di dapur rumah nomor 12';

  /// Berapa kali status dibaca — untuk membuktikan penyegaran benar-benar
  /// terjadi, bukan kebetulan tertebak.
  int bacaStatus = 0;
  int bacaDaftar = 0;

  void nyalakan() {
    aktif = true;
    idKejadian = 'ev-1';
  }

  void selesaikan() {
    aktif = false;
  }
}

class _DaruratTersinkron extends EmergencyProvider {
  final _BackendPalsu backend;

  /// Bila diisi, aksi OFF gagal dengan pesan ini dan backend TIDAK berubah.
  final String? gagalOff;

  _DaruratTersinkron(this.backend, {this.gagalOff});

  bool _menyala = false;
  Map<String, dynamic>? _kejadian;
  List<EmergencyModel> _daftar = [];

  @override
  bool get alarmMenyala => _menyala;

  @override
  Map<String, dynamic>? get kejadianAktif => _kejadian;

  @override
  bool get bolehMatikan => _kejadian?['boleh_matikan'] == true;

  @override
  bool get daruratMilikOrangLain =>
      _kejadian != null && _kejadian!['milik_saya'] != true;

  @override
  String get namaPengaktif =>
      (_kejadian?['nama_pengaktif'] as String?) ?? 'Tidak diketahui';

  @override
  String get keteranganKejadian =>
      (_kejadian?['message'] as String?)?.trim() ?? '';

  @override
  String get keteranganKejadianTampil =>
      keteranganKejadian.isEmpty ? '' : keteranganUntukTampilan(keteranganKejadian);

  @override
  DateTime? get waktuKejadian => _menyala ? DateTime(2026, 8, 16, 16, 45) : null;

  @override
  List<EmergencyModel> get alerts => _daftar;

  @override
  bool get isLoading => false;

  /// Membaca status dari "backend" — inilah yang harus dipanggil ulang setelah
  /// setiap mutasi.
  @override
  Future<void> muatStatusAlarm() async {
    backend.bacaStatus++;
    _menyala = backend.aktif;
    _kejadian = backend.aktif
        ? {
            'emergency_id': backend.idKejadian,
            'user_id': backend.pemilik,
            'nama_pengaktif': backend.namaPemilik,
            'message': backend.keterangan,
            'milik_saya': backend.pemilik == 'warga-1',
            'boleh_matikan': backend.pemilik == 'warga-1',
          }
        : null;
    notifyListeners();
  }

  @override
  Future<void> fetchAlerts({String? status, int page = 1, int limit = 10}) async {
    backend.bacaDaftar++;
    _daftar = backend.idKejadian == null
        ? []
        : [
            EmergencyModel.fromJson({
              'id': backend.idKejadian,
              'user_id': backend.pemilik,
              'message': backend.keterangan,
              'status': backend.aktif ? 'active' : 'dismissed',
              'nama_warga': backend.namaPemilik,
              'alamat': 'Jl. Melati No. 12',
              'no_hp': '08123456789',
              'dismissed_by_nama': backend.aktif ? null : 'Ketua RT',
              'dismissed_at': backend.aktif ? null : '2026-08-16T10:20:00.000Z',
              'created_at': '2026-08-16T09:45:00.000Z',
            }),
          ];
    notifyListeners();
  }

  /// ON/OFF dari kartu dasbor. Memakai `segarkanDarurat()` yang sesungguhnya.
  @override
  Future<String?> kendaliAlarm(String aksi, String pin, {String? keterangan}) async {
    if (aksi == 'ON') {
      backend.nyalakan();
    } else {
      if (gagalOff != null) return gagalOff;
      backend.selesaikan();
    }
    await segarkanDarurat();
    return null;
  }

  /// Selesaikan dari layar Status Darurat. Juga lewat `segarkanDarurat()`.
  @override
  Future<bool> dismissAlarm(String alertId, {String? pin}) async {
    if (gagalOff != null) return false;
    backend.selesaikan();
    await segarkanDarurat();
    return true;
  }
}

Widget _bungkus(Widget layar, {required EmergencyProvider darurat, AuthService? auth}) {
  return MultiProvider(
    providers: [
      ...semuaProvider(),
      ChangeNotifierProvider<EmergencyProvider>.value(value: darurat),
      if (auth != null) ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: layar),
      ),
    ),
  );
}

/// Kedua layar dirender BERSAMAAN di atas satu provider — cara paling langsung
/// membuktikan keduanya membaca sumber yang sama.
Widget _bungkusDuaLayar(EmergencyProvider darurat, AuthService auth) {
  return MultiProvider(
    providers: [
      ...semuaProvider(),
      ChangeNotifierProvider<EmergencyProvider>.value(value: darurat),
      ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: const [
              KartuAlarmDarurat(),
              SizedBox(height: 16),
              StatusDaruratScreen(),
            ],
          ),
        ),
      ),
    ),
  );
}

AuthService _auth({String id = 'warga-1', String role = 'warga'}) {
  final a = AuthService();
  a.pasangUji(user: {'id': id, 'role': role, 'nama': 'Pengguna Uji'});
  return a;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('Sinkronisasi lintas layar', () {
    testWidgets('1 & 5. Dasbor NYALAKAN lalu MATIKAN — riwayat ikut berubah', (tester) async {
      final backend = _BackendPalsu();
      final p = _DaruratTersinkron(backend);

      await tester.pumpWidget(_bungkusDuaLayar(p, _auth()));
      await tester.pumpAndSettle();

      expect(find.text('SIAGA'), findsOneWidget);

      // --- NYALAKAN dari dasbor ---
      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Kebakaran di dapur rumah nomor 12');
      await tester.enterText(find.byType(TextField).at(1), '246810');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      // Skenario 1: kartu AKTIF dan riwayat menampilkan kejadian yang sama.
      expect(find.text('AKTIF'), findsOneWidget);
      expect(find.text('Aktif'), findsWidgets, reason: 'riwayat harus menunjukkan kejadian aktif');

      // --- MATIKAN dari dasbor (skenario 5) ---
      await tester.tap(find.text('MATIKAN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '246810');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Matikan'));
      await tester.pumpAndSettle();

      expect(find.text('SIAGA'), findsOneWidget, reason: 'kartu harus kembali SIAGA');
      expect(find.text('Selesai'), findsWidgets,
          reason: 'Status Darurat harus langsung menampilkan SELESAI tanpa buka ulang');
    });

    testWidgets('2 & 3. Selesaikan dari Status Darurat — kartu dasbor jadi SIAGA',
        (tester) async {
      final backend = _BackendPalsu()..nyalakan();
      final p = _DaruratTersinkron(backend);

      await tester.pumpWidget(_bungkusDuaLayar(p, _auth()));
      await tester.pumpAndSettle();

      // Berangkat dari keadaan aktif yang dibaca dari backend.
      expect(find.text('AKTIF'), findsOneWidget);
      expect(find.text('Kebakaran di dapur rumah nomor 12'), findsWidgets);

      // --- Selesaikan dari layar Status Darurat ---
      await tester.ensureVisible(find.text('Selesaikan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selesaikan'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '246810');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Selesaikan').last);
      await tester.pumpAndSettle();

      // Skenario 2 — INILAH bug aslinya: dulu tetap "AKTIF".
      expect(find.text('SIAGA'), findsOneWidget,
          reason: 'kartu dasbor harus SIAGA setelah kejadian ditutup dari layar lain');
      expect(find.text('AKTIF'), findsNothing);

      // Detail kejadian ikut hilang dari kartu.
      expect(find.text('Aktif oleh Warga A'), findsNothing);

      // Skenario 3 — daftar di layar yang sama menunjukkan SELESAI.
      expect(find.text('Selesai'), findsWidgets);

      // Tombol NYALAKAN tersedia lagi.
      expect(find.text('NYALAKAN'), findsOneWidget);
    });

    testWidgets('6. OFF gagal tidak mengubah keadaan menjadi selesai', (tester) async {
      final backend = _BackendPalsu()..nyalakan();
      final p = _DaruratTersinkron(
        backend,
        gagalOff: 'Darurat ini dinyalakan warga lain. Hanya pemiliknya atau Pengurus RT '
            'yang boleh mematikannya.',
      );

      await tester.pumpWidget(_bungkusDuaLayar(p, _auth()));
      await tester.pumpAndSettle();
      expect(find.text('AKTIF'), findsOneWidget);

      await tester.tap(find.text('MATIKAN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '246810');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Matikan'));
      await tester.pumpAndSettle();

      // Backend menolak → keadaan TETAP aktif di kedua layar.
      expect(backend.aktif, isTrue, reason: 'backend tidak boleh berubah saat aksi gagal');
      expect(find.text('AKTIF'), findsOneWidget,
          reason: 'penolakan tidak boleh membuat layar mengaku sudah selesai');
      expect(find.text('SIAGA'), findsNothing);
    });

    testWidgets('7. Membuka aplikasi setelah darurat selesai — keduanya SIAGA', (tester) async {
      // Backend tidak punya kejadian aktif sama sekali.
      final backend = _BackendPalsu();
      final p = _DaruratTersinkron(backend);

      await tester.pumpWidget(_bungkusDuaLayar(p, _auth()));
      await tester.pumpAndSettle();

      expect(find.text('SIAGA'), findsOneWidget);
      expect(find.text('AKTIF'), findsNothing);
      expect(p.kejadianAktif, isNull);
      expect(backend.bacaStatus, greaterThan(0),
          reason: 'kartu harus membaca status dari backend saat dibuka, bukan menebak SIAGA');
    });

    testWidgets('8. Darurat milik orang lain: tetap tampil AKTIF, tanpa tombol MATIKAN',
        (tester) async {
      final backend = _BackendPalsu()
        ..nyalakan()
        ..pemilik = 'warga-9'
        ..namaPemilik = 'Warga Lain';
      final p = _DaruratTersinkron(backend);

      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: p));
      await tester.pumpAndSettle();

      expect(find.text('AKTIF'), findsOneWidget, reason: 'status aktif tetap harus terlihat');
      expect(find.text('Aktif oleh Warga Lain'), findsOneWidget);
      expect(find.text('MATIKAN'), findsNothing,
          reason: 'boleh_matikan=false dari backend → tombol dihapus');
      expect(find.text('NYALAKAN'), findsOneWidget);
    });
  });

  group('Provider — mutasi menyegarkan status global', () {
    test('4. Membaca ulang keadaan mengambil status terbaru dari backend', () async {
      final backend = _BackendPalsu()..nyalakan();
      final p = _DaruratTersinkron(backend);

      await p.muatStatusAlarm();
      expect(p.alarmMenyala, isTrue);

      // Ditutup dari perangkat lain, tanpa aplikasi ini tahu.
      backend.selesaikan();
      expect(p.alarmMenyala, isTrue, reason: 'belum membaca ulang, keadaannya memang basi');

      // Inilah yang dilakukan `didChangeAppLifecycleState` saat resume.
      await p.muatStatusAlarm();
      expect(p.alarmMenyala, isFalse);
      expect(p.kejadianAktif, isNull);
    });

    test('segarkanDarurat membaca status DAN daftar sekali jalan', () async {
      final backend = _BackendPalsu()..nyalakan();
      final p = _DaruratTersinkron(backend);

      backend.bacaStatus = 0;
      backend.bacaDaftar = 0;

      await p.segarkanDarurat();

      expect(backend.bacaStatus, 1, reason: 'status wajib dibaca ulang');
      expect(backend.bacaDaftar, 1, reason: 'daftar wajib dibaca ulang');
    });

    test('Setiap mutasi menyegarkan KEDUA bagian keadaan', () async {
      final backend = _BackendPalsu();
      final p = _DaruratTersinkron(backend);

      // ON dari dasbor.
      backend.bacaStatus = 0;
      backend.bacaDaftar = 0;
      await p.kendaliAlarm('ON', '246810', keterangan: 'Kebakaran di dapur');
      expect(backend.bacaStatus, 1, reason: 'ON harus menyegarkan status');
      expect(backend.bacaDaftar, 1, reason: 'ON harus menyegarkan riwayat');
      expect(p.alarmMenyala, isTrue);

      // Selesaikan dari Status Darurat — jalur yang dulu melupakan status.
      backend.bacaStatus = 0;
      backend.bacaDaftar = 0;
      await p.dismissAlarm('ev-1', pin: '246810');
      expect(backend.bacaStatus, 1, reason: 'Selesaikan harus menyegarkan status juga');
      expect(backend.bacaDaftar, 1);
      expect(p.alarmMenyala, isFalse, reason: 'kartu dasbor harus ikut padam');
      expect(p.kejadianAktif, isNull);
    });

    test('Filter daftar dipertahankan saat disegarkan setelah mutasi', () async {
      final backend = _BackendPalsu()..nyalakan();
      final p = _DaruratTersinkron(backend);

      // Layar sedang memfilter "Aktif" pada halaman 1.
      await p.fetchAlerts(status: 'active', page: 1, limit: 10);

      await p.segarkanDarurat();

      // Filter tidak boleh hilang setelah penyegaran, kalau tidak layar
      // mendadak menampilkan kejadian di luar filter yang sedang dipakai.
      expect(p.currentPage, 1);
      expect(p.perPage, 10);
    });
  });
}
