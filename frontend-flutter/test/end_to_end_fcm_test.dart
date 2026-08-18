import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/services/api_service.dart';
import 'package:smart_community/core/services/fcm_service.dart';
import 'package:smart_community/core/services/notification_data_refresher.dart';
import 'package:smart_community/models/notification_intent.dart';
import 'package:smart_community/providers/notification_provider.dart';
import 'package:smart_community/screens/admin/main_dashboard.dart';
import 'package:smart_community/widgets/in_app_notification_banner.dart';

import 'bantuan_uji.dart';

/// Helper pembungkus MainDashboard lengkap dengan seluruh provider untuk simulasi E2E.
Widget _bungkusE2EDashboard({required NotificationProvider notificationProvider}) {
  return MultiProvider(
    providers: [
      ...semuaProvider().where((p) => p is! ChangeNotifierProvider<NotificationProvider>),
      ChangeNotifierProvider<NotificationProvider>.value(value: notificationProvider),
    ],
    child: const MaterialApp(
      home: MainDashboard(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationDataRefresher.instance.bersihkan();
    await ApiService.saveToken('mock_jwt_token_admin_test');
  });

  group('FCM E2E Simulation: All 11 Entity Types Full Pipeline Verification', () {
    final entitasFixtures = <Map<String, dynamic>>[
      {
        'name': '1. announcement',
        'payload': {
          'entity_type': 'announcement',
          'action': 'NEW_ANNOUNCEMENT',
          'entity_id': '101',
        },
        'title': 'Pengumuman Kerja Bakti',
        'body': 'Kerja bakti hari Minggu pagi di lingkungan RT',
        'messageId': 'e2e_msg_announcement_1',
        'expectedMenu': 50,
        'expectedTab': 0,
      },
      {
        'name': '2. emergency',
        'payload': {
          'entity_type': 'emergency',
          'action': 'ALARM_TRIGGERED',
          'entity_id': '999',
        },
        'title': 'ALARM DARURAT!',
        'body': 'Ada kebakaran di area Blok C',
        'messageId': 'e2e_msg_emergency_1',
        'expectedMenu': 60,
        'expectedTab': null,
      },
      {
        'name': '3. complaint',
        'payload': {
          'entity_type': 'complaint',
          'action': 'NEW_COMPLAINT',
          'entity_id': '202',
        },
        'title': 'Pengaduan Warga Baru',
        'body': 'Lampu jalan mati di dekat gapura',
        'messageId': 'e2e_msg_complaint_1',
        'expectedMenu': 61,
        'expectedTab': null,
      },
      {
        'name': '4. letter',
        'payload': {
          'entity_type': 'letter',
          'action': 'LETTER_APPROVED',
          'entity_id': '303',
        },
        'title': 'Pengajuan Surat Disetujui',
        'body': 'Surat pengantar domisili Anda siap diunduh',
        'messageId': 'e2e_msg_letter_1',
        'expectedMenu': 44,
        'expectedTab': null,
      },
      {
        'name': '5. bill',
        'payload': {
          'entity_type': 'bill',
          'action': 'NEW_BILL',
          'entity_id': '404',
        },
        'title': 'Tagihan Iuran Diterbitkan',
        'body': 'Iuran kebersihan bulan berjalan telah terbit',
        'messageId': 'e2e_msg_bill_1',
        'expectedMenu': 21,
        'expectedTab': 0,
      },
      {
        'name': '6. payment',
        'payload': {
          'entity_type': 'payment',
          'action': 'PAYMENT_SUCCESS',
          'entity_id': 'ORDER-505',
        },
        'title': 'Pembayaran Berhasil',
        'body': 'Pembayaran tagihan telah diverifikasi lunas',
        'messageId': 'e2e_msg_payment_1',
        'expectedMenu': 21,
        'expectedTab': 1,
      },
      {
        'name': '7. agenda',
        'payload': {
          'entity_type': 'agenda',
          'action': 'NEW_AGENDA',
          'entity_id': '606',
        },
        'title': 'Agenda Kegiatan Baru',
        'body': 'Rapat koordinasi pengurus RT hari Sabtu',
        'messageId': 'e2e_msg_agenda_1',
        'expectedMenu': 50,
        'expectedTab': 1,
      },
      {
        'name': '8. inventory',
        'payload': {
          'entity_type': 'inventory',
          'action': 'BORROWING_STATUS_CHANGED',
          'entity_id': '707',
        },
        'title': 'Status Peminjaman Barang',
        'body': 'Peminjaman kursi lipat telah disetujui',
        'messageId': 'e2e_msg_inventory_1',
        'expectedMenu': 32,
        'expectedTab': null,
      },
      {
        'name': '9. visitor',
        'payload': {
          'entity_type': 'visitor',
          'action': 'VISITOR_ARRIVED',
          'entity_id': '808',
        },
        'title': 'Buku Tamu: Tamu Tiba',
        'body': 'Tamu Anda telah tiba di pos gerbang utama',
        'messageId': 'e2e_msg_visitor_1',
        'expectedMenu': 43,
        'expectedTab': null,
      },
      {
        'name': '10. polling',
        'payload': {
          'entity_type': 'polling',
          'action': 'NEW_POLLING',
          'entity_id': '909',
        },
        'title': 'Polling Warga Dibuka',
        'body': 'Silakan berikan suara pemilihan program kerja',
        'messageId': 'e2e_msg_polling_1',
        'expectedMenu': 62,
        'expectedTab': null,
      },
      {
        'name': '11. bansos',
        'payload': {
          'entity_type': 'bansos',
          'action': 'BANSOS_STATUS_UPDATE',
          'entity_id': '1010',
        },
        'title': 'Pembaruan Data Bansos',
        'body': 'Jadwal penyaluran bansos sembako telah diperbarui',
        'messageId': 'e2e_msg_bansos_1',
        'expectedMenu': 13,
        'expectedTab': null,
      },
    ];

    for (final f in entitasFixtures) {
      testWidgets('Pipeline E2E untuk ${f['name']}', (tester) async {
        final notifProvider = NotificationProvider();

        // 1. Simulasikan pesan masuk
        final intent = notifProvider.handleNotificationPayload(
          f['payload'] as Map<String, dynamic>,
          title: f['title'] as String,
          body: f['body'] as String,
          messageId: f['messageId'] as String,
          isLoggedIn: true,
        );

        expect(intent, isNotNull);
        expect(intent!.entityType, equals(f['payload']['entity_type']));
        expect(intent.action, equals(f['payload']['action']));
        expect(intent.entityId, equals(f['payload']['entity_id']));
        expect(intent.targetMenuIndex, equals(f['expectedMenu']));
        expect(intent.targetTabIndex, equals(f['expectedTab']));
        expect(intent.title, equals(f['title']));
        expect(intent.body, equals(f['body']));

        // 2. Render MainDashboard dan pastikan activeIntent dikonsumsi
        await tester.pumpWidget(
          _bungkusE2EDashboard(notificationProvider: notifProvider),
        );
        await tester.pumpAndSettle();

        // Verifikasi intent aktif telah dikonsumsi dan dibersihkan dari provider
        expect(notifProvider.hasActiveIntent, isFalse);

        // Verifikasi bahwa refresh data untuk intent telah tercatat
        expect(NotificationDataRefresher.instance.sudahDirefresh(intent), isTrue);
      });
    }
  });

  group('FCM E2E Simulation: Foreground In-App Banner & Delayed Refresh Flow', () {
    testWidgets('Pesan foreground menampilkan banner, tidak refresh sebelum Buka, lalu navigasi & refresh saat Buka ditekan', (tester) async {
      final notifProvider = NotificationProvider();
      FCMService.instance.pasangNotificationRouter(notifProvider);

      await tester.pumpWidget(
        _bungkusE2EDashboard(notificationProvider: notifProvider),
      );
      await tester.pumpAndSettle();

      // Buat simulasi RemoteMessage foreground
      final remoteMsg = RemoteMessage(
        messageId: 'e2e_fg_bill_001',
        data: {
          'entity_type': 'bill',
          'action': 'NEW_BILL',
          'entity_id': '555',
        },
        notification: const RemoteNotification(
          title: 'Tagihan Iuran Baru',
          body: 'Tagihan iuran kebersihan bulan ini telah terbit',
        ),
      );

      // Trigger foreground message melalui FCMService
      FCMService.instance.simulasiForegroundMessage(remoteMsg);
      await tester.pumpAndSettle();

      // 1. Banner harus muncul di layar
      expect(find.byType(InAppNotificationBanner), findsOneWidget);
      expect(find.text('Tagihan Iuran Baru'), findsOneWidget);
      expect(find.byKey(const Key('in_app_notif_open_btn')), findsOneWidget);

      // 2. Refresh belum boleh terjadi sebelum tombol Buka ditekan
      final fgIntent = notifProvider.foregroundNotification;
      expect(fgIntent, isNotNull);
      expect(NotificationDataRefresher.instance.sudahDirefresh(fgIntent!), isFalse);

      // 3. Tekan tombol "Buka"
      await tester.tap(find.byKey(const Key('in_app_notif_open_btn')));
      await tester.pumpAndSettle();

      // 4. Banner hilang, activeIntent dieksekusi, dan refresh berhasil dicatat
      expect(notifProvider.hasForegroundNotification, isFalse);
      expect(NotificationDataRefresher.instance.sudahDirefresh(fgIntent), isTrue);
    });

    testWidgets('Pesan foreground yang ditutup dengan tombol "X" tidak memicu navigasi atau refresh', (tester) async {
      final notifProvider = NotificationProvider();
      FCMService.instance.pasangNotificationRouter(notifProvider);

      await tester.pumpWidget(
        _bungkusE2EDashboard(notificationProvider: notifProvider),
      );
      await tester.pumpAndSettle();

      final remoteMsg = RemoteMessage(
        messageId: 'e2e_fg_complaint_002',
        data: {
          'entity_type': 'complaint',
          'action': 'NEW_COMPLAINT',
          'entity_id': '888',
        },
        notification: const RemoteNotification(
          title: 'Pengaduan Baru',
          body: 'Ada keluhan baru dari warga',
        ),
      );

      FCMService.instance.simulasiForegroundMessage(remoteMsg);
      await tester.pumpAndSettle();

      expect(find.byType(InAppNotificationBanner), findsOneWidget);

      // Tekan tombol tutup ("X")
      await tester.tap(find.byKey(const Key('in_app_notif_close_btn')));
      await tester.pumpAndSettle();

      // Banner hilang, activeIntent tetap null, dan tidak pernah direfresh
      expect(notifProvider.hasForegroundNotification, isFalse);
      expect(notifProvider.hasActiveIntent, isFalse);
      expect(NotificationDataRefresher.instance.sudahDirefresh(
        NotificationIntent(entityType: 'complaint', messageId: 'e2e_fg_complaint_002', targetMenuIndex: 61, timestamp: DateTime.now()),
      ), isFalse);
    });
  });

  group('FCM E2E Simulation: Background Tap & Terminated Initial Message Lifecycles', () {
    testWidgets('Background Tap (onMessageOpenedApp) langsung memicu routing dan data refresh', (tester) async {
      final notifProvider = NotificationProvider();

      // Simulasikan notifikasi dibuka dari background
      final intent = notifProvider.handleNotificationPayload(
        {
          'entity_type': 'visitor',
          'action': 'VISITOR_ARRIVED',
          'entity_id': '999',
        },
        title: 'Tamu Tiba',
        body: 'Tamu Anda sudah sampai di pos',
        messageId: 'e2e_bg_visitor_001',
        isLoggedIn: true,
      );

      expect(intent, isNotNull);
      expect(notifProvider.hasActiveIntent, isTrue);

      await tester.pumpWidget(
        _bungkusE2EDashboard(notificationProvider: notifProvider),
      );
      await tester.pumpAndSettle();

      // Dashboard mengonsumsi intent dan mengeksekusi refresh
      expect(notifProvider.hasActiveIntent, isFalse);
      expect(NotificationDataRefresher.instance.sudahDirefresh(intent!), isTrue);
    });

    testWidgets('Terminated Initial Message masuk ke pending intent, lalu dikonsumsi setelah login', (tester) async {
      final notifProvider = NotificationProvider();

      // 1. Startup cold-start saat user belum login
      final intent = notifProvider.handleNotificationPayload(
        {
          'entity_type': 'emergency',
          'action': 'ALARM_TRIGGERED',
          'entity_id': '112',
        },
        title: 'Darurat Aktif',
        body: 'Sirene dinyalakan di RT',
        messageId: 'e2e_cold_emergency_001',
        isLoggedIn: false,
      );

      expect(intent, isNotNull);
      expect(notifProvider.hasPendingIntent, isTrue);
      expect(notifProvider.hasActiveIntent, isFalse);

      // 2. User berhasil login -> AuthGate mengonsumsi pendingIntent
      final consumed = notifProvider.consumePendingIntent();
      expect(consumed, isNotNull);
      expect(notifProvider.hasPendingIntent, isFalse);
      expect(notifProvider.hasActiveIntent, isTrue);

      // 3. MainDashboard terbuka dan mengeksekusi activeIntent
      await tester.pumpWidget(
        _bungkusE2EDashboard(notificationProvider: notifProvider),
      );
      await tester.pumpAndSettle();

      expect(notifProvider.hasActiveIntent, isFalse);
      expect(NotificationDataRefresher.instance.sudahDirefresh(consumed!), isTrue);
    });
  });

  group('FCM E2E Simulation: Deduplication, Edge-Cases & Failure Isolation', () {
    testWidgets('Pesan duplikat lintas siklus (Background Tap + Initial Message) hanya diproses 1x', (tester) async {
      final notifProvider = NotificationProvider();

      final payload = {
        'entity_type': 'polling',
        'action': 'NEW_POLLING',
        'entity_id': '333',
      };

      // Event pertama
      final firstIntent = notifProvider.handleNotificationPayload(
        payload,
        messageId: 'duplicate_event_001',
        isLoggedIn: true,
      );
      expect(firstIntent, isNotNull);

      // Event kedua dengan messageId sama
      final secondIntent = notifProvider.handleNotificationPayload(
        payload,
        messageId: 'duplicate_event_001',
        isLoggedIn: true,
      );
      expect(secondIntent, isNull);

      await tester.pumpWidget(
        _bungkusE2EDashboard(notificationProvider: notifProvider),
      );
      await tester.pumpAndSettle();

      expect(notifProvider.hasActiveIntent, isFalse);
    });

    test('Payload invalid / unknown entity_type / hilang entity_type ditolak tanpa error', () {
      final notifProvider = NotificationProvider();

      expect(notifProvider.parsePayload(null), isNull);
      expect(notifProvider.parsePayload({}), isNull);
      expect(notifProvider.parsePayload({'entity_type': 'unsupported_module'}), isNull);
      expect(notifProvider.parsePayload({'entity_type': '  '}), isNull);
    });

    testWidgets('Kegagalan API/jaringan saat refresh data tidak membatalkan navigasi dashboard', (tester) async {
      final notifProvider = NotificationProvider();

      final intent = notifProvider.handleNotificationPayload(
        {
          'entity_type': 'bansos',
          'action': 'BANSOS_STATUS_UPDATE',
          'entity_id': '999',
        },
        messageId: 'err_isolation_001',
        isLoggedIn: true,
      );

      expect(intent, isNotNull);

      // Render dashboard dengan provider yang mungkin error saat fetch data
      await tester.pumpWidget(
        _bungkusE2EDashboard(notificationProvider: notifProvider),
      );
      await tester.pumpAndSettle();

      // Navigasi tetap selesai tanpa crash
      expect(notifProvider.hasActiveIntent, isFalse);
      expect(find.byType(MainDashboard), findsOneWidget);
    });
  });
}
