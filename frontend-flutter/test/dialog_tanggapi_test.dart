import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/complaint_provider.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/screens/admin/pengaduan_screen.dart';

import 'bantuan_uji.dart';

/// Dialog **Tanggapi Pengaduan** — satu-satunya tempat pengurus mengubah status
/// sekaligus menulis balasan yang dibaca warga.
///
/// Kenapa uji ini ada: dialog serupa di modul meteran meluber **196 px** pada
/// 320×568 dan **113 px** pada keadaan kosongnya, dan tak satu pun terlihat oleh
/// `flutter analyze` — cacat tata letak bukan galat Dart. Dialog ini membawa
/// dropdown, `TextField` lima baris, dan judul dua baris; ia layak dibuktikan,
/// bukan diasumsikan aman karena "polanya sudah benar".
///
/// Dua hal yang membuat uji ini bisa berjalan sama sekali:
///
///  1. **Provider disemai lewat `pasangUji`.** Tombol Tanggapi hanya digambar
///     bila tabelnya punya baris; provider kosong berarti tidak ada dialog untuk
///     dibuka.
///  2. **Izin `update` disemai lewat `terapkanData`.** `_bolehUbah` menjaga
///     tombol itu, dan `PermissionProvider` kosong menjawab "tidak boleh" —
///     jadi tanpa ini tombolnya tidak pernah muncul dan uji lulus tanpa pernah
///     menguji apa pun.

/// Provider yang tidak menyentuh jaringan.
///
/// `initState` layar memanggil `fetchComplaints`, dan bila backend kebetulan
/// hidup ia akan menjawab lalu **menimpa data yang baru disemai** — uji yang
/// sama lulus di mesin yang servernya mati dan gagal di mesin yang menyala.
/// Persis jebakan yang sudah terjadi di uji kartu meteran.
class _PengaduanTanpaJaringan extends ComplaintProvider {
  @override
  Future<void> fetchComplaints({String? status, String? search, int page = 1}) async {}

  @override
  Future<void> fetchStats() async {}
}

Map<String, dynamic> _pengaduan({
  int id = 1,
  String status = 'Menunggu',
  String? tanggapan,
  String? penanggap,
  String? dibacaPada,
}) => {
      'tanggapan_dibaca_pada': dibacaPada,
      'id': id,
      'kode_tiket': 'TKT-2026-000$id',
      // Sengaja panjang: judul pendek tidak pernah menekan tata letak.
      'judul': 'Lampu penerangan jalan umum di Gang Melati mati total sejak tiga malam',
      'deskripsi': 'Sudah tiga malam lampu di sepanjang gang tidak menyala sama sekali. '
          'Warga yang pulang kerja malam hari kesulitan melihat jalan, dan sudah ada '
          'satu anak yang terjatuh karena tidak melihat lubang di dekat pos ronda.',
      'kategori': 'Infrastruktur',
      'status': status,
      'nama_pengirim': 'Bapak Muhammad Nurhidayat Wicaksono',
      'created_at': '2026-08-09T20:15:00.000Z',
      'response': tanggapan,
      'responded_by_nama': penanggap,
    };

/// Izin pengurus penuh atas modul pengaduan.
PermissionProvider _izinPengurus() => PermissionProvider()
  ..terapkanData({
    'role': 'ketua_rt',
    'role_label': 'Ketua RT',
    'menus': [
      {
        'kode': 'aspirasi.pengaduan',
        'can_view': true,
        'can_create': true,
        'can_update': true,
        'can_delete': false,
      },
    ],
  });

/// Providernya harus berada DI ATAS `MaterialApp`.
///
/// `showDialog` memasang isinya di Navigator akar, jadi dialog mewarisi dari
/// konteks Navigator — bukan dari konteks tombol yang membukanya. Provider yang
/// disematkan di bawah `MaterialApp` tidak terlihat sama sekali, dan dialognya
/// diam-diam membaca provider kosong: uji tetap hijau sambil tidak menguji satu
/// baris data pun.
///
/// Parameter tipe pada `.value` juga wajib eksplisit — tanpa
/// `<ComplaintProvider>`, Dart menyimpulkan `<_PengaduanTanpaJaringan>`, tipe
/// yang berbeda, dan `read<ComplaintProvider>()` melewatinya.
Widget _bungkusPengaduan(
  List<Map<String, dynamic>> daftar, {
  double skalaFont = 1.0,
  bool gelap = false,
}) {
  final prov = _PengaduanTanpaJaringan()..pasangUji(daftar);
  return MultiProvider(
    providers: [
      ...semuaProvider(),
      ChangeNotifierProvider<ComplaintProvider>.value(value: prov),
      ChangeNotifierProvider<PermissionProvider>.value(value: _izinPengurus()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: gelap ? ThemeMode.dark : ThemeMode.light,
      builder: (ctx, anak) => MediaQuery.withClampedTextScaling(
        minScaleFactor: skalaFont,
        maxScaleFactor: skalaFont,
        child: anak!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: const PengaduanScreen(),
          ),
        ),
      ),
    ),
  );
}

