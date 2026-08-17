import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/core/services/websocket_service.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/models/emergency_model.dart';
import 'package:smart_community/providers/emergency_provider.dart';
import 'package:smart_community/screens/admin/status_darurat_screen.dart';
import 'package:smart_community/widgets/kartu_alarm_darurat.dart';

import 'bantuan_uji.dart';

/// Sinkronisasi darurat LINTAS PERANGKAT lewat siaran WebSocket.
///
/// Yang diuji di sini bukan soketnya, melainkan perkabelannya: ketika siaran
/// `ALARM_ON`/`ALARM_OFF` tiba dari perangkat lain, apakah `EmergencyProvider`
/// membaca ulang keadaan — dan apakah ia berhenti membaca ketika tidak ada yang
/// benar-benar berubah.

/// WebSocket tiruan yang tidak pernah menyambung, tetapi bisa "menerima" siaran.
///
/// Mewarisi [WebSocketService] supaya tipe yang dibaca provider tetap sama,
/// dan menimpa `connect()` agar tidak ada soket sungguhan maupun timer
/// reconnect yang tertinggal — timer yang menggantung membuat uji widget gagal
/// pada "pending timers" alih-alih pada hal yang sedang diuji.
class _WsPalsu extends WebSocketService {
  Map<String, dynamic>? _alarm;
  bool _sambung = false;

  /// Riwayat pesan, terbaru di depan — persis seperti `WebSocketService`
  /// sungguhan yang memakai `insert(0, ...)`.
  final List<Map<String, dynamic>> _pesan = [];

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  bool get isConnected => _sambung;

  @override
  Map<String, dynamic>? get lastAlarm => _alarm;

  @override
  List<Map<String, dynamic>> get messages => List.unmodifiable(_pesan);

  /// Meniru pesan masuk. Bentuknya sama dengan yang disiarkan backend, dan
  /// pembaruannya mengikuti urutan yang sama: catat pesannya, lalu perbarui
  /// `lastAlarm`.
  void terimaSiaran(Map<String, dynamic> pesan) {
    _pesan.insert(0, pesan);
    if (pesan['type'] == 'ALARM_ON') {
      _alarm = pesan;
    } else if (pesan['type'] == 'ALARM_OFF') {
      _alarm = null;
    }
    notifyListeners();
  }

  /// Meniru perubahan koneksi tanpa pesan apa pun.
  void setTersambung(bool nilai) {
    _sambung = nilai;
    notifyListeners();
  }

  /// Meniru pesan yang BUKAN tentang darurat.
  void siaranLain() => notifyListeners();

  /// `hasListeners` bersifat protected, jadi hanya bisa dibuka dari dalam
  /// subkelasnya. Dipakai uji untuk membuktikan tidak ada pendengar yang
  /// tertinggal — kebocoran yang tidak akan terlihat dari perilaku layar.
  bool get adaPendengar => hasListeners;
}

/// Provider yang membaca "backend" tiruan dan menghitung pembacaannya.
class _DaruratTerhitung extends EmergencyProvider {
  bool aktifDiBackend = false;
  String idKejadian = 'ev-1';

  int jumlahSegarkan = 0;

  bool _menyala = false;
  Map<String, dynamic>? _kejadian;
  List<EmergencyModel> _daftar = [];

  @override
  bool get alarmMenyala => _menyala;

  @override
  Map<String, dynamic>? get kejadianAktif => _kejadian;

  @override
  bool get bolehMatikan => _kejadian != null;

  @override
  bool get daruratMilikOrangLain => false;

  @override
  String get namaPengaktif => 'Warga A';

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

  @override
  Future<void> segarkanDarurat() async {
    jumlahSegarkan++;
    await muatStatusAlarm();
    await fetchAlerts();
  }

  @override
  Future<void> muatStatusAlarm() async {
    _menyala = aktifDiBackend;
    _kejadian = aktifDiBackend
        ? {
            'emergency_id': idKejadian,
            'nama_pengaktif': 'Warga A',
            'message': 'Kebakaran di dapur rumah nomor 12',
            'milik_saya': true,
            'boleh_matikan': true,
          }
        : null;
    notifyListeners();
  }

  @override
  Future<void> fetchAlerts({String? status, int page = 1, int limit = 10, bool silent = false}) async {
    _daftar = [
      EmergencyModel.fromJson({
        'id': idKejadian,
        'user_id': 'warga-1',
        'message': 'Kebakaran di dapur rumah nomor 12',
        'status': aktifDiBackend ? 'active' : 'dismissed',
        'nama_warga': 'Warga A',
        'alamat': 'Jl. Melati No. 12',
        'no_hp': '08123456789',
        'dismissed_by_nama': aktifDiBackend ? null : 'Ketua RT',
        'dismissed_at': aktifDiBackend ? null : '2026-08-16T10:20:00.000Z',
        'created_at': '2026-08-16T09:45:00.000Z',
      }),
    ];
    notifyListeners();
  }
}

AuthService _auth() {
  final a = AuthService();
  a.pasangUji(user: {'id': 'warga-1', 'role': 'warga', 'nama': 'Pengguna Uji'});
  return a;
}

