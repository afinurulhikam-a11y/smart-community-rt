import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/widgets/tombol_fullscreen.dart';

import 'bantuan_uji.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-uji',
      'user_data': jsonEncode({
        'id': 'user-123',
        'nama': 'AFI NURUL HIKAM',
        'role': 'admin',
        'username': 'admin01',
      }),
    });
  });

  testWidgets('TombolFullscreen berdiri sendiri: terpasang dan dapat ditekan', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TombolFullscreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TombolFullscreen), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

    // Tekan tombol fullscreen
    await tester.tap(find.byType(TombolFullscreen));
    await tester.pumpAndSettle();
  });

  testWidgets('Tombol fullscreen muncul di header dasbor desktop', (tester) async {
    pasangKondisi(tester, const KondisiPerangkat(nama: 'desktop', ukuran: Size(1440, 900)));

    await tester.pumpWidget(bungkusDasbor());
    await tester.pumpAndSettle();

    expect(find.byType(TombolFullscreen), findsOneWidget);
    expect(find.byTooltip('Layar penuh'), findsOneWidget);
  });

  testWidgets('Tombol fullscreen muncul di app bar dasbor mobile', (tester) async {
    pasangKondisi(tester, const KondisiPerangkat(nama: 'ponsel', ukuran: Size(360, 800)));

    await tester.pumpWidget(bungkusDasbor());
    await tester.pumpAndSettle();

    expect(find.byType(TombolFullscreen), findsOneWidget);
  });
}
