import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/screens/login_screen.dart';

/// Menjaga agar layar login tidak pernah lagi rusak di layar sempit.
///
/// Panel kirinya pernah berupa Stack yang SELURUH anaknya Positioned. Stack
/// menentukan ukuran dari anak yang tidak ber-Positioned; tanpa satu pun, ia
/// jatuh ke constraints.biggest. Di desktop itu aman karena tingginya dipatok
/// Container(height: 540), tetapi di ponsel panel itu anak Flex vertikal di
/// dalam SingleChildScrollView — tingginya tak terbatas — sehingga layar login
/// gagal dirender dengan "A Stack requires bounded constraints from its parent".
///
/// Cacat itu hanya muncul di perangkat sempit, jadi pengujian ini merender
/// pada beberapa ukuran nyata sekaligus.
void main() {
  Widget bungkus() => ChangeNotifierProvider(
        create: (_) => AuthService(),
        child: const MaterialApp(home: LoginScreen()),
      );

  /// Lebar/tinggi logis beberapa perangkat, termasuk yang paling sempit.
  const ukuran = <String, Size>{
    'ponsel kecil (320x568)': Size(320, 568),
    'ponsel umum (360x800)': Size(360, 800),
    'ponsel besar (412x915)': Size(412, 915),
    'tablet (800x1280)': Size(800, 1280),
    'desktop (1440x900)': Size(1440, 900),
  };

  ukuran.forEach((nama, size) {
    testWidgets('layar login dirender tanpa error pada $nama', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bungkus());
      await tester.pump();

      // takeException() mengembalikan error layout apa pun yang terlempar saat
      // render — termasuk assertion Stack yang dulu meruntuhkan layar ini.
      expect(tester.takeException(), isNull);

      // Judul panel kiri harus benar-benar ikut terpasang, bukan sekadar
      // "tidak error" karena widget-nya tidak pernah dirender.
      expect(find.textContaining('Informasi RT'), findsWidgets);
    });
  });

  testWidgets('kolom login bisa diisi dan tombolnya ada di layar ponsel',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(bungkus());
    await tester.pump();

    final kolom = find.byType(TextField);
    expect(kolom, findsNWidgets(2));

    await tester.enterText(kolom.at(0), 'warga@example.com');
    await tester.enterText(kolom.at(1), 'warga123');
    await tester.pump();

    expect(find.text('warga@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// Layar masuk harus muat satu layar penuh di ponsel.
  ///
  /// Bentuk desktop-nya menumpuk panel promosi di atas formulir; ditumpuk
  /// vertikal di ponsel, hasilnya lebih tinggi dari layar sehingga pengguna
  /// harus menggulir hanya untuk mencapai tombol Masuk. Yang menjaganya
  /// sekarang adalah kepala ringkas + ConstrainedBox(minHeight) —
  /// dan pengujian ini, karena tinggi isi mudah bertambah lagi tanpa disadari.
  for (final size in const [Size(320, 568), Size(360, 800), Size(412, 915)]) {
    testWidgets('layar login tidak perlu digulir pada ${size.width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bungkus());
      await tester.pump();

      final posisi = tester.widget<Scrollable>(find.byType(Scrollable).first).controller;
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);

      // maxScrollExtent nol berarti isinya sudah muat — tidak ada yang bisa
      // digulir sama sekali.
      expect(
        scroll.position.maxScrollExtent,
        0,
        reason: 'isi layar login melebihi tinggi layar ${size.height.toInt()}px',
      );
      expect(posisi, anything);
      expect(tester.takeException(), isNull);
    });
  }
}