Widget _bungkusDuaLayar(EmergencyProvider darurat, WebSocketService ws) {
  return MultiProvider(
    providers: [
      ...semuaProvider(),
      ChangeNotifierProvider<EmergencyProvider>.value(value: darurat),
      ChangeNotifierProvider<WebSocketService>.value(value: ws),
      ChangeNotifierProvider<AuthService>.value(value: _auth()),
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

const _pesanOn = {
  'type': 'ALARM_ON',
  'event': 'emergency_alert',
  'alert_id': 'ev-1',
  'nama': 'Warga A',
};

const _pesanOff = {
  'type': 'ALARM_OFF',
  'event': 'emergency_dismissed',
  'alert_id': 'ev-1',
};

/// Muatan PERSIS seperti yang kini dikirim `nyalakanDarurat`
/// (`POST /emergency/alarm` aksi ON) sesudah COMMIT.
const _pesanOnDasbor = {
  'type': 'ALARM_ON',
  'event': 'emergency_alert',
  'alert_id': 'ev-1',
  'user_id': 'warga-1',
  'nama': 'Warga A',
  'no_hp': '-',
  'alamat': '-',
  'message': 'Kebakaran di dapur rumah nomor 12',
  'timestamp': '2026-08-16T09:45:00.000Z',
};

/// Muatan PERSIS seperti yang kini dikirim `matikanDarurat` (aksi OFF).
const _pesanOffDasbor = {
  'type': 'ALARM_OFF',
  'event': 'emergency_dismissed',
  'alert_id': 'ev-1',
  'dismissed_by': 'pengurus-1',
  'dismissed_by_nama': 'Ketua RT',
  'timestamp': '2026-08-16T10:20:00.000Z',
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('Siaran WebSocket memicu pembacaan ulang', () {
    test('ALARM_ON dari perangkat lain menyegarkan keadaan', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung();
      p.pasangSumberRealtime(ws);

      p.aktifDiBackend = true;
      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 1);
      expect(p.alarmMenyala, isTrue);
    });

    test('ALARM_OFF dari perangkat lain menyegarkan keadaan', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);
      expect(p.alarmMenyala, isTrue);

      // Ditutup dari perangkat lain.
      p.aktifDiBackend = false;
      ws.terimaSiaran(_pesanOff);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 2);
      expect(p.alarmMenyala, isFalse);
      expect(p.kejadianAktif, isNull);
    });

    test('Siaran ganda untuk kejadian yang sama TIDAK menyegarkan berulang', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOn);
      ws.terimaSiaran(_pesanOn);
      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);

      // Tiga siaran identik → satu penyegaran. Tiap penyegaran berarti dua
      // permintaan HTTP; tanpa penyaringan ini, satu rentetan siaran akan
      // membanjiri backend.
      expect(p.jumlahSegarkan, 1);
    });

    test('ALARM_OFF ganda juga hanya sekali', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOn);
      p.aktifDiBackend = false;
      ws.terimaSiaran(_pesanOff);
      ws.terimaSiaran(_pesanOff);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 2, reason: 'ON sekali + OFF sekali');
    });

    test('Pesan WebSocket yang bukan darurat tidak menyegarkan apa pun', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung();
      p.pasangSumberRealtime(ws);

      ws.siaranLain();
      ws.siaranLain();
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 0);
    });

    test('Tersambung kembali memicu pembacaan ulang sekali', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung();
      p.pasangSumberRealtime(ws);

      // Putus — tidak ada gunanya menembakkan permintaan saat jaringan mati.
      ws.setTersambung(false);
      await Future<void>.delayed(Duration.zero);
      expect(p.jumlahSegarkan, 0);

      // Tersambung lagi: selama putus, siaran apa pun hilang tanpa jejak, jadi
      // keadaan di layar tidak bisa dipercaya lagi.
      ws.setTersambung(true);
      await Future<void>.delayed(Duration.zero);
      expect(p.jumlahSegarkan, 1);

      // Notifikasi lain saat sudah tersambung tidak menambah penyegaran.
      ws.siaranLain();
      await Future<void>.delayed(Duration.zero);
      expect(p.jumlahSegarkan, 1);
    });
  });

  group('Siaran dari TOMBOL DASBOR perangkat lain', () {
    // Sampai perbaikan backend terakhir, `POST /emergency/alarm` sama sekali
    // tidak menyiarkan — sehingga menyalakan alarm dari dasbor satu ponsel
    // tidak terlihat di ponsel lain. Muatan di bawah adalah bentuk yang kini
    // benar-benar dikirim kedua jalur itu.

    test('ALARM_ON dari dasbor perangkat lain menyegarkan sekali', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung();
      p.pasangSumberRealtime(ws);

      p.aktifDiBackend = true;
      ws.terimaSiaran(_pesanOnDasbor);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 1);
      expect(p.alarmMenyala, isTrue);
    });

    test('ALARM_OFF dari dasbor perangkat lain menyegarkan sekali', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOnDasbor);
      await Future<void>.delayed(Duration.zero);

      p.aktifDiBackend = false;
      ws.terimaSiaran(_pesanOffDasbor);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 2);
      expect(p.alarmMenyala, isFalse);
      expect(p.kejadianAktif, isNull);
    });

    test('ON dasbor berulang untuk kejadian sama hanya sekali menyegarkan', () async {
      // Backend menembakkan siaran juga pada penekanan berulang, supaya
      // perangkat yang melewatkan siaran pertama tetap menyusul. Perangkat
      // yang SUDAH menerimanya menyaring sendiri lewat alert_id.
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOnDasbor);
      ws.terimaSiaran(_pesanOnDasbor);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 1);
    });

    testWidgets('Kedua layar mengikuti ALARM_OFF dari tombol dasbor perangkat lain',
        (tester) async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      await tester.pumpWidget(_bungkusDuaLayar(p, ws));
      await tester.pumpAndSettle();
      expect(find.text('AKTIF'), findsOneWidget);

      p.aktifDiBackend = false;
      ws.terimaSiaran(_pesanOffDasbor);
      await tester.pumpAndSettle();

      expect(find.text('SIAGA'), findsOneWidget);
      expect(find.text('Selesai'), findsWidgets);

      p.lepasSumberRealtime();
    });
  });

  group('Pendaftaran pendengar aman', () {
    test('Memasang dua kali tidak mendaftarkan pendengar ganda', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;

      p.pasangSumberRealtime(ws);
      p.pasangSumberRealtime(ws);
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 1, reason: 'satu siaran harus menghasilkan satu penyegaran');
    });

    test('Melepas menghentikan penyegaran dan tidak menyisakan pendengar', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      p.lepasSumberRealtime();

      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 0, reason: 'pendengar yang dilepas tidak boleh dipanggil lagi');
      expect(ws.adaPendengar, isFalse, reason: 'tidak boleh ada pendengar tertinggal');
    });

    test('dispose melepas pendengar sehingga tidak bocor', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung();
      p.pasangSumberRealtime(ws);

      expect(ws.adaPendengar, isTrue);
      p.dispose();

      expect(ws.adaPendengar, isFalse,
          reason: 'WebSocketService hidup selama proses; pendengar tertinggal menahan provider');
    });

    test('Berpindah ke layanan lain melepas pendengar yang lama', () async {
      final wsLama = _WsPalsu();
      final wsBaru = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;

      p.pasangSumberRealtime(wsLama);
      p.pasangSumberRealtime(wsBaru);

      expect(wsLama.adaPendengar, isFalse);
      expect(wsBaru.adaPendengar, isTrue);

      wsLama.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);
      expect(p.jumlahSegarkan, 0, reason: 'layanan lama tidak boleh lagi berpengaruh');
    });

    test('bersihkan() mereset tanda sehingga siaran berikutnya tetap dibaca ulang', () async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);
      expect(p.jumlahSegarkan, 1);

      // Keluar lalu masuk lagi sebagai pengguna lain di perangkat yang sama.
      p.bersihkan();

      // Siaran yang tandanya SAMA dengan sebelum logout tetap harus memicu
      // pembacaan ulang — kalau tandanya tidak direset, pengguna baru akan
      // duduk di depan layar yang tidak pernah menyusul keadaan.
      ws.terimaSiaran(_pesanOn);
      await Future<void>.delayed(Duration.zero);

      expect(p.jumlahSegarkan, 2,
          reason: 'tanda harus direset saat bersihkan(), bukan dibawa lintas sesi');
    });
  });

  group('Kedua layar mengikuti siaran', () {
    testWidgets('ALARM_OFF dari perangkat lain: kartu jadi SIAGA & riwayat SELESAI',
        (tester) async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung()..aktifDiBackend = true;
      p.pasangSumberRealtime(ws);

      await tester.pumpWidget(_bungkusDuaLayar(p, ws));
      await tester.pumpAndSettle();

      expect(find.text('AKTIF'), findsOneWidget);

      // Perangkat lain menyelesaikan daruratnya.
      p.aktifDiBackend = false;
      ws.terimaSiaran(_pesanOff);
      await tester.pumpAndSettle();

      expect(find.text('SIAGA'), findsOneWidget,
          reason: 'kartu harus mengikuti siaran tanpa aksi apa pun di perangkat ini');
      expect(find.text('AKTIF'), findsNothing);
      expect(find.text('Selesai'), findsWidgets,
          reason: 'riwayat di layar yang sama juga harus ikut berubah');

      p.lepasSumberRealtime();
    });

    testWidgets('ALARM_ON dari perangkat lain: kedua layar menyala', (tester) async {
      final ws = _WsPalsu();
      final p = _DaruratTerhitung();
      p.pasangSumberRealtime(ws);

      await tester.pumpWidget(_bungkusDuaLayar(p, ws));
      await tester.pumpAndSettle();
      expect(find.text('SIAGA'), findsOneWidget);

      p.aktifDiBackend = true;
      ws.terimaSiaran(_pesanOn);
      await tester.pumpAndSettle();

      expect(find.text('AKTIF'), findsOneWidget);
      expect(find.text('Kebakaran di dapur rumah nomor 12'), findsWidgets);

      p.lepasSumberRealtime();
    });
  });
}
