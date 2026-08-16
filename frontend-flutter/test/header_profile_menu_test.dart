import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/action_provider.dart';
import 'package:smart_community/providers/bill_provider.dart';
import 'package:smart_community/providers/complaint_provider.dart';
import 'package:smart_community/providers/demographic_provider.dart';
import 'package:smart_community/providers/emergency_provider.dart';
import 'package:smart_community/providers/finance_provider.dart';
import 'package:smart_community/providers/letter_provider.dart';
import 'package:smart_community/providers/bop_provider.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/providers/polling_provider.dart';
import 'package:smart_community/providers/websocket_service.dart';
import 'package:smart_community/screens/admin/main_dashboard.dart';
import 'package:smart_community/widgets/sidebar_menu.dart';

Widget _susunMainDashboard({required AuthService auth}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider(create: (_) => AksiUtamaProvider()),
      ChangeNotifierProvider(create: (_) => FinanceProvider()),
      ChangeNotifierProvider(create: (_) => BillProvider()),
      ChangeNotifierProvider(create: (_) => DemographicProvider()),
      ChangeNotifierProvider(create: (_) => EmergencyProvider()),
      ChangeNotifierProvider(create: (_) => ComplaintProvider()),
      ChangeNotifierProvider(create: (_) => LetterProvider()),
      ChangeNotifierProvider(create: (_) => BopProvider()),
      ChangeNotifierProvider(create: (_) => PermissionProvider()),
      ChangeNotifierProvider(create: (_) => PollingProvider()),
      ChangeNotifierProvider(create: (_) => WebSocketService()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const MainDashboard(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-uji',
      'user_data': jsonEncode({
        'id': 'user-123',
        'nama': 'Ketua RT 01',
        'role': 'ketua_rt',
        'username': 'ketua01',
      }),
    });
  });

  testWidgets('SidebarMenu tidak lagi menampilkan tombol Keluar', (tester) async {
    final auth = AuthService();
    auth.pasangUji(user: {
      'id': 'user-123',
      'nama': 'Ketua RT 01',
      'role': 'ketua_rt',
      'username': 'ketua01',
    });

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
              role: 'ketua_rt',
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
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final auth = AuthService();
    auth.pasangUji(user: {
      'id': 'user-123',
      'nama': 'Ketua RT 01',
      'role': 'ketua_rt',
      'username': 'ketua01',
    });

    await tester.pumpWidget(_susunMainDashboard(auth: auth));
    await tester.pumpAndSettle();

    // Pastikan tombol menu akun di header ada
    final menuAkunFinder = find.byTooltip('Menu Akun (Ketua RT)');
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
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final auth = AuthService();
    auth.pasangUji(user: {
      'id': 'user-123',
      'nama': 'Ketua RT 01',
      'role': 'ketua_rt',
      'username': 'ketua01',
    });

    await tester.pumpWidget(_susunMainDashboard(auth: auth));
    await tester.pumpAndSettle();

    // Menu Akun di AppBar ponsel
    final menuAkunMobile = find.byTooltip('Menu Akun');
    expect(menuAkunMobile, findsOneWidget);

    // Klik menu akun di AppBar
    await tester.tap(menuAkunMobile);
    await tester.pumpAndSettle();

    // Verifikasi 2 opsi popup menu muncul
    expect(find.text('Profil Saya'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });
}
