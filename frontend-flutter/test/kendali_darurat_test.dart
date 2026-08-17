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

/// Provider darurat yang tidak menyentuh jaringan, dengan keadaan yang bisa
/// disetel per skenario.
///
/// Keadaan darurat mustahil diuji lewat jalur aslinya: memicunya sungguhan
/// berarti membunyikan sirene. Yang diuji di sini adalah apa yang DIGAMBAR
/// layar untuk sebuah keadaan — dan keadaan itu datang dari backend.
class _DaruratPalsu extends EmergencyProvider {
  final bool menyala;
  final bool boleh;
  final bool milikOrangLain;
  final String pengaktif;
  final String keterangan;
  final List<EmergencyModel> daftar;

  /// Meniru keadaan "perintah sedang dikirim" untuk menguji penguncian tombol.
  final bool sedangMengirim;

  /// Bila diisi, `kendaliAlarm` menjawab galat ini — meniru 400 dari backend.
  final String? galatKirim;

  /// Panggilan `kendaliAlarm` yang tertangkap, untuk memastikan keterangan
  /// benar-benar ikut terkirim — bukan sekadar tervalidasi lalu hilang.
  final List<Map<String, String?>> terkirim = [];

  _DaruratPalsu({
    this.menyala = false,
    this.boleh = false,
    this.milikOrangLain = false,
    this.pengaktif = 'Tidak diketahui',
    this.keterangan = '',
    this.daftar = const [],
    this.sedangMengirim = false,
    this.galatKirim,
  });

  @override
  bool get mengirimAlarm => sedangMengirim;

  @override
  Future<void> fetchAlerts({String? status, int page = 1, int limit = 10, bool silent = false}) async {}

  @override
  Future<void> muatStatusAlarm() async {}

  @override
  List<EmergencyModel> get alerts => daftar;

  @override
  bool get isLoading => false;

  @override
  bool get alarmMenyala => menyala;

  @override
  bool get bolehMatikan => boleh;

  @override
  bool get daruratMilikOrangLain => milikOrangLain;

  @override
  String get namaPengaktif => pengaktif;

  @override
  String get keteranganKejadian => keterangan;

  @override
  DateTime? get waktuKejadian => menyala ? DateTime(2026, 8, 16, 16, 45) : null;

  @override
  Future<String?> kendaliAlarm(String aksi, String pin, {String? keterangan}) async {
    terkirim.add({'aksi': aksi, 'pin': pin, 'keterangan': keterangan});
    return galatKirim;
  }
}

EmergencyModel _alert({
  String id = 'ev-1',
  String userId = 'warga-1',
  String message = 'Kebakaran di dapur rumah nomor 12, api belum padam',
  String status = 'active',
  String namaWarga = 'Warga A',
}) =>
    EmergencyModel.fromJson({
      'id': id,
      'user_id': userId,
      'message': message,
      'status': status,
      'nama_warga': namaWarga,
      'alamat': 'Jl. Melati No. 12',
      'no_hp': '08123456789',
      'dismissed_by_nama': null,
      'dismissed_at': null,
      'created_at': '2026-08-16T09:45:00.000Z',
    });