/// Buka dialog lewat tombol aksinya, bukan dengan memanggil metode privatnya.
/// Itu juga yang membuktikan tombolnya memang tergambar dan bisa ditekan.
///
/// `ensureVisible` wajib: di layar ponsel tabelnya menjadi kartu bertumpuk dan
/// tombol aksinya jatuh di bawah lipatan. `tap` pada widget di luar viewport
/// tidak mengenai apa pun — ia gagal sebagai peringatan hit-test, bukan sebagai
/// "tombolnya tidak ada", sehingga mudah disalahartikan.
Future<void> _ketuk(WidgetTester tester, String tooltip) async {
  final tombol = find.byTooltip(tooltip);
  expect(tombol, findsWidgets, reason: 'tombol "$tooltip" tidak tergambar');
  await tester.ensureVisible(tombol.first);
  await tester.pumpAndSettle();
  await tester.tap(tombol.first);
  await tester.pumpAndSettle();
}

void main() {
  // Dialog Detail memformat tanggal dengan `DateFormat(..., 'id_ID')`, dan
  // tanpa data locale-nya `intl` melempar UninitializedLocaleData — kegagalan
  // pada kerangka uji, bukan pada tata letak yang sedang diperiksa.
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('Dialog Tanggapi — tergambar di kondisi perangkat nyata', () {
    for (final k in kondisiUji) {
      testWidgets('dari aksi tabel @ ${k.nama}', (tester) async {
        pasangKondisi(tester, k);
        await tester.pumpWidget(
          _bungkusPengaduan([_pengaduan()], skalaFont: k.skalaFont),
        );
        await tester.pumpAndSettle();
        await _ketuk(tester, 'Tanggapi');
        expect(tester.takeException(), isNull);
      });
    }

    for (final k in kondisiUji) {
      testWidgets('lewat dialog Detail @ ${k.nama}', (tester) async {
        pasangKondisi(tester, k);
        await tester.pumpWidget(
          _bungkusPengaduan([_pengaduan()], skalaFont: k.skalaFont),
        );
        await tester.pumpAndSettle();
        await _ketuk(tester, 'Lihat Detail');
        expect(tester.takeException(), isNull);

        // Tombol Tanggapi di dalam dialog Detail menutup Detail lalu membuka
        // formulir — dua dialog beruntun, jalur yang paling mungkin retak.
        await tester.tap(find.widgetWithText(ElevatedButton, 'Tanggapi'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Isi dialog Tanggapi', () {
    testWidgets('membawa pilihan status DAN kolom teks', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan()]));
      await tester.pumpAndSettle();
      await _ketuk(tester, 'Tanggapi');

      expect(find.text('Tanggapi Pengaduan'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Teks Tanggapan'), findsOneWidget);
      expect(find.text('Simpan Tanggapan'), findsOneWidget);
    });

    testWidgets('menawarkan Diproses, Selesai, dan Ditolak', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan()]));
      await tester.pumpAndSettle();
      await _ketuk(tester, 'Tanggapi');

      // Diuji lewat PERILAKU, bukan isi widget. Dua alasan, keduanya nyata:
      // saat tertutup `DropdownButtonFormField` hanya membangun item yang
      // terpilih (jadi membacanya menghasilkan 1, bukan 3), sementara membaca
      // seluruh pohon ikut menghitung dropdown penyaring milik layar di
      // belakang dialog (4, bukan 3). Keduanya menjawab pertanyaan yang lain.

      // Pengaduan ini berstatus 'Menunggu', dan dialognya harus sudah memilih
      // satu langkah maju — bukan menyuruh pengurus memilih ulang dari awal.
      final diDialog = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Diproses'),
      );
      expect(diDialog, findsOneWidget, reason: 'tidak default ke satu langkah maju');

      // 'Menunggu' tidak boleh ada di dalam dialog sama sekali: menanggapi
      // berarti bergerak maju, dan memundurkannya membuat warga melihat
      // pengaduannya seolah belum pernah disentuh siapa pun.
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Menunggu')),
        findsNothing,
      );

      // Ketiga pilihan benar-benar bisa dipilih — dibuktikan dengan memilihnya.
      for (final s in ['Selesai', 'Ditolak']) {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s).last);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: find.byType(AlertDialog), matching: find.text(s)),
          findsOneWidget,
          reason: 'pilihan "$s" tidak bisa dipilih',
        );
      }
    });

    testWidgets('tanggapan lama ikut terisi, bukan kolom kosong', (tester) async {
      // Pengurus yang mengoreksi tanggapan tidak boleh harus mengetik ulang —
      // dan kolom kosong membuatnya mengira belum pernah ada tanggapan.
      const lama = 'Sudah dilaporkan ke Dinas Perhubungan, menunggu penjadwalan.';
      await tester.pumpWidget(
        _bungkusPengaduan([_pengaduan(status: 'Diproses', tanggapan: lama)]),
      );
      await tester.pumpAndSettle();
      await _ketuk(tester, 'Tanggapi');

      final f = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Teks Tanggapan'),
      );
      expect(f.controller?.text, lama);
    });
  });

  group('Dialog Detail — apa yang dilihat warga', () {
    testWidgets('tanggapan dan nama penanggap ditampilkan', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([
        _pengaduan(
          status: 'Selesai',
          tanggapan: 'Petugas kebersihan sudah dijadwalkan ke lokasi esok pagi.',
          penanggap: 'Administrator',
        ),
      ]));
      await tester.pumpAndSettle();
      await _ketuk(tester, 'Lihat Detail');

      expect(find.textContaining('dijadwalkan ke lokasi'), findsOneWidget);
      expect(find.textContaining('Administrator'), findsOneWidget);
    });

    testWidgets('belum ditanggapi berkata begitu, bukan kosong diam', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan()]));
      await tester.pumpAndSettle();
      await _ketuk(tester, 'Lihat Detail');
      expect(find.text('Belum ada tanggapan.'), findsOneWidget);
    });

    testWidgets('pengaduan Selesai tidak menawarkan Tanggapi lagi', (tester) async {
      await tester.pumpWidget(
        _bungkusPengaduan([_pengaduan(status: 'Selesai', tanggapan: 'Beres.')]),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tanggapi'), findsNothing);
    });
  });

  group('Lencana tanggapan belum dibaca', () {
    testWidgets('baris bertanggapan baru diberi lencana "Baru"', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([
        _pengaduan(status: 'Diproses', tanggapan: 'Petugas dijadwalkan besok.'),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Baru'), findsOneWidget);
    });

    testWidgets('yang sudah dibaca tidak berlencana', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([
        _pengaduan(
          status: 'Diproses',
          tanggapan: 'Petugas dijadwalkan besok.',
          dibacaPada: '2026-08-10T09:00:00.000Z',
        ),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Baru'), findsNothing);
    });

    testWidgets('belum ditanggapi juga tidak berlencana', (tester) async {
      // Lencana yang menyala tanpa ada yang bisa dibaca hanya melatih warga
      // mengabaikannya.
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan()]));
      await tester.pumpAndSettle();
      expect(find.text('Baru'), findsNothing);
    });

    for (final k in kondisiUji) {
      testWidgets('lencana tidak meluberkan baris @ ${k.nama}', (tester) async {
        pasangKondisi(tester, k);
        await tester.pumpWidget(_bungkusPengaduan([
          _pengaduan(status: 'Diproses', tanggapan: 'Sudah dijadwalkan.'),
        ], skalaFont: k.skalaFont));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Kolom aksi — kesejajaran diukur, bukan diperkirakan', () {
    // Dijalankan di lebar desktop supaya tabelnya benar-benar tabel; di ponsel
    // TabelResponsif berubah jadi kartu dan kolom aksinya tata letaknya lain.
    Future<void> siapkan(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan(status: 'Diproses')]));
      await tester.pumpAndSettle();
    }

    testWidgets('kedua tombol berukuran sama persis', (tester) async {
      await siapkan(tester);
      final detail = tester.getSize(find.byTooltip('Lihat Detail'));
      final tanggapi = tester.getSize(find.byTooltip('Tanggapi'));
      expect(tanggapi, detail,
          reason: 'ukuran berbeda → satu tombol terasa lebih lega daripada yang lain');
    });

    testWidgets('sejajar VERTIKAL — titik tengah y identik', (tester) async {
      await siapkan(tester);
      final d = tester.getCenter(find.byTooltip('Lihat Detail'));
      final t = tester.getCenter(find.byTooltip('Tanggapi'));
      expect(t.dy, d.dy, reason: 'salah satu tombol duduk lebih tinggi/rendah');
    });

    testWidgets('sejajar HORIZONTAL — jaraknya persis selebar satu tombol',
        (tester) async {
      await siapkan(tester);
      final d = tester.getRect(find.byTooltip('Lihat Detail'));
      final t = tester.getRect(find.byTooltip('Tanggapi'));

      // Yang dikunci adalah jarak ANTAR-PUSAT, bukan celah antar-lingkaran.
      //
      // Terukur: kedua tombol 30×30, dan pusatnya berjarak tepat 48px — yaitu
      // `kMinInteractiveDimension`. Lingkaran hover-nya memang 30, sehingga
      // tersisa celah 18px di antaranya (48 − 30), dan itu BUKAN celah liar
      // melainkan padding sasaran sentuh 48dp yang jadi aturan proyek ini.
      //
      // Mengunci "celah nol" justru salah: ia akan memaksa kedua sasaran sentuh
      // saling tumpang tindih, dan ketukan di perbatasan mengenai tombol yang
      // keliru. Yang benar adalah sasaran sentuhnya bersebelahan persis — tidak
      // beririsan, tidak berjarak.
      expect(t.center.dx - d.center.dx, kMinInteractiveDimension,
          reason: 'pusatnya tidak berjarak satu sasaran sentuh penuh');
      expect(t.width, d.width);
      expect(d.width, 30.0, reason: 'ukuran hover berubah dari gayaAksiTabel');
    });

    testWidgets('warnanya BERBEDA — bukan dua ikon teal yang sama', (tester) async {
      await siapkan(tester);
      Color? warna(String tooltip) => tester
          .widget<Icon>(find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byType(Icon),
          ))
          .color;

      final detail = warna('Lihat Detail');
      final tanggapi = warna('Tanggapi');
      expect(detail, isNotNull);
      expect(tanggapi, isNotNull);
      expect(tanggapi, isNot(detail),
          reason: 'Detail hanya membaca; Tanggapi mengubah status DAN mengirim '
              'WhatsApp ke warga — keduanya tidak boleh terlihat sama');

      // Tidak boleh bertabrakan dengan warna lencana status di baris yang sama.
      const warnaStatus = [Colors.orange, Colors.blue, Color(0xFF166534)];
      expect(warnaStatus.contains(tanggapi), isFalse,
          reason: 'warnanya sama dengan salah satu lencana status');
    });
  });

  group('Lencana status — empat status, empat warna', () {
    /// Warna teks lencana status pada baris pertama tabel.
    Color? warnaLencana(WidgetTester tester, String status) {
      final teks = tester.widget<Text>(find.descendant(
        of: find.byType(Container),
        matching: find.text(status),
      ).first);
      return teks.style?.color;
    }

    Future<Color?> render(WidgetTester tester, String status) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan(status: status)]));
      await tester.pumpAndSettle();
      return warnaLencana(tester, status);
    }

    testWidgets('Ditolak TIDAK berwarna sama dengan Menunggu', (tester) async {
      // Inti cacatnya: `Ditolak` tidak punya cabang sendiri sehingga jatuh ke
      // oranye bawaan — warna Menunggu. Aduan yang sudah ditutup terlihat sama
      // persis dengan yang belum disentuh siapa pun.
      final menunggu = await render(tester, 'Menunggu');
      expect(menunggu, isNotNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final ditolak = await render(tester, 'Ditolak');
      expect(ditolak, isNotNull);
      expect(ditolak, isNot(menunggu),
          reason: 'Ditolak masih memakai warna bawaan yang sama dengan Menunggu');
    });

    testWidgets('keempat statusnya berwarna berbeda satu sama lain',
        (tester) async {
      final warna = <String, Color?>{};
      for (final s in ['Menunggu', 'Diproses', 'Selesai', 'Ditolak']) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        warna[s] = await render(tester, s);
      }
      final unik = warna.values.whereType<Color>().toSet();
      expect(unik.length, 4,
          reason: 'ada status yang berbagi warna: '
              '${warna.entries.map((e) => '${e.key}=${e.value}').join(', ')}');
    });
  });

  group('Mode gelap', () {
    testWidgets('dialog Tanggapi tergambar di tema gelap', (tester) async {
      await tester.pumpWidget(_bungkusPengaduan([_pengaduan()], gelap: true));
      await tester.pumpAndSettle();
      await _ketuk(tester, 'Tanggapi');
      expect(tester.takeException(), isNull);
    });
  });
}
