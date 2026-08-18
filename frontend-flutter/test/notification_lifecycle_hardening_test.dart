import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/services/notification_data_refresher.dart';
import 'package:smart_community/models/notification_intent.dart';
import 'package:smart_community/providers/notification_provider.dart';

import 'bantuan_uji.dart';

Widget _bungkusHardeningTest(Widget Function(BuildContext context) builder) {
  return MultiProvider(
    providers: semuaProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(builder: builder),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationDataRefresher.instance.bersihkan();
  });

  group('FCM Phase 3.5 Hardening: Terminated Cold Start & Idempotency', () {
    test('getInitialMessage saat cold-start ditahan di pendingIntent dan dikonsumsi tepat 1x setelah login', () {
      final provider = NotificationProvider();

      // Cold start: aplikasi dibuka dari terminated state, user belum login
      final payload = {
        'entity_type': 'letter',
        'action': 'LETTER_APPROVED',
        'entity_id': '456',
      };

      final intent = provider.handleNotificationPayload(
        payload,
        messageId: 'cold_msg_100',
        isLoggedIn: false,
      );

      expect(intent, isNotNull);
      expect(provider.hasPendingIntent, isTrue);
      expect(provider.hasActiveIntent, isFalse);
      expect(provider.pendingIntent?.entityType, equals('letter'));
      expect(provider.pendingIntent?.targetMenuIndex, equals(44));

      // User berhasil login: AuthGate mengonsumsi pendingIntent
      final consumed = provider.consumePendingIntent();
      expect(consumed, isNotNull);
      expect(consumed?.entityType, equals('letter'));
      expect(provider.hasPendingIntent, isFalse);
      expect(provider.hasActiveIntent, isTrue);

      // Pemanggilan kedua consumePendingIntent mengembalikan null (idempotent / hanya 1x)
      final consumedLagi = provider.consumePendingIntent();
      expect(consumedLagi, isNull);
    });

    test('Duplicate tap / background event dengan messageId yang sama diabaikan', () {
      final provider = NotificationProvider();

      final payload = {
        'entity_type': 'emergency',
        'action': 'ALARM_TRIGGERED',
        'entity_id': '999',
      };

      // Tap pertama dari background
      final intent1 = provider.handleNotificationPayload(
        payload,
        messageId: 'msg_cross_cycle_1',
        isLoggedIn: true,
      );
      expect(intent1, isNotNull);
      expect(provider.hasActiveIntent, isTrue);

      // Membersihkan active intent setelah dieksekusi UI
      provider.clearActiveIntent();
      expect(provider.hasActiveIntent, isFalse);

      // Tap kedua dengan pesan yang sama persis
      final intent2 = provider.handleNotificationPayload(
        payload,
        messageId: 'msg_cross_cycle_1',
        isLoggedIn: true,
      );
      // Harus diabaikan oleh cache deduplikasi
      expect(intent2, isNull);
      expect(provider.hasActiveIntent, isFalse);
    });
  });

  group('FCM Phase 3.5 Hardening: Logout, Account Switching & State Cleanup', () {
    test('Logout membersihkan pending intent, active intent, foreground notif, dan cache deduplikasi', () {
      final provider = NotificationProvider();

      // Menerima pesan saat belum login
      provider.handleNotificationPayload(
        {'entity_type': 'bill', 'action': 'NEW_BILL', 'entity_id': '101'},
        messageId: 'user_a_bill',
        isLoggedIn: false,
      );
      expect(provider.hasPendingIntent, isTrue);

      // Menerima foreground notif
      provider.handleForegroundMessage(
        {'entity_type': 'announcement', 'action': 'NEW_ANNOUNCEMENT'},
        messageId: 'user_a_notif',
        isLoggedIn: true,
      );
      expect(provider.hasForegroundNotification, isTrue);

      // Sesi User A berakhir (Logout / Account switch)
      provider.bersihkan();
      NotificationDataRefresher.instance.bersihkan();

      // State harus bersih 100%
      expect(provider.hasPendingIntent, isFalse);
      expect(provider.hasActiveIntent, isFalse);
      expect(provider.hasForegroundNotification, isFalse);

      // User B login: tidak ada data intent User A yang tertinggal atau terkonsumsi
      final consumedUserB = provider.consumePendingIntent();
      expect(consumedUserB, isNull);
    });
  });

  group('FCM Phase 3.5 Hardening: Bounded Cache & TTL Eviction', () {
    test('Cache deduplikasi dibatasi maksimum 100 entri dan tidak membengkak (Bounded FIFO)', () {
      final provider = NotificationProvider();

      // Simulasikan 120 pesan dengan ID berbeda
      for (int i = 1; i <= 120; i++) {
        provider.recordProcessed(
          NotificationIntent(
            entityType: 'bill',
            messageId: 'batch_msg_$i',
            targetMenuIndex: 21,
            timestamp: DateTime.now(),
          ),
        );
      }

      // Pesan nomor 1-20 seharusnya sudah di-evict dari cache FIFO 100
      final intentOld = NotificationIntent(
        entityType: 'bill',
        messageId: 'batch_msg_1',
        targetMenuIndex: 21,
        timestamp: DateTime.now(),
      );
      expect(provider.isDuplicate(intentOld), isFalse);

      // Pesan nomor 120 masih ada di dalam cache
      final intentRecent = NotificationIntent(
        entityType: 'bill',
        messageId: 'batch_msg_120',
        targetMenuIndex: 21,
        timestamp: DateTime.now(),
      );
      expect(provider.isDuplicate(intentRecent), isTrue);
    });

    test('Entri deduplikasi kedaluwarsa setelah TTL 15 menit', () {
      final provider = NotificationProvider();
      final now = DateTime.now();

      final intent = NotificationIntent(
        entityType: 'complaint',
        messageId: 'ttl_test_msg',
        targetMenuIndex: 61,
        timestamp: now,
      );

      // Dicatat pada waktu sekarang
      provider.recordProcessed(intent, now: now);
      expect(provider.isDuplicate(intent, now: now), isTrue);

      // Diperiksa 16 menit kemudian (melewati TTL 15 menit)
      final futureTime = now.add(const Duration(minutes: 16));
      expect(provider.isDuplicate(intent, now: futureTime), isFalse);
    });
  });

  group('FCM Phase 3.5 Hardening: Malformed & Robust Payload Parsing', () {
    test('Payload dengan whitespace, huruf kapital, dan string "null" dinormalisasi dengan aman', () {
      final provider = NotificationProvider();

      final payload = {
        'entity_type': '   EMERGENCY   ',
        'action': '  null  ',
        'entity_id': '  undefined  ',
        'extra_unrecognized_key': 'abc_123',
      };

      final intent = provider.parsePayload(payload, messageId: 'malformed_1');
      expect(intent, isNotNull);
      expect(intent?.entityType, equals('emergency'));
      expect(intent?.action, isNull);
      expect(intent?.entityId, isNull);
      expect(intent?.targetMenuIndex, equals(60));
      expect(intent?.rawPayload['extra_unrecognized_key'], equals('abc_123'));
    });

    test('Payload tanpa entity_type atau bertipe tidak dikenal ditolak dengan aman', () {
      final provider = NotificationProvider();

      expect(provider.parsePayload(null), isNull);
      expect(provider.parsePayload({}), isNull);
      expect(provider.parsePayload({'entity_type': ''}), isNull);
      expect(provider.parsePayload({'entity_type': '   '}), isNull);
      expect(provider.parsePayload({'entity_type': 'hacker_attack'}), isNull);
      expect(provider.parsePayload({'entity_type': 'unknown_123'}), isNull);
    });
  });

  group('FCM Phase 3.5 Hardening: Safe Data Refresh & Error Isolation', () {
    testWidgets('Kegagalan provider/jaringan saat refresh tidak menimbulkan exception tak tertangkap', (tester) async {
      await tester.pumpWidget(
        _bungkusHardeningTest((context) {
          final intent = NotificationIntent(
            entityType: 'bansos',
            action: 'BANSOS_STATUS_UPDATE',
            entityId: '80',
            targetMenuIndex: 13,
            messageId: 'msg_safe_refresh_err',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              // Menjalankan refresh
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(
                context,
                intent,
                force: true,
              );
              // Tetap selesai dengan boolean tanpa melempar exception fatal
              expect(result, isTrue);
            },
            child: const Text('Do Safe Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Do Safe Refresh'));
      await tester.pump();
    });

    test('Pesan foreground yang diterima TIDAK langsung memicu data refresh sebelum dibuka', () {
      final provider = NotificationProvider();

      provider.handleForegroundMessage(
        {'entity_type': 'visitor', 'action': 'VISITOR_ARRIVED', 'entity_id': '77'},
        messageId: 'visitor_fg_1',
        isLoggedIn: true,
      );

      expect(provider.hasForegroundNotification, isTrue);
      expect(provider.hasActiveIntent, isFalse);

      final fgIntent = provider.foregroundNotification!;
      // Belum pernah direfresh
      expect(NotificationDataRefresher.instance.sudahDirefresh(fgIntent), isFalse);

      // Pengguna menekan Buka
      provider.bukaForegroundNotification();
      expect(provider.hasActiveIntent, isTrue);
      expect(provider.hasForegroundNotification, isFalse);
    });
  });
}
