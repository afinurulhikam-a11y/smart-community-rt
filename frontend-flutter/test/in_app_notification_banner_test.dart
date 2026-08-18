import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/notification_provider.dart';
import 'package:smart_community/widgets/in_app_notification_banner.dart';

Widget _bungkusWidget({
  required NotificationProvider provider,
  ThemeMode mode = ThemeMode.light,
}) {
  return ChangeNotifierProvider<NotificationProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: const Scaffold(
        body: Column(
          children: [
            InAppNotificationBanner(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InAppNotificationBanner Widget', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    testWidgets('Tidak merender apa pun saat tidak ada foreground notification', (tester) async {
      await tester.pumpWidget(_bungkusWidget(provider: provider));
      await tester.pump();

      expect(find.byType(InAppNotificationBanner), findsOneWidget);
      expect(find.byKey(const Key('in_app_notif_open_btn')), findsNothing);
      expect(find.byKey(const Key('in_app_notif_close_btn')), findsNothing);
    });

    testWidgets('Merender banner lengkap saat foreground notification aktif', (tester) async {
      provider.handleForegroundMessage(
        {
          'entity_type': 'complaint',
          'action': 'NEW_COMPLAINT',
          'entity_id': '50',
          'judul': 'Saluran Air Mampet',
        },
        title: 'Pengaduan Warga Baru',
        body: 'Saluran air di RT 01 mampet',
        isLoggedIn: true,
      );

      await tester.pumpWidget(_bungkusWidget(provider: provider));
      await tester.pump();

      expect(find.text('Pengaduan Warga Baru'), findsOneWidget);
      expect(find.text('Saluran air di RT 01 mampet'), findsOneWidget);
      expect(find.byKey(const Key('in_app_notif_open_btn')), findsOneWidget);
      expect(find.byKey(const Key('in_app_notif_close_btn')), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('Menekan tombol Buka memanggil bukaForegroundNotification dan mengosongkan banner', (tester) async {
      provider.handleForegroundMessage(
        {
          'entity_type': 'agenda',
          'action': 'NEW_AGENDA',
          'entity_id': '10',
          'judul': 'Rapat Warga',
        },
        isLoggedIn: true,
      );

      await tester.pumpWidget(_bungkusWidget(provider: provider));
      await tester.pump();

      expect(find.byKey(const Key('in_app_notif_open_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('in_app_notif_open_btn')));
      await tester.pump();

      // Banner hilang dan activeIntent terisi
      expect(provider.hasForegroundNotification, isFalse);
      expect(provider.hasActiveIntent, isTrue);
      expect(provider.activeIntent!.targetMenuIndex, equals(50));
      expect(find.byKey(const Key('in_app_notif_open_btn')), findsNothing);
    });

    testWidgets('Menekan tombol Tutup memanggil tutupForegroundNotification dan menyembunyikan banner', (tester) async {
      provider.handleForegroundMessage(
        {
          'entity_type': 'emergency',
          'action': 'ALARM_TRIGGERED',
          'entity_id': '99',
        },
        isLoggedIn: true,
      );

      await tester.pumpWidget(_bungkusWidget(provider: provider));
      await tester.pump();

      expect(find.byKey(const Key('in_app_notif_close_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('in_app_notif_close_btn')));
      await tester.pump();

      expect(provider.hasForegroundNotification, isFalse);
      expect(provider.hasActiveIntent, isFalse);
      expect(find.byKey(const Key('in_app_notif_close_btn')), findsNothing);
    });

    testWidgets('Dapat dirender dalam Mode Gelap (Dark Theme) tanpa exception', (tester) async {
      provider.handleForegroundMessage(
        {
          'entity_type': 'bill',
          'action': 'NEW_BILL',
          'entity_id': '77',
          'periode': 'Oktober 2026',
        },
        isLoggedIn: true,
      );

      await tester.pumpWidget(_bungkusWidget(provider: provider, mode: ThemeMode.dark));
      await tester.pump();

      expect(find.text('Tagihan Iuran Baru'), findsOneWidget);
      expect(find.byKey(const Key('in_app_notif_open_btn')), findsOneWidget);
    });
  });
}
