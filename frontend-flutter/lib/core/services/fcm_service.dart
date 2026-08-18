import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../constants/api_constants.dart';
import 'api_service.dart';
import '../../providers/notification_provider.dart';

/// Top-level background message handler wajib untuk FCM background processing.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background message handler dijalankan di isolate terpisah oleh Flutter engine.
  // Di Phase 1A/3.2, pesan diterima tanpa memicu side effect kompleks.
  debugPrint('FCM Background message diterima: ${message.messageId}');
}

/// Service terpusat untuk inisialisasi Firebase Cloud Messaging (FCM),
/// pengelolaan siklus hidup token perangkat (Token Lifecycle), dan penghubung
/// siklus penanganan notifikasi (Foreground, Background Tap, Terminated Cold Start).
class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  bool _isInitialized = false;
  String? _lastRegisteredToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;

  NotificationProvider? _notificationRouter;
  bool _initialMessageChecked = false;
  RemoteMessage? _pendingInitialMessage;

  bool get isInitialized => _isInitialized;
  String? get currentToken => _lastRegisteredToken;
  bool get initialMessageChecked => _initialMessageChecked;

  /// Menghubungkan [NotificationProvider] ke FCMService untuk merutekan intent notifikasi.
  void pasangNotificationRouter(NotificationProvider router) {
    _notificationRouter = router;
    if (_pendingInitialMessage != null) {
      final msg = _pendingInitialMessage!;
      _pendingInitialMessage = null;
      _arahkanPesan(msg);
    }
  }

  /// Inisialisasi Firebase Core, Firebase Messaging, dan listener seluruh siklus notifikasi.
  ///
  /// Dirancang toleran terhadap kegagalan: bila dijalankan pada platform yang
  /// belum dikonfigurasi (misal Web tanpa Service Worker) atau pada lingkungan
  /// pengujian/desktop, inisialisasi akan dilewati dengan aman tanpa mematikan aplikasi.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kIsWeb) {
        // Pada Flutter Web, FCM membutuhkan konfigurasi VAPID dan Service Worker terpisah.
        // Dilewati dengan aman agar Web tetap berfungsi normal.
        debugPrint('FCMService: Platform Web terdeteksi, inisialisasi native dilewati.');
        _isInitialized = true;
        return;
      }

      // Inisialisasi Firebase Core
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;

      // Minta izin notifikasi untuk Android 13+ (POST_NOTIFICATIONS) dan iOS
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('FCMService: Izin notifikasi status: ${settings.authorizationStatus}');

      // Pasang background message handler (isolate terpisah)
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Pasang listener token refresh otomatis
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCMService: Token diperbarui oleh FCM.');
        unawaited(sinkronkanTokenKeBackend(tokenBaru: newToken));
      });

      // Pasang listener pesan foreground
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCMService: Pesan foreground diterima: ${message.notification?.title ?? message.data['entity_type']}');
      });

      // Pasang listener background tap (aplikasi dalam keadaan background/minimized)
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCMService: Notifikasi dibuka dari background: ${message.messageId}');
        _arahkanPesan(message);
      });

      // Periksa initial message saat startup (aplikasi dibuka dari keadaan mati / terminated)
      // Diproses tepat satu kali per siklus proses.
      if (!_initialMessageChecked) {
        _initialMessageChecked = true;
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          debugPrint('FCMService: Initial message (terminated) terdeteksi: ${initialMessage.messageId}');
          if (_notificationRouter != null) {
            _arahkanPesan(initialMessage);
          } else {
            _pendingInitialMessage = initialMessage;
          }
        }
      }

      _isInitialized = true;
      debugPrint('FCMService: Berhasil diinisialisasi.');
    } catch (e) {
      debugPrint('FCMService: Inisialisasi dilewati/gagal (aman): $e');
      // Tetap tandai true agar tidak mencoba berulang-ulang saat startup
      _isInitialized = true;
    }
  }

  /// Meneruskan payload [RemoteMessage] ke [NotificationProvider] terdaftar.
  void _arahkanPesan(RemoteMessage message) {
    final router = _notificationRouter;
    if (router == null) {
      _pendingInitialMessage = message;
      return;
    }

    final jwtToken = ApiService.token;
    final bool isLoggedIn = jwtToken != null && jwtToken.isNotEmpty;

    router.handleNotificationPayload(
      message.data,
      messageId: message.messageId,
      isLoggedIn: isLoggedIn,
    );
  }

  /// Mengambil token FCM perangkat dan mendaftarkannya ke endpoint backend
  /// `POST /api/notifications/fcm-token`.
  ///
  /// Pengguna wajib sudah login (memiliki JWT token sah di ApiService).
  /// `user_id` TIDAK dikirim dari klien; backend membacanya dari `req.user.id` (UUID).
  Future<bool> sinkronkanTokenKeBackend({String? tokenBaru}) async {
    if (kIsWeb) return false;
    final jwtToken = ApiService.token;
    if (jwtToken == null || jwtToken.isEmpty) {
      debugPrint('FCMService: Pengguna belum login, sinkronisasi token ditunda.');
      return false;
    }

    try {
      String? token = tokenBaru;
      if (token == null || token.isEmpty) {
        token = await FirebaseMessaging.instance.getToken();
      }

      if (token == null || token.isEmpty) {
        debugPrint('FCMService: Gagal mendapatkan token dari FCM.');
        return false;
      }

      // Hindari request berulang jika token sama persis dengan yang sudah terdaftar
      if (token == _lastRegisteredToken) {
        return true;
      }

      final deviceType = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      final response = await ApiService.post(
        ApiConstants.fcmToken,
        body: {
          'fcm_token': token,
          'device_type': deviceType,
          'device_name': 'Flutter App (${defaultTargetPlatform.name})',
        },
      );

      if (response['success'] == true) {
        _lastRegisteredToken = token;
        debugPrint('FCMService: Token perangkat berhasil disinkronkan ke backend.');
        return true;
      } else {
        debugPrint('FCMService: Backend menolak token: ${response['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('FCMService: Kesalahan saat sinkronisasi token: $e');
      return false;
    }
  }

  /// Mencabut token FCM perangkat dari backend saat pengguna keluar (logout).
  ///
  /// Memanggil `DELETE /api/notifications/fcm-token` dengan token perangkat ini
  /// agar push notification pengguna ini tidak lagi terkirim ke perangkat ini.
  Future<bool> cabutTokenDariBackend() async {
    final token = _lastRegisteredToken;
    final jwtToken = ApiService.token;

    if (token == null || token.isEmpty || jwtToken == null || jwtToken.isEmpty) {
      _lastRegisteredToken = null;
      return true;
    }

    try {
      final response = await ApiService.delete(
        ApiConstants.fcmToken,
        body: {'fcm_token': token},
      );

      _lastRegisteredToken = null;
      return response['success'] == true;
    } catch (e) {
      debugPrint('FCMService: Kesalahan saat mencabut token: $e');
      _lastRegisteredToken = null;
      return false;
    }
  }

  /// Mereset token terdaftar secara lokal tanpa panggilan jaringan.
  void resetTokenLokal() {
    _lastRegisteredToken = null;
  }

  /// Jalur pengujian unit / mock state.
  @visibleForTesting
  void pasangStateUji({
    bool? isInitialized,
    String? lastRegisteredToken,
    NotificationProvider? notificationRouter,
    bool clearNotificationRouter = false,
    bool? initialMessageChecked,
    RemoteMessage? pendingInitialMessage,
  }) {
    if (isInitialized != null) _isInitialized = isInitialized;
    _lastRegisteredToken = lastRegisteredToken;
    if (clearNotificationRouter) {
      _notificationRouter = null;
    } else if (notificationRouter != null) {
      _notificationRouter = notificationRouter;
    }
    if (initialMessageChecked != null) _initialMessageChecked = initialMessageChecked;
    _pendingInitialMessage = pendingInitialMessage;
  }

  /// Simulasi background tap notification untuk pengujian unit.
  @visibleForTesting
  void simulasiMessageOpenedApp(RemoteMessage message) {
    _arahkanPesan(message);
  }

  /// Simulasi cold start / initial message untuk pengujian unit.
  @visibleForTesting
  void simulasiInitialMessage(RemoteMessage message) {
    if (_initialMessageChecked) return;
    _initialMessageChecked = true;
    if (_notificationRouter != null) {
      _arahkanPesan(message);
    } else {
      _pendingInitialMessage = message;
    }
  }

  /// Membersihkan listener saat service dibongkar (bila diperlukan).
  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _onMessageSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedAppSub?.cancel();
    _onMessageOpenedAppSub = null;
  }
}
