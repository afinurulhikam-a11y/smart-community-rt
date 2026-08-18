import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/services/api_service.dart';
import 'package:smart_community/core/services/fcm_service.dart';
import 'package:smart_community/models/notification_intent.dart';
import 'package:smart_community/providers/notification_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationIntent Model', () {
    test('DeduplicationKey menggunakan messageId bila tersedia', () {
      final intent = NotificationIntent(
        entityType: 'complaint',
        action: 'NEW_COMPLAINT',
        entityId: '10',
        targetMenuIndex: 61,
        messageId: 'msg_fcm_001',
        timestamp: DateTime(2026, 8, 18, 10, 0),
      );

      expect(intent.deduplicationKey, equals('msg_fcm_001'));
    });

    test('DeduplicationKey membentuk fallback signature dari payload jika messageId null', () {
      final intent = NotificationIntent(
        entityType: 'bill',
        action: 'NEW_BILL',
        entityId: '99',
        targetMenuIndex: 21,
        rawPayload: {'created_at': '2026-08-18T10:00:00Z'},
        timestamp: DateTime(2026, 8, 18, 10, 0),
      );

      expect(intent.deduplicationKey, equals('bill:NEW_BILL:99:2026-08-18T10:00:00Z'));
    });

    test('Equality dan hashCode bekerja dengan benar', () {
      final t1 = DateTime(2026, 8, 18);
      final intent1 = NotificationIntent(
        entityType: 'letter',
        action: 'LETTER_STATUS_CHANGED',
        entityId: '5',
        targetMenuIndex: 44,
        targetTabIndex: null,
        messageId: 'msg_1',
        timestamp: t1,
      );
      final intent2 = NotificationIntent(
        entityType: 'letter',
        action: 'LETTER_STATUS_CHANGED',
        entityId: '5',
        targetMenuIndex: 44,
        targetTabIndex: null,
        messageId: 'msg_1',
        timestamp: t1,
      );

      expect(intent1, equals(intent2));
      expect(intent1.hashCode, equals(intent2.hashCode));
    });
  });

  group('NotificationProvider: Payload Parsing & Mapping 11 Entity Types', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    test('1. announcement -> targetMenuIndex: 50, targetTabIndex: 0', () {
      final intent = provider.parsePayload({
        'entity_type': 'announcement',
        'entity_id': '101',
        'kategori': 'Umum',
      });

      expect(intent, isNotNull);
      expect(intent!.entityType, equals('announcement'));
      expect(intent.targetMenuIndex, equals(50));
      expect(intent.targetTabIndex, equals(0));
      expect(intent.entityId, equals('101'));
    });

    test('2. emergency -> targetMenuIndex: 60', () {
      final intent = provider.parsePayload({
        'entity_type': 'emergency',
        'action': 'ALARM_TRIGGERED',
        'entity_id': '888',
        'status': 'active',
      });

      expect(intent, isNotNull);
      expect(intent!.entityType, equals('emergency'));
      expect(intent.action, equals('ALARM_TRIGGERED'));
      expect(intent.targetMenuIndex, equals(60));
      expect(intent.targetTabIndex, isNull);
      expect(intent.entityId, equals('888'));
    });

    test('3. complaint -> targetMenuIndex: 61', () {
      final intentNew = provider.parsePayload({
        'entity_type': 'complaint',
        'action': 'NEW_COMPLAINT',
        'entity_id': '12',
        'kode_tiket': 'ADU-2026-001',
      });
      expect(intentNew, isNotNull);
      expect(intentNew!.targetMenuIndex, equals(61));
      expect(intentNew.action, equals('NEW_COMPLAINT'));

      final intentReplied = provider.parsePayload({
        'entity_type': 'complaint',
        'action': 'COMPLAINT_REPLIED',
        'entity_id': '12',
      });
      expect(intentReplied, isNotNull);
      expect(intentReplied!.targetMenuIndex, equals(61));
      expect(intentReplied.action, equals('COMPLAINT_REPLIED'));
    });

    test('4. letter -> targetMenuIndex: 44', () {
      final intentNew = provider.parsePayload({
        'entity_type': 'letter',
        'action': 'NEW_LETTER_REQUEST',
        'entity_id': '77',
      });
      expect(intentNew, isNotNull);
      expect(intentNew!.targetMenuIndex, equals(44));

      final intentStatus = provider.parsePayload({
        'entity_type': 'letter',
        'action': 'LETTER_STATUS_CHANGED',
        'entity_id': '77',
      });
      expect(intentStatus, isNotNull);
      expect(intentStatus!.targetMenuIndex, equals(44));
    });

    test('5. bill -> targetMenuIndex: 21, NEW_BILL -> targetTabIndex: 0', () {
      final intent = provider.parsePayload({
        'entity_type': 'bill',
        'action': 'NEW_BILL',
        'entity_id': '450',
        'periode': 'Agustus 2026',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(21));
      expect(intent.targetTabIndex, equals(0));
      expect(intent.entityId, equals('450'));
    });

    test('6. payment -> targetMenuIndex: 21, PAYMENT_SUCCESS -> targetTabIndex: 1', () {
      final intent = provider.parsePayload({
        'entity_type': 'payment',
        'action': 'PAYMENT_SUCCESS',
        'entity_id': 'ORDER-12345',
        'status': 'settlement',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(21));
      expect(intent.targetTabIndex, equals(1));
      expect(intent.entityId, equals('ORDER-12345'));
    });

    test('7. agenda -> targetMenuIndex: 50, NEW_AGENDA -> targetTabIndex: 1', () {
      final intent = provider.parsePayload({
        'entity_type': 'agenda',
        'action': 'NEW_AGENDA',
        'entity_id': '33',
        'judul': 'Kerja Bakti',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(50));
      expect(intent.targetTabIndex, equals(1));
      expect(intent.entityId, equals('33'));
    });

    test('8. inventory -> targetMenuIndex: 32', () {
      final intent = provider.parsePayload({
        'entity_type': 'inventory',
        'action': 'BORROWING_STATUS_CHANGED',
        'entity_id': '19',
        'status': 'dipinjam',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(32));
      expect(intent.entityId, equals('19'));
    });

    test('9. visitor -> targetMenuIndex: 43', () {
      final intent = provider.parsePayload({
        'entity_type': 'visitor',
        'action': 'VISITOR_ARRIVED',
        'entity_id': '501',
        'nama_tamu': 'Budi',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(43));
      expect(intent.entityId, equals('501'));
    });

    test('10. polling -> targetMenuIndex: 62', () {
      final intent = provider.parsePayload({
        'entity_type': 'polling',
        'action': 'NEW_POLLING',
        'entity_id': '64',
        'judul': 'Pemilihan Warna Gapura',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(62));
      expect(intent.entityId, equals('64'));
    });

    test('11. bansos -> targetMenuIndex: 13', () {
      final intent = provider.parsePayload({
        'entity_type': 'bansos',
        'action': 'BANSOS_STATUS_UPDATE',
        'entity_id': '8',
        'status': 'Aktif',
      });

      expect(intent, isNotNull);
      expect(intent!.targetMenuIndex, equals(13));
      expect(intent.entityId, equals('8'));
    });
  });

  group('NotificationProvider: Invalid Payload & Robustness', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    test('Null dan empty map mengembalikan null secara aman', () {
      expect(provider.parsePayload(null), isNull);
      expect(provider.parsePayload({}), isNull);
    });

    test('Missing atau empty entity_type mengembalikan null', () {
      expect(provider.parsePayload({'action': 'NEW_BILL'}), isNull);
      expect(provider.parsePayload({'entity_type': ''}), isNull);
      expect(provider.parsePayload({'entity_type': '   '}), isNull);
    });

    test('Tipe entitas tidak dikenal mengembalikan null', () {
      expect(provider.parsePayload({'entity_type': 'unknown_arbitrary_type'}), isNull);
      expect(provider.parsePayload({'entity_type': 'promo_banner'}), isNull);
    });

    test('String "null" pada entity_id dinormalisasi menjadi null', () {
      final intent = provider.parsePayload({
        'entity_type': 'emergency',
        'entity_id': 'null',
        'action': 'null',
      });

      expect(intent, isNotNull);
      expect(intent!.entityId, isNull);
      expect(intent.action, isNull);
    });
  });

  group('NotificationProvider: Pending Intent & Login Lifecycle', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    test('handleNotificationPayload saat belum login menyimpan ke pendingIntent', () {
      final intent = provider.handleNotificationPayload(
        {'entity_type': 'letter', 'action': 'NEW_LETTER_REQUEST', 'entity_id': '10'},
        isLoggedIn: false,
      );

      expect(intent, isNotNull);
      expect(provider.hasPendingIntent, isTrue);
      expect(provider.pendingIntent, equals(intent));
      expect(provider.hasActiveIntent, isFalse);
    });

    test('consumePendingIntent memindahkan pendingIntent ke activeIntent', () {
      provider.handleNotificationPayload(
        {'entity_type': 'bill', 'action': 'NEW_BILL', 'entity_id': '20'},
        isLoggedIn: false,
      );

      expect(provider.hasPendingIntent, isTrue);
      final consumed = provider.consumePendingIntent();

      expect(consumed, isNotNull);
      expect(consumed!.targetMenuIndex, equals(21));
      expect(provider.hasPendingIntent, isFalse);
      expect(provider.hasActiveIntent, isTrue);
      expect(provider.activeIntent, equals(consumed));
    });

    test('handleNotificationPayload saat sudah login langsung mengisi activeIntent', () {
      final intent = provider.handleNotificationPayload(
        {'entity_type': 'emergency', 'action': 'ALARM_TRIGGERED', 'entity_id': '30'},
        isLoggedIn: true,
      );

      expect(intent, isNotNull);
      expect(provider.hasPendingIntent, isFalse);
      expect(provider.hasActiveIntent, isTrue);
      expect(provider.activeIntent, equals(intent));
    });

    test('clearActiveIntent membersihkan activeIntent', () {
      provider.handleNotificationPayload(
        {'entity_type': 'polling', 'action': 'NEW_POLLING'},
        isLoggedIn: true,
      );

      expect(provider.hasActiveIntent, isTrue);
      provider.clearActiveIntent();
      expect(provider.hasActiveIntent, isFalse);
      expect(provider.activeIntent, isNull);
    });

    test('bersihkan() mereset seluruh state pada logout', () {
      provider.handleNotificationPayload(
        {'entity_type': 'visitor', 'action': 'VISITOR_ARRIVED'},
        isLoggedIn: false,
      );
      expect(provider.hasPendingIntent, isTrue);

      provider.bersihkan();
      expect(provider.hasPendingIntent, isFalse);
      expect(provider.hasActiveIntent, isFalse);
    });
  });

  group('NotificationProvider: Duplicate Message Prevention', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    test('Pesan dengan messageId yang sama tidak diproses ulang', () {
      final data = {'entity_type': 'agenda', 'action': 'NEW_AGENDA', 'entity_id': '5'};

      final first = provider.handleNotificationPayload(
        data,
        messageId: 'fcm_unique_msg_100',
        isLoggedIn: true,
      );
      expect(first, isNotNull);

      provider.clearActiveIntent();

      final second = provider.handleNotificationPayload(
        data,
        messageId: 'fcm_unique_msg_100',
        isLoggedIn: true,
      );
      expect(second, isNull);
      expect(provider.hasActiveIntent, isFalse);
    });

    test('Pesan dengan fallback signature yang sama tidak diproses ulang', () {
      final data = {
        'entity_type': 'bansos',
        'action': 'BANSOS_STATUS_UPDATE',
        'entity_id': '15',
        'created_at': '2026-08-18T10:30:00Z',
      };

      final first = provider.handleNotificationPayload(data, isLoggedIn: true);
      expect(first, isNotNull);

      provider.clearActiveIntent();

      final second = provider.handleNotificationPayload(data, isLoggedIn: true);
      expect(second, isNull);
    });
  });

  group('FCMService: Background Tap & Terminated Initial Message Integration', () {
    late NotificationProvider router;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      router = NotificationProvider();
      await ApiService.clearToken();
      FCMService.instance.pasangStateUji(
        isInitialized: true,
        notificationRouter: router,
        initialMessageChecked: false,
      );
    });

    test('simulasiMessageOpenedApp (Background Tap) diteruskan ke router', () {
      final message = RemoteMessage(
        messageId: 'bg_tap_msg_001',
        data: {
          'entity_type': 'complaint',
          'action': 'NEW_COMPLAINT',
          'entity_id': '99',
        },
      );

      FCMService.instance.simulasiMessageOpenedApp(message);

      // ApiService.token null -> masuk ke pendingIntent
      expect(router.hasPendingIntent, isTrue);
      expect(router.pendingIntent!.targetMenuIndex, equals(61));
      expect(router.pendingIntent!.entityId, equals('99'));
    });

    test('simulasiInitialMessage (Terminated Cold Start) diproses tepat satu kali', () {
      final message = RemoteMessage(
        messageId: 'cold_start_msg_001',
        data: {
          'entity_type': 'emergency',
          'action': 'ALARM_TRIGGERED',
          'entity_id': '111',
        },
      );

      FCMService.instance.simulasiInitialMessage(message);

      expect(router.hasPendingIntent, isTrue);
      expect(router.pendingIntent!.targetMenuIndex, equals(60));

      router.clearActiveIntent();

      // Panggilan kedua pada instance yang sama diabaikan karena initialMessageChecked = true
      FCMService.instance.simulasiInitialMessage(message);
      expect(router.hasActiveIntent, isFalse);
    });

    test('Pending initial message dikirim begitu router dipasang', () {
      final freshRouter = NotificationProvider();
      // Pasang FCMService tanpa router terlebih dahulu
      FCMService.instance.pasangStateUji(
        isInitialized: true,
        clearNotificationRouter: true,
        initialMessageChecked: false,
        pendingInitialMessage: null,
      );

      final message = RemoteMessage(
        messageId: 'early_cold_msg_002',
        data: {
          'entity_type': 'bill',
          'action': 'NEW_BILL',
          'entity_id': '333',
        },
      );

      FCMService.instance.simulasiInitialMessage(message);

      // Belum ada router, jadi message ditahan di FCMService
      expect(freshRouter.hasPendingIntent, isFalse);

      // Begitu router dipasang, pending initial message langsung diproses
      FCMService.instance.pasangNotificationRouter(freshRouter);
      expect(freshRouter.hasPendingIntent, isTrue);
      expect(freshRouter.pendingIntent!.targetMenuIndex, equals(21));
    });

    test('simulasiForegroundMessage meneruskan pesan ke handleForegroundMessage', () {
      final message = RemoteMessage(
        messageId: 'fg_msg_001',
        notification: const RemoteNotification(
          title: 'Aduan Ditanggapi',
          body: 'Ketua RT telah menanggapi aduan Anda',
        ),
        data: {
          'entity_type': 'complaint',
          'action': 'COMPLAINT_REPLIED',
          'entity_id': '45',
        },
      );

      // ApiService.token null -> masuk ke pendingIntent
      FCMService.instance.simulasiForegroundMessage(message);
      expect(router.hasPendingIntent, isTrue);
      expect(router.pendingIntent!.title, equals('Aduan Ditanggapi'));
      expect(router.pendingIntent!.body, equals('Ketua RT telah menanggapi aduan Anda'));
    });
  });

  group('NotificationProvider: Foreground Notifications & Actions', () {
    late NotificationProvider provider;

    setUp(() {
      provider = NotificationProvider();
    });

    test('Foreground message dengan notification block menggunakan title & body yang dikirim', () {
      final intent = provider.handleForegroundMessage(
        {'entity_type': 'emergency', 'action': 'ALARM_TRIGGERED', 'entity_id': '911'},
        title: 'BAHAYA KEBAKARAN!',
        body: 'Terdeteksi asap pekat di Blok C2',
        messageId: 'fg_emergency_1',
        isLoggedIn: true,
      );

      expect(intent, isNotNull);
      expect(provider.hasForegroundNotification, isTrue);
      expect(provider.foregroundNotification!.title, equals('BAHAYA KEBAKARAN!'));
      expect(provider.foregroundNotification!.body, equals('Terdeteksi asap pekat di Blok C2'));
      expect(provider.hasActiveIntent, isFalse);
    });

    test('Foreground message tanpa notification block menggunakan fallback title & body yang aman', () {
      final intent = provider.handleForegroundMessage(
        {
          'entity_type': 'bill',
          'action': 'NEW_BILL',
          'entity_id': '88',
          'periode': 'September 2026',
        },
        messageId: 'fg_bill_1',
        isLoggedIn: true,
      );

      expect(intent, isNotNull);
      expect(provider.hasForegroundNotification, isTrue);
      expect(provider.foregroundNotification!.title, equals('Tagihan Iuran Baru'));
      expect(provider.foregroundNotification!.body, contains('September 2026'));
    });

    test('Foreground message dengan payload invalid/unknown tidak memunculkan notifikasi', () {
      final intent = provider.handleForegroundMessage(
        {'entity_type': 'random_unknown_type'},
        title: 'Judul',
        body: 'Isi',
        isLoggedIn: true,
      );

      expect(intent, isNull);
      expect(provider.hasForegroundNotification, isFalse);
      expect(provider.hasActiveIntent, isFalse);
      expect(provider.hasPendingIntent, isFalse);
    });

    test('Foreground message duplikat diabaikan', () {
      final data = {'entity_type': 'letter', 'action': 'NEW_LETTER_REQUEST', 'entity_id': '10'};

      final first = provider.handleForegroundMessage(
        data,
        messageId: 'fg_duplicate_1',
        isLoggedIn: true,
      );
      expect(first, isNotNull);
      expect(provider.hasForegroundNotification, isTrue);

      provider.tutupForegroundNotification();
      expect(provider.hasForegroundNotification, isFalse);

      final second = provider.handleForegroundMessage(
        data,
        messageId: 'fg_duplicate_1',
        isLoggedIn: true,
      );
      expect(second, isNull);
      expect(provider.hasForegroundNotification, isFalse);
    });

    test('Aksi bukaForegroundNotification memindahkan intent ke activeIntent untuk navigasi', () {
      provider.handleForegroundMessage(
        {'entity_type': 'agenda', 'action': 'NEW_AGENDA', 'entity_id': '25'},
        isLoggedIn: true,
      );

      expect(provider.hasForegroundNotification, isTrue);
      expect(provider.hasActiveIntent, isFalse);

      provider.bukaForegroundNotification();

      expect(provider.hasForegroundNotification, isFalse);
      expect(provider.hasActiveIntent, isTrue);
      expect(provider.activeIntent!.targetMenuIndex, equals(50));
      expect(provider.activeIntent!.targetTabIndex, equals(1));
    });

    test('Aksi tutupForegroundNotification menghilangkan in-app notification', () {
      provider.handleForegroundMessage(
        {'entity_type': 'visitor', 'action': 'VISITOR_ARRIVED', 'entity_id': '12'},
        isLoggedIn: true,
      );

      expect(provider.hasForegroundNotification, isTrue);

      provider.tutupForegroundNotification();

      expect(provider.hasForegroundNotification, isFalse);
      expect(provider.hasActiveIntent, isFalse);
    });

    test('bersihkan() menghapus foreground notification', () {
      provider.handleForegroundMessage(
        {'entity_type': 'bansos', 'action': 'BANSOS_STATUS_UPDATE', 'entity_id': '5'},
        isLoggedIn: true,
      );

      expect(provider.hasForegroundNotification, isTrue);

      provider.bersihkan();

      expect(provider.hasForegroundNotification, isFalse);
      expect(provider.hasActiveIntent, isFalse);
      expect(provider.hasPendingIntent, isFalse);
    });
  });

  group('NotificationIntent: Fallback Generator Verification across 11 Entities', () {
    test('Fallback title dan body untuk seluruh 11 entitas bekerja tepat', () {
      // 1. announcement
      expect(NotificationIntent.generateFallbackTitle('announcement', null), equals('Pengumuman Warga'));
      expect(
        NotificationIntent.generateFallbackBody('announcement', null, {'judul': 'Gotong Royong'}),
        equals('Gotong Royong'),
      );

      // 2. emergency
      expect(NotificationIntent.generateFallbackTitle('emergency', 'ALARM_TRIGGERED'), equals('Peringatan Darurat Warga'));
      expect(NotificationIntent.generateFallbackTitle('emergency', 'ALARM_CANCELLED'), equals('Peringatan Darurat Selesai'));
      expect(
        NotificationIntent.generateFallbackBody('emergency', 'ALARM_TRIGGERED', {'lokasi': 'Blok A'}),
        contains('Blok A'),
      );

      // 3. complaint
      expect(NotificationIntent.generateFallbackTitle('complaint', 'NEW_COMPLAINT'), equals('Pengaduan Warga Baru'));
      expect(NotificationIntent.generateFallbackTitle('complaint', 'COMPLAINT_REPLIED'), equals('Tanggapan Pengaduan Warga'));
      expect(
        NotificationIntent.generateFallbackBody('complaint', 'NEW_COMPLAINT', {'judul': 'Lampu Jalan'}),
        contains('Lampu Jalan'),
      );

      // 4. letter
      expect(NotificationIntent.generateFallbackTitle('letter', 'NEW_LETTER_REQUEST'), equals('Pengajuan Surat Warga'));
      expect(NotificationIntent.generateFallbackTitle('letter', 'LETTER_STATUS_CHANGED'), equals('Status Surat Diperbarui'));
      expect(
        NotificationIntent.generateFallbackBody('letter', 'LETTER_STATUS_CHANGED', {'jenis_surat': 'Surat Pengantar SKCK'}),
        contains('SKCK'),
      );

      // 5. bill
      expect(NotificationIntent.generateFallbackTitle('bill', 'NEW_BILL'), equals('Tagihan Iuran Baru'));
      expect(
        NotificationIntent.generateFallbackBody('bill', 'NEW_BILL', {'periode': 'Agustus 2026'}),
        contains('Agustus 2026'),
      );

      // 6. payment
      expect(NotificationIntent.generateFallbackTitle('payment', 'PAYMENT_SUCCESS'), equals('Pembayaran Iuran Berhasil'));
      expect(
        NotificationIntent.generateFallbackBody('payment', 'PAYMENT_SUCCESS', {}),
        contains('berhasil diverifikasi'),
      );

      // 7. agenda
      expect(NotificationIntent.generateFallbackTitle('agenda', 'NEW_AGENDA'), equals('Agenda Kegiatan Baru'));
      expect(
        NotificationIntent.generateFallbackBody('agenda', 'NEW_AGENDA', {'judul': 'Senam Pagi'}),
        contains('Senam Pagi'),
      );

      // 8. inventory
      expect(NotificationIntent.generateFallbackTitle('inventory', 'BORROWING_STATUS_CHANGED'), equals('Peminjaman Inventaris'));
      expect(
        NotificationIntent.generateFallbackBody('inventory', 'BORROWING_STATUS_CHANGED', {}),
        contains('inventaris RT'),
      );

      // 9. visitor
      expect(NotificationIntent.generateFallbackTitle('visitor', 'VISITOR_ARRIVED'), equals('Buku Tamu / Kunjungan'));
      expect(
        NotificationIntent.generateFallbackBody('visitor', 'VISITOR_ARRIVED', {'nama_tamu': 'Ahmad'}),
        contains('Ahmad'),
      );

      // 10. polling
      expect(NotificationIntent.generateFallbackTitle('polling', 'NEW_POLLING'), equals('Polling Warga Baru'));
      expect(
        NotificationIntent.generateFallbackBody('polling', 'NEW_POLLING', {'judul': 'Pemilihan Pengurus'}),
        contains('Pemilihan Pengurus'),
      );

      // 11. bansos
      expect(NotificationIntent.generateFallbackTitle('bansos', 'BANSOS_STATUS_UPDATE'), equals('Bantuan Sosial Diperbarui'));
      expect(
        NotificationIntent.generateFallbackBody('bansos', 'BANSOS_STATUS_UPDATE', {}),
        contains('bantuan sosial'),
      );
    });
  });
}
