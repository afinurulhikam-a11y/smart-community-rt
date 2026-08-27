import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/core/theme/warna_konteks.dart';
import 'package:smart_community/widgets/tombol_kembali.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Warna tombol penutup (Batal, Tutup, Kembali)', () {
    testWidgets('Mode Terang: tombol dan helper menghasilkan warna hitam (#000000)', (tester) async {
      late BuildContext buildCtx;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                buildCtx = ctx;
                return Column(
                  children: [
                    const TombolKembali(),
                    TextButton(onPressed: () {}, child: const Text('Batal')),
                    OutlinedButton(onPressed: () {}, child: const Text('Tutup')),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Verifikasi helper warna kontekstual
      expect(buildCtx.warnaTombolTutup, const Color(0xFF000000));

      // Verifikasi tema TextButton & OutlinedButton
      final textBtnStyle = Theme.of(buildCtx).textButtonTheme.style;
      expect(textBtnStyle?.foregroundColor?.resolve({}), const Color(0xFF000000));

      final outlinedBtnStyle = Theme.of(buildCtx).outlinedButtonTheme.style;
      expect(outlinedBtnStyle?.foregroundColor?.resolve({}), const Color(0xFF000000));

      // Verifikasi ikon TombolKembali berwarna hitam
      final iconFinder = find.byIcon(Icons.arrow_back_rounded);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, const Color(0xFF000000));
    });

    testWidgets('Mode Gelap: tombol dan helper menghasilkan warna putih (#FFFFFF)', (tester) async {
      late BuildContext buildCtx;

      await tester.pumpWidget(
        MaterialApp(
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                buildCtx = ctx;
                return Column(
                  children: [
                    const TombolKembali(),
                    TextButton(onPressed: () {}, child: const Text('Batal')),
                    OutlinedButton(onPressed: () {}, child: const Text('Tutup')),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Verifikasi helper warna kontekstual
      expect(buildCtx.warnaTombolTutup, const Color(0xFFFFFFFF));

      // Verifikasi tema TextButton & OutlinedButton
      final textBtnStyle = Theme.of(buildCtx).textButtonTheme.style;
      expect(textBtnStyle?.foregroundColor?.resolve({}), const Color(0xFFFFFFFF));

      final outlinedBtnStyle = Theme.of(buildCtx).outlinedButtonTheme.style;
      expect(outlinedBtnStyle?.foregroundColor?.resolve({}), const Color(0xFFFFFFFF));

      // Verifikasi ikon TombolKembali berwarna putih
      final iconFinder = find.byIcon(Icons.arrow_back_rounded);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, const Color(0xFFFFFFFF));
    });
  });
}