/// Membungkus layar dengan provider bawaan, lalu MENIMPA yang perlu.
///
/// Entri MultiProvider yang belakangan berada lebih dalam di pohon, sehingga
/// pencarian tipe yang sama menemukannya lebih dulu.
Widget _bungkus(Widget layar, {required _DaruratPalsu darurat, AuthService? auth}) {
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

AuthService _auth({required String id, required String role}) {
  final a = AuthService();
  a.pasangUji(user: {'id': id, 'role': role, 'nama': 'Pengguna Uji'});
  return a;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('Modal aktivasi — keterangan wajib', () {
    testWidgets('Dialog NYALAKAN memuat kolom Keterangan Kejadian', (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      expect(find.text('Keterangan Kejadian'), findsOneWidget);
      expect(find.text('PIN Darurat'), findsOneWidget);
    });

    testWidgets('Kirim tanpa keterangan ditolak dan tidak mengirim apa pun', (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      // PIN diisi supaya yang menggagalkan HANYA keterangan.
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(find.text('Keterangan kejadian wajib diisi'), findsOneWidget);
      // Dialog tetap terbuka — tidak boleh lolos diam-diam.
      expect(find.text('PIN Darurat'), findsOneWidget);
      expect(darurat.terkirim, isEmpty, reason: 'tidak boleh ada permintaan terkirim');
    });

    testWidgets('Keterangan berisi spasi saja ditolak', (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '        ');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(find.text('Keterangan kejadian wajib diisi'), findsOneWidget);
      expect(darurat.terkirim, isEmpty);
    });

    testWidgets('Keterangan terlalu pendek ditolak dengan pesan yang menyebut batas', (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'api');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Terlalu pendek — minimal ${EmergencyProvider.keteranganMin} karakter'),
        findsOneWidget,
      );
      expect(darurat.terkirim, isEmpty);
    });

    testWidgets('PIN kosong dan keterangan kosong ditampilkan bersamaan', (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(find.text('Keterangan kejadian wajib diisi'), findsOneWidget);
      expect(find.text('PIN wajib diisi'), findsOneWidget);
      expect(darurat.terkirim, isEmpty);
    });

    testWidgets('Keterangan sah terkirim bersama PIN ke backend', (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(0),
        '  Kebakaran di dapur rumah nomor 12  ',
      );
      await tester.enterText(find.byType(TextField).at(1), '246810');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(darurat.terkirim, hasLength(1));
      expect(darurat.terkirim.first['aksi'], 'ON');
      expect(darurat.terkirim.first['pin'], '246810');
      // Dirapikan sebelum dikirim — spasi di ujung bukan bagian dari cerita.
      expect(darurat.terkirim.first['keterangan'], 'Kebakaran di dapur rumah nomor 12');
    });

    testWidgets('Keterangan lebih dari 500 karakter ditolak, bukan dipotong diam-diam',
        (tester) async {
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      final terlaluPanjang = 'A' * (EmergencyProvider.keteranganMaks + 20);
      await tester.enterText(find.byType(TextField).at(0), terlaluPanjang);
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.pumpAndSettle();

      // Teksnya utuh di kolom — tidak dipangkas jadi 500 tanpa sepengetahuan
      // pemiliknya. Yang terjadi adalah penolakan yang terlihat.
      final kolom = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(kolom.controller!.text.length, terlaluPanjang.length,
          reason: 'teks tidak boleh terpotong diam-diam');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Terlalu panjang — maksimal ${EmergencyProvider.keteranganMaks} karakter'),
        findsOneWidget,
      );
      expect(darurat.terkirim, isEmpty);
    });

    testWidgets('Tombol terkunci saat perintah sedang dikirim (anti kirim ganda)',
        (tester) async {
      final darurat = _DaruratPalsu(sedangMengirim: true);
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));
      // `pump`, BUKAN `pumpAndSettle`: keadaan sibuk menampilkan
      // CircularProgressIndicator yang berputar tanpa henti, sehingga
      // `pumpAndSettle` menunggu animasi yang tidak akan pernah selesai.
      await tester.pump();

      // Label berubah dan tombolnya mati — menekan berkali-kali saat panik
      // tidak boleh menjadi banyak permintaan.
      expect(find.text('Mengirim…'), findsWidgets);
      final tombol = tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('Mengirim…'), matching: find.byType(ElevatedButton)).first,
      );
      expect(tombol.onPressed, isNull, reason: 'tombol harus nonaktif selama pengiriman');
    });

    testWidgets('Galat 400 dari backend ditampilkan apa adanya kepada pengguna',
        (tester) async {
      const pesanBackend = 'Keterangan kejadian terlalu pendek — minimal 5 karakter.';
      final darurat = _DaruratPalsu(galatKirim: pesanBackend);
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Kebakaran di dapur');
      await tester.enterText(find.byType(TextField).at(1), '246810');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      // Permintaannya memang terkirim — penolakan datang dari backend, dan
      // pesannya diteruskan tanpa diganti kalimat generik.
      expect(darurat.terkirim, hasLength(1));
      expect(find.text(pesanBackend), findsOneWidget);
    });

    testWidgets('Dialog MATIKAN tidak meminta keterangan', (tester) async {
      final darurat = _DaruratPalsu(menyala: true, boleh: true, keterangan: 'Kebakaran');
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('MATIKAN'));
      await tester.pumpAndSettle();

      expect(find.text('Keterangan Kejadian'), findsNothing);
      expect(find.text('PIN Darurat'), findsOneWidget);
    });
  });

  group('Kartu Kendali Darurat — hak aksi', () {
    testWidgets('Darurat milik orang lain tanpa hak: tombol MATIKAN DIHILANGKAN', (tester) async {
      final darurat = _DaruratPalsu(
        menyala: true,
        boleh: false,
        milikOrangLain: true,
        pengaktif: 'Warga A',
        keterangan: 'Kebakaran di dapur rumah nomor 12',
      );
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));
      await tester.pumpAndSettle();

      expect(find.text('MATIKAN'), findsNothing,
          reason: 'tombol harus dihapus dari tampilan, bukan sekadar dinonaktifkan');

      // Kejadiannya sendiri TIDAK ikut hilang.
      expect(find.text('AKTIF'), findsOneWidget);
      expect(find.text('Aktif oleh Warga A'), findsOneWidget);
      expect(find.text('Kebakaran di dapur rumah nomor 12'), findsOneWidget);
    });

    testWidgets('Pemilik darurat tetap melihat tombol MATIKAN', (tester) async {
      final darurat = _DaruratPalsu(
        menyala: true,
        boleh: true,
        milikOrangLain: false,
        pengaktif: 'Pengguna Uji',
        keterangan: 'Pohon tumbang menutup jalan',
      );
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));
      await tester.pumpAndSettle();

      expect(find.text('MATIKAN'), findsOneWidget);
      expect(find.text('Pohon tumbang menutup jalan'), findsOneWidget);
    });

    testWidgets('Saat siaga tombol MATIKAN tetap ada sebagai jaring pengaman', (tester) async {
      // Aplikasi bisa tertinggal keadaan; buzzer yang tak bisa dihentikan
      // lebih buruk daripada satu perintah OFF berlebih.
      final darurat = _DaruratPalsu(menyala: false, boleh: false);
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));
      await tester.pumpAndSettle();

      expect(find.text('MATIKAN'), findsOneWidget);
      expect(find.text('SIAGA'), findsOneWidget);
    });
  });

  group('Badan permintaan /emergency/alarm', () {
    test('ON mengirim keterangan DAN message dengan nilai sama', () {
      final body = EmergencyProvider.susunBadanAlarm(
        'ON',
        '246810',
        '  Ada warga jatuh dan membutuhkan bantuan  ',
      );

      expect(body['aksi'], 'ON');
      expect(body['pin'], '246810');

      // Keduanya wajib ada selama backend produksi belum mengenal
      // `keterangan`: yang lama membaca `message`, yang baru membaca
      // `keterangan`. Menghapus salah satunya membuat kalimat warga hilang
      // diam-diam di salah satu sisi.
      expect(body['keterangan'], 'Ada warga jatuh dan membutuhkan bantuan');
      expect(body['message'], 'Ada warga jatuh dan membutuhkan bantuan');
      expect(body['message'], equals(body['keterangan']),
          reason: 'dua field yang berbeda isi akan ditafsirkan berbeda oleh dua versi backend');
    });

    test('OFF tidak membawa keterangan maupun message', () {
      final body = EmergencyProvider.susunBadanAlarm('OFF', '246810', 'apa pun');

      expect(body.containsKey('keterangan'), isFalse);
      expect(body.containsKey('message'), isFalse);
      expect(body.keys.toSet(), {'aksi', 'pin'});
    });

    test('Keterangan kosong atau spasi tidak dikirim sebagai field kosong', () {
      for (final k in <String?>[null, '', '   ', '\t\n ']) {
        final body = EmergencyProvider.susunBadanAlarm('ON', '1234', k);
        expect(body.containsKey('keterangan'), isFalse, reason: 'nilai: ${k?.trim()}');
        expect(body.containsKey('message'), isFalse, reason: 'nilai: ${k?.trim()}');
      }
    });
  });

  group('Penanda legacy — kejadian dari aplikasi versi lama', () {
    test('Penanda diterjemahkan, keterangan biasa dibiarkan apa adanya', () {
      expect(keteranganUntukTampilan(penandaLegacyKeterangan),
          'Tanpa keterangan — dikirim aplikasi versi lama.');
      expect(keteranganUntukTampilan('Kebakaran di dapur'), 'Kebakaran di dapur');
      expect(keteranganUntukTampilan(''), 'Tidak ada keterangan yang tercatat.');
      expect(keteranganUntukTampilan(null), 'Tidak ada keterangan yang tercatat.');
    });

    test('Model menandai kejadian legacy dan menerjemahkannya', () {
      final legacy = _alert(message: penandaLegacyKeterangan);
      expect(legacy.tanpaKeteranganLegacy, isTrue);
      expect(legacy.keteranganTampil, isNot(contains('legacy_without_keterangan')));

      final biasa = _alert(message: 'Maling di gang tiga');
      expect(biasa.tanpaKeteranganLegacy, isFalse);
      expect(biasa.keteranganTampil, 'Maling di gang tiga');
    });

    testWidgets('Riwayat tidak pernah menampilkan penanda mentah', (tester) async {
      final darurat = _DaruratPalsu(daftar: [_alert(message: penandaLegacyKeterangan)]);
      await tester.pumpWidget(_bungkus(
        const StatusDaruratScreen(),
        darurat: darurat,
        auth: _auth(id: 'warga-2', role: 'warga'),
      ));
      await tester.pumpAndSettle();

      expect(find.text(penandaLegacyKeterangan), findsNothing,
          reason: 'penanda internal tidak boleh bocor ke layar');
      expect(find.text('Tanpa keterangan — dikirim aplikasi versi lama.'), findsOneWidget);
    });

    testWidgets('Kartu dasbor menampilkan kalimat legacy, bukan penanda', (tester) async {
      final darurat = _DaruratPalsu(
        menyala: true,
        boleh: true,
        pengaktif: 'Warga A',
        keterangan: penandaLegacyKeterangan,
      );
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));
      await tester.pumpAndSettle();

      expect(find.text(penandaLegacyKeterangan), findsNothing);
      expect(find.text('Tanpa keterangan — dikirim aplikasi versi lama.'), findsOneWidget);
      // Kejadiannya tetap tampil utuh — pelapor dan statusnya tidak ikut hilang.
      expect(find.text('Aktif oleh Warga A'), findsOneWidget);
      expect(find.text('AKTIF'), findsOneWidget);
    });

    testWidgets('Klien BARU tetap wajib mengisi keterangan meski backend masih permisif',
        (tester) async {
      // Kelonggaran Tahap 1 ada di BACKEND, untuk APK lama. Aplikasi baru tidak
      // ikut dilonggarkan — kalau ia ikut longgar, keterangan sungguhan tidak
      // akan pernah terkumpul dan Tahap 2 tidak akan pernah bisa dinyalakan.
      final darurat = _DaruratPalsu();
      await tester.pumpWidget(_bungkus(const KartuAlarmDarurat(), darurat: darurat));

      await tester.tap(find.text('NYALAKAN'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nyalakan'));
      await tester.pumpAndSettle();

      expect(find.text('Keterangan kejadian wajib diisi'), findsOneWidget);
      expect(darurat.terkirim, isEmpty);
    });
  });

  group('Status Darurat — aksi Selesaikan', () {
    testWidgets('Warga lain tidak melihat tombol Selesaikan, tetapi tetap melihat kejadiannya',
        (tester) async {
      final darurat = _DaruratPalsu(daftar: [_alert(userId: 'warga-1')]);
      await tester.pumpWidget(_bungkus(
        const StatusDaruratScreen(),
        darurat: darurat,
        auth: _auth(id: 'warga-2', role: 'warga'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Selesaikan'), findsNothing,
          reason: 'warga lain tidak berwenang menutup kejadian ini');

      // Datanya TIDAK ikut disembunyikan.
      expect(find.text('Warga A'), findsWidgets);
      expect(find.text('Detail'), findsOneWidget);
    });

    testWidgets('Pemilik kejadian melihat tombol Selesaikan', (tester) async {
      final darurat = _DaruratPalsu(daftar: [_alert(userId: 'warga-1')]);
      await tester.pumpWidget(_bungkus(
        const StatusDaruratScreen(),
        darurat: darurat,
        auth: _auth(id: 'warga-1', role: 'warga'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Selesaikan'), findsOneWidget);
    });

    testWidgets('Pengurus melihat tombol Selesaikan pada kejadian milik warga', (tester) async {
      final darurat = _DaruratPalsu(daftar: [_alert(userId: 'warga-1')]);
      await tester.pumpWidget(_bungkus(
        const StatusDaruratScreen(),
        darurat: darurat,
        auth: _auth(id: 'pengurus-1', role: 'ketua_rt'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Selesaikan'), findsOneWidget);
    });

    testWidgets('Membuka Detail menampilkan keterangan penuh tanpa mengubah status',
        (tester) async {
      const panjang =
          'Kebakaran di dapur rumah nomor 12. Api sudah padam, tetapi masih ada asap tebal '
          'dan bau gas menyengat di sekitar dapur sehingga warga diminta menjauh dulu.';

      final darurat = _DaruratPalsu(daftar: [_alert(message: panjang, userId: 'warga-1')]);
      await tester.pumpWidget(_bungkus(
        const StatusDaruratScreen(),
        darurat: darurat,
        auth: _auth(id: 'warga-2', role: 'warga'),
      ));
      await tester.pumpAndSettle();

      // Di tabel keterangannya dipotong — dua baris dan elipsis — supaya satu
      // kalimat panjang tidak merusak seluruh baris.
      final diTabel = tester.widget<Text>(find.text(panjang));
      expect(diTabel.maxLines, 2);
      expect(diTabel.overflow, TextOverflow.ellipsis);

      // Kolom aksi berada di ujung tabel yang menggulir mendatar, jadi ia harus
      // dibawa ke dalam viewport dulu. Tanpa ini `tap()` mengenai ruang kosong
      // dan ujinya gagal seolah-olah tombolnya tidak ada.
      await tester.ensureVisible(find.text('Detail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detail'));
      await tester.pumpAndSettle();

      expect(find.text('Darurat Aktif'), findsOneWidget);
      expect(find.text('Keterangan Kejadian'), findsOneWidget);

      // Salinan di dalam dialog ditulis UTUH — tanpa batas baris. Dicari
      // sebagai keturunan AlertDialog karena salinan tabel juga menyimpan
      // teks penuh yang sama, hanya saja digambar terpotong.
      final diDialog = tester.widget<Text>(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(panjang),
      ));
      expect(diDialog.maxLines, isNull, reason: 'detail harus menampilkan keterangan utuh');

      // Membuka detail bukan menyelesaikan: tidak ada satu pun perintah terkirim.
      expect(darurat.terkirim, isEmpty);
      // Dan tombol Selesaikan tetap tidak muncul untuk yang tidak berwenang.
      expect(find.text('Selesaikan'), findsNothing);
    });
  });
}
