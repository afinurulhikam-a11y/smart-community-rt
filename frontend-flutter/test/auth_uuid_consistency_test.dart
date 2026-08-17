import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_community/core/services/api_service.dart';
import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/models/borrowing_model.dart';
import 'package:smart_community/models/emergency_model.dart';
import 'package:smart_community/models/user_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String sampleUuid = '693ad551-0361-4259-a931-c5af81599fe9';
  const String otherUuid = 'f6e759b3-91b0-496a-b4e9-ea32eac0392e';

  group('Konsistensi AuthService.userId UUID', () {
    test('restore session mempertahankan UUID string pada auth.userId', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'sample-jwt-token',
        'user_data': jsonEncode({
          'id': sampleUuid,
          'nama': 'Agus Wijaya',
          'role': 'warga',
          'username': '3201990000000001',
          'must_change_password': false,
        }),
      });

      final auth = AuthService();
      final restored = await auth.tryAutoLogin();

      expect(restored, isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.userId, equals(sampleUuid));
      expect(auth.userId, isA<String>());
      expect(auth.userName, equals('Agus Wijaya'));
      expect(auth.userRole, equals('warga'));
    });

    test('logout membersihkan auth.userId menjadi string kosong', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'sample-jwt-token',
        'user_data': jsonEncode({
          'id': sampleUuid,
          'nama': 'Agus Wijaya',
          'role': 'warga',
        }),
      });

      final auth = AuthService();
      await auth.tryAutoLogin();
      expect(auth.userId, equals(sampleUuid));

      await auth.logout(panggilServer: false);

      expect(auth.isLoggedIn, isFalse);
      expect(auth.userId, equals(''));
      expect(auth.userRole, equals(''));
      expect(ApiService.token, isNull);
    });

    test('tanpa sesi yang tersimpan, auth.userId mengembalikan string kosong aman', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.userId, equals(''));
      expect(auth.userId, isA<String>());
    });
  });

  group('Konsistensi UserModel UUID', () {
    test('UserModel.fromJson mempertahankan id sebagai String UUID', () {
      final json = {
        'id': sampleUuid,
        'nama': 'Agus Wijaya',
        'email': 'agus@example.com',
        'username': '3201990000000001',
        'role': 'warga',
        'is_active': true,
        'nik': '3201990000000001',
      };

      final user = UserModel.fromJson(json);

      expect(user.id, equals(sampleUuid));
      expect(user.id, isA<String>());
      expect(user.nama, equals('Agus Wijaya'));

      final encoded = user.toJson();
      expect(encoded['id'], equals(sampleUuid));
    });

    test('UserModel.fromJson menangani id null secara aman', () {
      final json = {
        'nama': 'Calon Warga',
        'email': 'calon@example.com',
        'role': 'warga',
      };

      final user = UserModel.fromJson(json);

      expect(user.id, isNull);
      expect(user.nama, equals('Calon Warga'));
    });
  });

  group('Pengecekan Kepemilikan (Ownership Checks) dengan UUID', () {
    test('ownership peminjaman warga mencocokkan UUID secara langsung', () {
      final pinjamanSaya = BorrowingModel(
        id: 1,
        inventoryId: 10,
        namaBarang: 'Tenda RT',
        userId: sampleUuid,
        namaPeminjam: 'Agus Wijaya',
        jumlah: 1,
        status: 'Dipinjam',
        statusEfektif: 'Dipinjam',
      );

      final pinjamanOrangLain = BorrowingModel(
        id: 2,
        inventoryId: 10,
        namaBarang: 'Tenda RT',
        userId: otherUuid,
        namaPeminjam: 'Hendra Gunawan',
        jumlah: 1,
        status: 'Dipinjam',
        statusEfektif: 'Dipinjam',
      );

      // Simulasi evaluasi kepemilikan di peminjaman_screen.dart
      const currentUserId = sampleUuid;

      final bolehHapusMilikSaya = (currentUserId == pinjamanSaya.userId && !pinjamanSaya.isDikembalikan);
      final bolehHapusMilikOrangLain = (currentUserId == pinjamanOrangLain.userId && !pinjamanOrangLain.isDikembalikan);

      expect(bolehHapusMilikSaya, isTrue);
      expect(bolehHapusMilikOrangLain, isFalse);
    });

    test('ownership status darurat mencocokkan UUID secara langsung', () {
      final alertSaya = EmergencyModel(
        id: 'alert-uuid-1',
        userId: sampleUuid,
        message: 'Bantuan medis',
        status: 'active',
        createdAt: DateTime.now(),
      );

      final alertOrangLain = EmergencyModel(
        id: 'alert-uuid-2',
        userId: otherUuid,
        message: 'Kebakaran',
        status: 'active',
        createdAt: DateTime.now(),
      );

      // Simulasi evaluasi _bolehMenyelesaikan di status_darurat_screen.dart
      bool bolehMenyelesaikan(EmergencyModel alert, {required bool isPengurus, required String currentUserId}) {
        if (isPengurus) return true;
        final idSaya = currentUserId;
        return idSaya.isNotEmpty && idSaya == alert.userId;
      }

      expect(bolehMenyelesaikan(alertSaya, isPengurus: false, currentUserId: sampleUuid), isTrue);
      expect(bolehMenyelesaikan(alertOrangLain, isPengurus: false, currentUserId: sampleUuid), isFalse);
      expect(bolehMenyelesaikan(alertOrangLain, isPengurus: true, currentUserId: sampleUuid), isTrue);
    });
  });
}
