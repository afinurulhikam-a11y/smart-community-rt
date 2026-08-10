import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/models/meteran_model.dart';
import 'package:smart_community/providers/meteran_provider.dart';
import 'package:smart_community/widgets/dialog_bacaan_meteran.dart';
import 'package:smart_community/widgets/kartu_meteran_warga.dart';

import 'bantuan_uji.dart';

/// Kartu meteran punya enam tampilan, dan lima di antaranya hanya muncul pada
/// kombinasi tanggal dan isi tabel tertentu.
///
/// Uji yang hanya me-render layarnya dengan provider kosong akan selamanya
/// melihat satu keadaan saja — "data belum tersedia" — yaitu tampilan yang
/// paling sedikit isinya, dan karena itu paling kecil kemungkinannya meluber.
/// Justru lima keadaan lain yang membawa angka, pita peringatan, dan tombol.
///
/// Karena itu keadaannya dipasang langsung lewat `pasangUji`, lalu setiap
/// keadaan di-render pada seluruh [kondisiUji]: lima lebar nyata, poni atas,
/// bilah gestur, dan skala font 1,3× — setelan "Besar" yang benar-benar
/// dipakai orang di Android.

MeteranSaya _keadaan({
  bool periodePertama = false,
  bool bolehIsi = true,
  bool langgananSampah = true,
  MeteranModel? bacaan,
  int? meteranLalu = 230,
}) {
  return MeteranSaya(
    namaPelanggan: 'Bapak Muhammad Nurhidayat Wicaksono',
    noKk: '3374010101010001',
    blok: 'C-12',
    alamat: 'Jl. Melati Raya Nomor 45 RT 003 RW 007',
    langgananSampah: langgananSampah,
    periode: '2026-08',
    periodePertama: periodePertama,
    meteranLalu: meteranLalu,
    bacaan: bacaan,
    bolehIsi: bolehIsi,
    batasTanggal: 5,
  );
}

MeteranModel _bacaan({
  int lalu = 230,
  int kini = 234,
  String status = 'terisi',
  String? catatan,
  String? billId,
}) {
  return MeteranModel(
    id: 'bacaan-1',
    keluargaId: 1,
    periode: '2026-08',
    status: status,
    meteranLalu: lalu,
    meteranSekarang: kini,
    catatan: catatan,
    billId: billId,
    kepalaKeluarga: 'Bapak Muhammad Nurhidayat Wicaksono',
    blok: 'C-12',
    noKk: '3374010101010001',
  );
}

/// Semua keadaan yang harus bisa digambar, dengan nama yang menjelaskan
/// kenapa masing-masing berbeda.
final Map<String, MeteranSaya?> _semuaKeadaan = {
  'periode pertama, belum diisi': _keadaan(periodePertama: true, meteranLalu: null),
  'periode lanjutan, belum diisi': _keadaan(),
  'sudah diisi, masih boleh diubah': _keadaan(bacaan: _bacaan()),
  'sudah diisi, tanggal sudah lewat': _keadaan(bolehIsi: false, bacaan: _bacaan()),
  'terkunci karena tagihan sudah terbit':
      _keadaan(bolehIsi: false, bacaan: _bacaan(billId: 'tagihan-1')),
  'anomali': _keadaan(
    bacaan: _bacaan(
      kini: 100,
      status: 'anomali',
      catatan: 'Meteran sekarang (100) lebih kecil daripada meteran sebelumnya (230).',
    ),
  ),
  'tanpa langganan sampah': _keadaan(langgananSampah: false, bacaan: _bacaan()),
  // Null = akun tanpa kartu keluarga. Kartunya harus menjelaskan keadaannya,
  // bukan diam — daftar kosong terbaca sebagai "belum ada tagihan".
  'akun tanpa kartu keluarga': null,
};

/// Provider yang TIDAK menyentuh jaringan.
///
/// Tanpa ini uji ini bergantung pada apakah backend kebetulan hidup — dan
/// hasilnya berbeda-beda. Terbukti langsung: dengan server menyala di
/// localhost:3001, `muatSaya()` benar-benar berjalan, dijawab 400 karena uji
/// tidak membawa token, lalu mengosongkan keadaan yang baru saja disemai. Uji
/// yang sama akan lulus di mesin yang servernya mati dan gagal di mesin yang
/// menyala — cacat yang jauh lebih mahal daripada cacat yang dicarinya.
class _MeteranTanpaJaringan extends MeteranProvider {
  @override
  Future<void> muatSaya({String? periode}) async {}

  @override
  Future<void> muatDaftar({String? periode, String? status, String? search}) async {}
}

