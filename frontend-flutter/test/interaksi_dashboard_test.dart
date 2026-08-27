import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bantuan_uji.dart';

/// Menguji apa yang terjadi saat tombol BENAR-BENAR DITEKAN.
///
/// Seluruh pengujian lain di proyek ini hanya me-render: `mobile_layout_test`
/// membangun 18 kombinasi layar × ukuran lalu memeriksa `takeException()`,
/// tetapi tidak satu pun mengetuk apa pun. Cacat interaksi karena itu lolos
/// dengan bersih.
///
/// Celah itu meloloskan satu cacat sampai ke perangkat: `_pilihMenu` sempat
/// memanggil dirinya sendiri, sehingga SETIAP ketukan menu melempar
/// `StackOverflowError` setelah sekitar 128 ribu frame dan aplikasi membeku.
/// `flutter analyze` tidak bisa melihatnya — rekursi tak berujung tetap kode
/// yang sah.
///
/// Catatan: `PermissionProvider` kosong saat pengujian, jadi navigasi bawah
/// hanya menampilkan Dashboard dan "Lainnya". Ketukan yang diandalkan di sini
/// adalah tombol AppBar dan item laci, karena keduanya memanggil `_pilihMenu`
/// tanpa bergantung pada izin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Ukuran ponsel yang lazim; navigasi bawah dan AppBar hanya muncul di sini,
  /// bukan di layar lebar.
  const ukuranPonsel = Size(360, 800);

  Future<void> bukaDasbor(WidgetTester tester) async {
    tester.view.physicalSize = ukuranPonsel;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(bungkusDasbor());
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'dasbor gagal dirender');
  }

  Future<void> bukaProfil(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Menu Akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil Saya'));
    await tester.pumpAndSettle();
  }

  testWidgets('menekan avatar profil di AppBar tidak melempar galat', (tester) async {
    await bukaDasbor(tester);

    // Membuka Profil Saya (menu 81) lewat Menu Akun popup.
    await bukaProfil(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('menekan panah kembali di AppBar tidak melempar galat', (tester) async {
    await bukaDasbor(tester);

    // Dari Dashboard, tombol kirinya adalah menu — jadi pindah dulu ke layar
    // lain supaya panah kembali muncul.
    await bukaProfil(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('memilih menu dari laci tidak melempar galat', (tester) async {
    await bukaDasbor(tester);

    // "Lainnya" di navigasi bawah membuka laci.
    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'laci gagal dibuka');

    // Item Dashboard selalu ada, apa pun izin yang dimiliki role.
    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('berpindah menu berkali-kali tetap aman', (tester) async {
    await bukaDasbor(tester);

    // Gerakan inilah yang dulu membekukan aplikasi: berpindah menu
    // berulang-ulang. Sekali ketuk saja sudah cukup memicu rekursinya, tetapi
    // pengulangan juga menangkap keadaan yang baru rusak setelah beberapa kali
    // pindah — misalnya FAB yang tertinggal dari layar sebelumnya.
    for (int i = 0; i < 3; i++) {
      await bukaProfil(tester);
      expect(tester.takeException(), isNull, reason: 'gagal pada perpindahan ke-${i + 1}');

      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'gagal kembali pada putaran ke-${i + 1}');
    }
  });

  testWidgets('tombol back Android di halaman selain dashboard kembali ke halaman sebelumnya', (tester) async {
    await bukaDasbor(tester);
    await bukaProfil(tester);

    // Kirim sinyal pop navigasi sistem (back button Android)
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Profil Saya'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tombol back Android di dashboard memunculkan dialog konfirmasi keluar aplikasi', (tester) async {
    await bukaDasbor(tester);

    // Kirim sinyal pop navigasi sistem dari dashboard
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Keluar Aplikasi?'), findsOneWidget);
    expect(find.text('Batal'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);

    // Batalkan dialog
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Keluar Aplikasi?'), findsNothing);
  });
}
