import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_community/core/constants/api_constants.dart';
import 'package:smart_community/core/services/api_service.dart';
import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/core/services/fcm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String sampleUuid = '693ad551-0361-4259-a931-c5af81599fe9';
  const String sampleFcmToken = 'fcm_mock_token_abc_123456789';

  group('ApiConstants & Endpoint Notifikasi', () {
    test('ApiConstants.fcmToken mengarah ke rute notifikasi yang benar', () {
      expect(ApiConstants.fcmToken, endsWith('/notifications/fcm-token'));
    });
  });

  group('FCMService Lifecycle & Token Management', () {
    setUp(() {
      FCMService.instance.pasangStateUji(
        isInitialized: true,
        lastRegisteredToken: null,
      );
    });

    test('FCMService singleton mempertahankan state inisialisasi', () {
      final fcm = FCMService.instance;
      expect(fcm.isInitialized, isTrue);
      expect(fcm.currentToken, isNull);
    });

    test('sinkronkanTokenKeBackend menolak jika belum ada JWT token login', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.clearToken();

      final hasil = await FCMService.instance.sinkronkanTokenKeBackend(
        tokenBaru: sampleFcmToken,
      );

      expect(hasil, isFalse);
      expect(FCMService.instance.currentToken, isNull);
    });

    test('cabutTokenDariBackend membersihkan currentToken lokal', () async {
      FCMService.instance.pasangStateUji(
        isInitialized: true,
        lastRegisteredToken: sampleFcmToken,
      );
      expect(FCMService.instance.currentToken, equals(sampleFcmToken));

      await FCMService.instance.cabutTokenDariBackend();

      expect(FCMService.instance.currentToken, isNull);
    });

    test('initialize aman dipanggil berulang kali', () async {
      final fcm = FCMService.instance;
      await fcm.initialize();
      await fcm.initialize();
      expect(fcm.isInitialized, isTrue);
    });
  });

  group('Integrasi AuthService & FCMService', () {
    test('logout memicu pelepasan token FCM secara aman', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'sample-jwt-token-123',
        'user_data': jsonEncode({
          'id': sampleUuid,
          'nama': 'Warga Test',
          'role': 'warga',
        }),
      });

      final auth = AuthService();
      await auth.tryAutoLogin();
      expect(auth.isLoggedIn, isTrue);

      FCMService.instance.pasangStateUji(
        isInitialized: true,
        lastRegisteredToken: sampleFcmToken,
      );
      expect(FCMService.instance.currentToken, equals(sampleFcmToken));

      await auth.logout(panggilServer: false);

      expect(auth.isLoggedIn, isFalse);
      expect(FCMService.instance.currentToken, isNull);
    });
  });
}