/// Provider disemai SEBELUM pumpWidget, lalu disematkan di atas widgetnya.
///
/// Menyemainya di dalam `build` akan memanggil `notifyListeners()` di tengah
/// fase build dan gagal dengan "setState() called during build" — kegagalan
/// pada uji itu sendiri, bukan pada kode yang sedang diuji. Provider dalam
/// menutupi yang dari [semuaProvider], jadi `context.read` di dalam widget
/// menemukan yang sudah berisi.
Widget _sematkan(
  Widget anak, {
  MeteranSaya? saya,
  List<MeteranModel>? daftar,
  String? galat,
  double skalaFont = 1.0,
  bool gelap = false,
}) {
  final prov = _MeteranTanpaJaringan()
    ..pasangUji(saya: saya, daftar: daftar, galat: galat);
  return bungkusLayar(
    ChangeNotifierProvider<MeteranProvider>.value(value: prov, child: anak),
    skalaFont: skalaFont,
    gelap: gelap,
  );
}

/// Buka dialog lewat `showDialog`, bukan merendernya sebagai isi layar.
///
/// [bungkusLayar] menaruh anaknya di dalam `SingleChildScrollView` — meniru
/// kerangka MainDashboard, dan benar untuk sebuah layar. Sebuah dialog tidak
/// pernah dipasang di sana: `showDialog` memasangnya di Navigator akar dengan
/// tinggi terbatas. Merendernya di dalam scroll memberi tinggi tak terbatas,
/// dan `ListView(shrinkWrap: true)` di dalamnya lalu dimintai dimensi
/// intrinsik yang memang tidak bisa ia berikan.
///
/// Uji yang memaksakan cara pasang yang salah akan gagal atas kesalahannya
/// sendiri, dan "memperbaikinya" berarti mengubah kode produksi yang tidak
/// pernah rusak.
///
/// Providernya juga harus berada DI ATAS `MaterialApp`, bukan di dalam `home:`.
///
/// `showDialog` memasang isinya di Navigator akar, jadi dialog mewarisi dari
/// konteks Navigator — bukan dari konteks tombol yang membukanya. Provider yang
/// disematkan di bawah `MaterialApp` karena itu tidak terlihat sama sekali, dan
/// dialognya diam-diam membaca provider kosong: uji tetap "lulus" karena tidak
/// ada yang meluber, sambil tidak pernah menguji satu baris data pun.
///
/// Jebakan yang sama sudah tercatat di CLAUDE.md untuk mode gelap — dulu
/// `Theme()` dipasang di tengah pohon dan setiap dialog tetap terang.
Future<void> _bukaDialog(
  WidgetTester tester, {
  required List<MeteranModel> daftar,
  String? galat,
  double skalaFont = 1.0,
}) async {
  final prov = _MeteranTanpaJaringan()..pasangUji(daftar: daftar, galat: galat);

  await tester.pumpWidget(
    MultiProvider(
      // Yang terakhir berada paling dalam, jadi ia menutupi MeteranProvider
      // kosong dari semuaProvider().
      providers: [
        ...semuaProvider(),
        // Parameter tipe WAJIB eksplisit. Tanpa <MeteranProvider>, Dart
        // menyimpulkan ChangeNotifierProvider<_MeteranTanpaJaringan> — tipe
        // yang berbeda — sehingga `read<MeteranProvider>()` di dalam dialog
        // melewatinya dan menemukan yang kosong dari semuaProvider(). Uji
        // tetap hijau sambil menguji provider yang salah.
        ChangeNotifierProvider<MeteranProvider>.value(value: prov),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (ctx, anak) => MediaQuery.withClampedTextScaling(
          minScaleFactor: skalaFont,
          maxScaleFactor: skalaFont,
          child: anak!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog(
                context: ctx,
                builder: (_) => const DialogBacaanMeteran(),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
}

Widget _bungkusKartu(MeteranSaya? keadaan, {double skalaFont = 1.0, bool gelap = false}) {
  return _sematkan(
    const KartuMeteranWarga(),
    saya: keadaan,
    galat: keadaan == null ? 'Akun ini belum tertaut ke kartu keluarga mana pun.' : null,
    skalaFont: skalaFont,
    gelap: gelap,
  );
}

void main() {
  group('KartuMeteranWarga — enam keadaan × kondisi perangkat nyata', () {
    for (final entri in _semuaKeadaan.entries) {
      for (final k in kondisiUji) {
        testWidgets('${entri.key} @ ${k.nama}', (tester) async {
          pasangKondisi(tester, k);
          await tester.pumpWidget(_bungkusKartu(entri.value, skalaFont: k.skalaFont));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Isi yang harus terlihat, bukan sekadar tidak meluber', () {
    testWidgets('anomali menjelaskan kenapa ditandai', (tester) async {
      await tester.pumpWidget(_bungkusKartu(_semuaKeadaan['anomali']));
      await tester.pump();
      expect(find.textContaining('lebih kecil'), findsOneWidget);
    });

    testWidgets('tanggal lewat DAN belum diisi memberi peringatan, bukan diam',
        (tester) async {
      // Keadaan yang paling mudah terlewat. Tanpa peringatan, warga baru tahu
      // ia melewatkannya ketika tagihannya terbit tanpa pemakaian air.
      await tester.pumpWidget(_bungkusKartu(_keadaan(bolehIsi: false)));
      await tester.pump();
      expect(find.textContaining('sudah lewat'), findsOneWidget);
      expect(find.text('Isi Meteran'), findsNothing);
    });

    testWidgets('tagihan sudah terbit: tidak ada tombol isi/ubah', (tester) async {
      await tester.pumpWidget(
        _bungkusKartu(_semuaKeadaan['terkunci karena tagihan sudah terbit']),
      );
      await tester.pump();
      expect(find.text('Isi Meteran'), findsNothing);
      expect(find.text('Ubah Meteran'), findsNothing);
      expect(find.textContaining('terkunci'), findsOneWidget);
    });

    testWidgets('saklar sampah mati setelah batas tanggal', (tester) async {
      await tester.pumpWidget(
        _bungkusKartu(_keadaan(bolehIsi: false, bacaan: _bacaan())),
      );
      await tester.pump();
      final saklar = tester.widget<Switch>(find.byType(Switch));
      expect(saklar.onChanged, isNull,
          reason: 'Tanpa batas, warga bisa mematikannya tgl 24 lalu '
              'menyalakannya lagi tgl 26 dan melewati biayanya.');
    });

    testWidgets('akun tanpa KK menjelaskan keadaannya', (tester) async {
      await tester.pumpWidget(_bungkusKartu(null));
      await tester.pump();
      expect(find.textContaining('kartu keluarga'), findsOneWidget);
    });

    testWidgets('periode pertama meminta DUA angka', (tester) async {
      await tester.pumpWidget(
        _bungkusKartu(_semuaKeadaan['periode pertama, belum diisi']),
      );
      await tester.pump();
      await tester.tap(find.text('Isi Meteran'));
      await tester.pumpAndSettle();
      expect(find.text('Meteran bulan lalu'), findsOneWidget);
      expect(find.text('Meteran sekarang'), findsOneWidget);
    });

    testWidgets('periode lanjutan hanya meminta SATU angka', (tester) async {
      // Angka pembandingnya ditampilkan, bukan diminta — server mengambilnya
      // sendiri dan mengabaikan kiriman klien.
      await tester.pumpWidget(_bungkusKartu(_keadaan()));
      await tester.pump();
      await tester.tap(find.text('Isi Meteran'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Meteran sekarang'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Meteran bulan lalu'), findsNothing);
    });
  });

  group('Mode gelap', () {
    for (final entri in _semuaKeadaan.entries) {
      testWidgets('${entri.key} terpasang di tema gelap', (tester) async {
        await tester.pumpWidget(_bungkusKartu(entri.value, gelap: true));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DialogBacaanMeteran — panel pengurus', () {
    List<MeteranModel> daftarPanjang() => [
          _bacaan(),
          _bacaan(status: 'menunggu', kini: 0).salinKosong(),
          _bacaan(
            kini: 100,
            status: 'anomali',
            catatan: 'Meteran sekarang (100) lebih kecil daripada meteran sebelumnya (230).',
          ),
        ];

    for (final k in kondisiUji) {
      testWidgets('daftar bacaan @ ${k.nama}', (tester) async {
        pasangKondisi(tester, k);
        await _bukaDialog(tester, daftar: daftarPanjang(), skalaFont: k.skalaFont);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('daftar kosong tidak berbunyi seperti kegagalan', (tester) async {
      await _bukaDialog(tester, daftar: []);
      expect(find.textContaining('Belum ada bacaan meteran'), findsOneWidget);
    });

    testWidgets('permintaan gagal TIDAK tampil sebagai daftar kosong', (tester) async {
      // Kegagalan yang tampil sebagai "belum ada data" membuat pengurus
      // menyimpulkan tidak ada yang melapor, padahal servernya tak terjangkau.
      await _bukaDialog(tester, daftar: [], galat: 'Gagal terhubung ke server');
      expect(find.textContaining('Belum ada bacaan meteran'), findsNothing);
      expect(find.textContaining('Gagal'), findsWidgets);
    });

    testWidgets('periode dibangun dari komponen waktu lokal', (tester) async {
      // 1 Agustus pukul 00:30 WIB adalah 31 Juli di UTC. `toIso8601String()`
      // akan mengirim periode bulan sebelumnya, dan seluruh layar bergeser
      // sebulan tepat pada tanggal 1.
      expect(periodeSekarang(DateTime(2026, 8, 1, 0, 30)), '2026-08');
      expect(periodeSekarang(DateTime(2026, 1, 1)), '2026-01');
      expect(periodeSekarang(DateTime(2026, 12, 31, 23, 59)), '2026-12');
    });
  });
}

extension on MeteranModel {
  /// Bacaan yang barisnya sudah ada tetapi warganya belum mengisi angkanya.
  MeteranModel salinKosong() => MeteranModel(
        id: id,
        keluargaId: keluargaId,
        periode: periode,
        status: 'menunggu',
        kepalaKeluarga: kepalaKeluarga,
        blok: blok,
        noKk: noKk,
      );
}
