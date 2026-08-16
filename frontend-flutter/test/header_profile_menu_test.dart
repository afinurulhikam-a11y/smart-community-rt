import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/widgets/sidebar_menu.dart';

import 'bantuan_uji.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-uji',
      'user_data': jsonEncode({
        'id': 'user-123',
        'nama': 'Ketua RT 01',
        'role': 'admin',
        'username': 'ketua01',
      }),
    });
  });

  testWidgets('SidebarMenu tidak lagi menampilkan tombol Keluar', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PermissionProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SidebarMenu(
              selectedIndex: 0,
              role: 'admin',
              onItemSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verifikasi bahwa teks "Keluar" dan ikon logout TIDAK ada di SidebarMenu
    expect(find.text('Keluar'), findsNothing);
    expect(find.byIcon(Icons.logout_rounded), findsNothing);
  });

  testWidgets('Header bar desktop memunculkan menu Profil Saya dan Keluar saat diklik', (tester) async {
    pasangKondisi(tester, const KondisiPerangkat(nama: 'desktop', ukuran: Size(1440, 900)));

    await tester.pumpWidget(bungkusDasbor());
    await tester.pump();

    // Pastikan tombol menu akun di header ada
    final menuAkunFinder = find.byType(PopupMenuButton<String>);
    expect(menuAkunFinder, findsOneWidget);

    // Klik menu akun
    await tester.tap(menuAkunFinder);
    await tester.pumpAndSettle();

    // Verifikasi 2 opsi popup menu muncul: Profil Saya dan Keluar
    expect(find.text('Profil Saya'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

    // Klik Keluar -> Dialog konfirmasi keluar harus muncul
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(find.text('Keluar dari akun?'), findsOneWidget);
  });

  testWidgets('AppBar ponsel memunculkan menu Profil Saya dan Keluar saat diklik', (tester) async {
    pasangKondisi(tester, const KondisiPerangkat(nama: 'ponsel', ukuran: Size(360, 800)));

    await tester.pumpWidget(bungkusDasbor());
    await tester.pump();

    // Menu Akun di AppBar ponsel
    final menuAkunMobile = find.byType(PopupMenuButton<String>);
    expect(menuAkunMobile, findsOneWidget);

    // Klik menu akun di AppBar
    await tester.tap(menuAkunMobile);
    await tester.pumpAndSettle();

    // Verifikasi 2 opsi popup menu muncul
    expect(find.text('Profil Saya'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });
}
