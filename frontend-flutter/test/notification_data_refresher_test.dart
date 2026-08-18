import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/services/notification_data_refresher.dart';
import 'package:smart_community/models/notification_intent.dart';
import 'package:smart_community/providers/notification_provider.dart';

import 'bantuan_uji.dart';

Widget _bungkusRefresherTest(Widget Function(BuildContext context) builder) {
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

  group('NotificationDataRefresher: All 11 Entity Types Refresh Mapping', () {
    testWidgets('1. announcement memicu refresh AgendaProvider dan AnnouncementProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'announcement',
            action: 'NEW_ANNOUNCEMENT',
            entityId: '1',
            targetMenuIndex: 50,
            messageId: 'msg_announcement_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('2. emergency memicu refresh EmergencyProvider (segarkanDarurat)', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'emergency',
            action: 'ALARM_TRIGGERED',
            entityId: '911',
            targetMenuIndex: 60,
            messageId: 'msg_emergency_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('3. complaint memicu refresh ComplaintProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'complaint',
            action: 'NEW_COMPLAINT',
            entityId: '10',
            targetMenuIndex: 61,
            messageId: 'msg_complaint_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('4. letter memicu refresh LetterProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'letter',
            action: 'LETTER_STATUS_CHANGED',
            entityId: '20',
            targetMenuIndex: 44,
            messageId: 'msg_letter_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('5 & 6. bill dan payment memicu refresh BillProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final billIntent = NotificationIntent(
            entityType: 'bill',
            action: 'NEW_BILL',
            entityId: '30',
            targetMenuIndex: 21,
            messageId: 'msg_bill_1',
            timestamp: DateTime.now(),
          );

          final paymentIntent = NotificationIntent(
            entityType: 'payment',
            action: 'PAYMENT_SUCCESS',
            entityId: 'ORDER-123',
            targetMenuIndex: 21,
            messageId: 'msg_payment_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final resBill = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, billIntent);
              final resPay = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, paymentIntent);
              expect(resBill, isTrue);
              expect(resPay, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('7. agenda memicu refresh AgendaProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'agenda',
            action: 'NEW_AGENDA',
            entityId: '40',
            targetMenuIndex: 50,
            messageId: 'msg_agenda_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('8. inventory memicu refresh InventoryProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'inventory',
            action: 'BORROWING_STATUS_CHANGED',
            entityId: '50',
            targetMenuIndex: 32,
            messageId: 'msg_inventory_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('9. visitor memicu refresh VisitorProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'visitor',
            action: 'VISITOR_ARRIVED',
            entityId: '60',
            targetMenuIndex: 43,
            messageId: 'msg_visitor_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('10. polling memicu refresh PollingProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'polling',
            action: 'NEW_POLLING',
            entityId: '70',
            targetMenuIndex: 62,
            messageId: 'msg_polling_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });

    testWidgets('11. bansos memicu refresh BantuanSosialProvider', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'bansos',
            action: 'BANSOS_STATUS_UPDATE',
            entityId: '80',
            targetMenuIndex: 13,
            messageId: 'msg_bansos_1',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(result, isTrue);
            },
            child: const Text('Refresh'),
          );
        }),
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
    });
  });

  group('NotificationDataRefresher: Deduplication, Error Handling & Lifecycle', () {
    testWidgets('Deduplikasi mencegah pemanggilan refresh berulang untuk intent yang sama', (tester) async {
      await tester.pumpWidget(
        _bungkusRefresherTest((context) {
          final intent = NotificationIntent(
            entityType: 'complaint',
            action: 'NEW_COMPLAINT',
            entityId: '99',
            targetMenuIndex: 61,
            messageId: 'msg_dedup_test',
            timestamp: DateTime.now(),
          );

          return ElevatedButton(
            onPressed: () async {
              final first = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              final second = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
              expect(first, isTrue);
              expect(second, isFalse); // Pemanggilan kedua diabaikan
            },
            child: const Text('Test Dedup'),
          );
        }),
      );

      await tester.tap(find.text('Test Dedup'));
      await tester.pump();
    });

    testWidgets('Ketiadaan provider dalam context ditangani secara aman tanpa crash', (tester) async {
      // Widget dengan context kosong tanpa provider bisnis
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final intent = NotificationIntent(
                  entityType: 'emergency',
                  targetMenuIndex: 60,
                  messageId: 'msg_isolated_test',
                  timestamp: DateTime.now(),
                );

                return ElevatedButton(
                  onPressed: () async {
                    final result = await NotificationDataRefresher.instance.refreshDataUntukIntent(context, intent);
                    expect(result, isTrue); // Berjalan aman tanpa crash
                  },
                  child: const Text('Test Safe'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test Safe'));
      await tester.pump();
    });

    test('Foreground message tanpa Buka tidak memicu refresh data', () {
      final notifProvider = NotificationProvider();

      // Menerima foreground message
      notifProvider.handleForegroundMessage(
        {'entity_type': 'bill', 'action': 'NEW_BILL', 'entity_id': '100'},
        messageId: 'msg_no_open',
        isLoggedIn: true,
      );

      // Banner muncul tapi activeIntent masih null (belum dieksekusi)
      expect(notifProvider.hasForegroundNotification, isTrue);
      expect(notifProvider.hasActiveIntent, isFalse);
      expect(NotificationDataRefresher.instance.sudahDirefresh(notifProvider.foregroundNotification!), isFalse);
    });

    test('bukaForegroundNotification memindahkan intent ke activeIntent', () {
      final notifProvider = NotificationProvider();

      notifProvider.handleForegroundMessage(
        {'entity_type': 'complaint', 'action': 'NEW_COMPLAINT', 'entity_id': '101'},
        messageId: 'msg_open_test',
        isLoggedIn: true,
      );

      notifProvider.bukaForegroundNotification();

      expect(notifProvider.hasForegroundNotification, isFalse);
      expect(notifProvider.hasActiveIntent, isTrue);
      expect(notifProvider.activeIntent!.entityType, equals('complaint'));
    });

    test('Pending intent pada cold start dieksekusi ke activeIntent setelah login', () {
      final notifProvider = NotificationProvider();

      // Cold start saat app mati & user belum login
      notifProvider.handleNotificationPayload(
        {'entity_type': 'emergency', 'action': 'ALARM_TRIGGERED', 'entity_id': '999'},
        messageId: 'cold_msg_1',
        isLoggedIn: false,
      );

      expect(notifProvider.hasPendingIntent, isTrue);
      expect(notifProvider.hasActiveIntent, isFalse);

      // Pengguna berhasil login -> AuthGate mengonsumsi pending intent
      final consumed = notifProvider.consumePendingIntent();

      expect(consumed, isNotNull);
      expect(notifProvider.hasPendingIntent, isFalse);
      expect(notifProvider.hasActiveIntent, isTrue);
      expect(notifProvider.activeIntent!.entityType, equals('emergency'));
    });
  });
}
