import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/screens/admin/data_warga_screen.dart';

import 'bantuan_uji.dart';

/// Tinggi kotak yang benar-benar dilukis untuk sebuah widget.
double tinggi(WidgetTester tester, Finder f) => tester.getSize(f).height;

/// Bangun layar Data Warga dengan kerapatan visual tertentu.
///
/// [kerapatan] ada di sini karena inilah yang membuat cacatnya tidak terlihat:
/// `VisualDensity.adaptivePlatformDensity` menghasilkan `standard` di uji widget
/// (platform bawaannya Android) tetapi `compact` di Windows, Linux, dan macOS.
/// `OutlinedButton` mengurangi `minimumSize`-nya dengan `baseSizeAdjustment`
/// milik kerapatan itu; `TextField` tidak. Jadi tinggi keduanya bisa sama persis
/// di seluruh uji dan tetap berbeda di layar tempat aplikasi ini dikembangkan.
Future<void> bukaFilter(WidgetTester tester, {required VisualDensity kerapatan}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: semuaProvider(),
      child: MaterialApp(
        theme: AppTheme.lightTheme.copyWith(visualDensity: kerapatan),
        home: const Scaffold(
          body: SingleChildScrollView(child: DataWargaScreen()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final kasus = <String, VisualDensity>{
    'standard (Android/iOS)': VisualDensity.standard,
    'compact (Windows/Linux/macOS)': VisualDensity.compact,
    'comfortable': VisualDensity.comfortable,
  };

  kasus.forEach((nama, kerapatan) {
    testWidgets('tombol Reset setinggi kolom pencarian — $nama', (tester) async {
      await bukaFilter(tester, kerapatan: kerapatan);

      final kolom = find.byType(TextField);
      final tombol = find.widgetWithText(OutlinedButton, 'Reset');
      expect(kolom, findsOneWidget);
      expect(tombol, findsOneWidget);

      final hKolom = tinggi(tester, kolom);
      final hTombol = tinggi(tester, tombol);

      expect(
        hTombol,
        hKolom,
        reason:
            'Kolom pencarian $hKolom, tombol Reset $hTombol. '
            'Keduanya sebaris dan bersebelahan; beda tinggi terbaca langsung '
            'sebagai tombol yang lebih kecil. Penyebab yang paling mungkin: '
            'VisualDensity memangkas minimumSize tombol tetapi tidak menyentuh '
            'TextField.',
      );
    });
  });

  testWidgets('keduanya rata atas dan rata bawah, bukan sekadar setinggi', (tester) async {
    // Tinggi sama belum berarti sejajar: `Wrap` bisa saja merapatkan salah
    // satunya ke atas. Yang dilihat mata adalah tepi atas dan tepi bawahnya.
    await bukaFilter(tester, kerapatan: VisualDensity.compact);

    final kolom = find.byType(TextField);
    final tombol = find.widgetWithText(OutlinedButton, 'Reset');

    final atasKolom = tester.getTopLeft(kolom).dy;
    final atasTombol = tester.getTopLeft(tombol).dy;
    final bawahKolom = tester.getBottomLeft(kolom).dy;
    final bawahTombol = tester.getBottomLeft(tombol).dy;

    expect(atasTombol, atasKolom, reason: 'tepi atas tidak sejajar');
    expect(bawahTombol, bawahKolom, reason: 'tepi bawah tidak sejajar');
  });

  testWidgets('tetap sama tinggi saat font sistem 1,3x', (tester) async {
    // 1,3x adalah setelan "Large" Android yang benar-benar dipakai orang.
    // Teks tombol ikut membesar sementara ikon di kolom pencarian tidak, jadi
    // inilah kondisi yang paling mungkin memisahkan keduanya lagi.
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: semuaProvider(),
        child: MaterialApp(
          theme: AppTheme.lightTheme.copyWith(visualDensity: VisualDensity.compact),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: DataWargaScreen()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tinggi(tester, find.widgetWithText(OutlinedButton, 'Reset')),
      tinggi(tester, find.byType(TextField)),
    );
  });
}
