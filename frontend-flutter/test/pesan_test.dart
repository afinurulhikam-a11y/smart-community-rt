import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/core/pesan.dart';
import 'package:smart_community/core/theme/app_theme.dart';

/// Ambil warna latar snackbar yang sedang tampil.
Color? latarSnackBar(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor;

Widget _pemicu(void Function(BuildContext) aksi) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (c) => ElevatedButton(onPressed: () => aksi(c), child: const Text('picu')),
    ),
  ),
);

void main() {
  group('warna snackbar', () {
    testWidgets('pesan berhasil memakai satu hijau', (tester) async {
      await tester.pumpWidget(_pemicu((c) => pesanSukses(c, 'Data ditambahkan')));
      await tester.tap(find.text('picu'));
      await tester.pump();

      expect(find.text('Data ditambahkan'), findsOneWidget);
      expect(latarSnackBar(tester), AppTheme.successColor);
    });

    testWidgets('pesan gagal memakai satu merah', (tester) async {
      await tester.pumpWidget(_pemicu((c) => pesanGagal(c, 'Pilih warga terlebih dahulu')));
      await tester.tap(find.text('picu'));
      await tester.pump();

      expect(find.text('Pilih warga terlebih dahulu'), findsOneWidget);
      expect(latarSnackBar(tester), AppTheme.dangerColor);
    });

    testWidgets('teksnya putih di atas kedua latar', (tester) async {
      // Kedua latar gelap. Warna teks bawaan snackbar mengikuti
      // `onInverseSurface`, yang ikut berubah di mode gelap — pada latar merah
      // hasilnya bisa nyaris tidak terbaca, dan itu tidak akan terlihat di tes
      // mana pun yang hanya memeriksa latarnya.
      for (final gelap in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: gelap ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (c) =>
                    ElevatedButton(onPressed: () => pesanGagal(c, 'gagal'), child: const Text('picu')),
              ),
            ),
          ),
        );
        await tester.tap(find.text('picu'));
        await tester.pump();

        expect(
          tester.widget<Text>(find.text('gagal')).style?.color,
          Colors.white,
          reason: 'mode gelap=$gelap',
        );
      }
    });

    testWidgets('perilaku dan durasi tetap bisa diatur per layar', (tester) async {
      await tester.pumpWidget(
        _pemicu(
          (c) => tampilkanPesan(
            c,
            'reset gagal',
            sukses: false,
            perilaku: SnackBarBehavior.floating,
            durasi: const Duration(seconds: 8),
          ),
        ),
      );
      await tester.tap(find.text('picu'));
      await tester.pump();

      final s = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(s.behavior, SnackBarBehavior.floating);
      expect(s.duration, const Duration(seconds: 8));
      expect(s.backgroundColor, AppTheme.dangerColor);
    });
  });

  test('tidak ada layar yang membangun SnackBar-nya sendiri', () {
    // Ini penjaga yang sebenarnya. Uji widget di atas hanya membuktikan helper
    // ini benar; yang membuat aplikasi konsisten adalah tidak adanya jalur lain.
    //
    // Sebelum penyatuan ada 61 pemanggil dengan tiga merah dan lima hijau yang
    // berbeda, ditambah 14 tanpa warna sama sekali. Semuanya benar secara
    // sintaks dan lolos setiap uji yang ada — hanya mata di perangkat yang bisa
    // melihatnya, dan hanya kalau kebetulan membuka layar yang tepat.
    final pelanggar = <String>[];

    for (final berkas in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final jalur = berkas.path.replaceAll(r'\', '/');
      if (!jalur.endsWith('.dart')) continue;
      if (jalur.endsWith('core/pesan.dart')) continue;

      final baris = berkas.readAsLinesSync();
      for (var i = 0; i < baris.length; i++) {
        if (baris[i].contains('showSnackBar')) {
          pelanggar.add('$jalur:${i + 1}');
        }
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason:
          'Pakai pesanSukses() / pesanGagal() / tampilkanPesan() dari lib/core/pesan.dart.\n'
          'Memanggil showSnackBar langsung berarti memilih warna sendiri, dan itulah\n'
          'yang membuat delapan warna beredar bersamaan sebelumnya.\n'
          'Ditemukan di:\n  ${pelanggar.join("\n  ")}',
    );
  });
}
