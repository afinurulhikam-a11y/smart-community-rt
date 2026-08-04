import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/core/constants/api_constants.dart';

/// Menjaga penyusunan alamat backend.
///
/// `String.fromEnvironment` dibaca saat kompilasi, jadi nilainya di sini
/// mengikuti apa yang dikirim `--dart-define` saat menjalankan tes. Tanpa
/// define apa pun, yang berlaku adalah jalur bawaan — itulah yang diperiksa
/// berkas ini, bersama aturan turunan yang berlaku di SEMUA jalur.
///
/// Untuk memastikan jalur override, jalankan:
///
///   flutter test --dart-define=API_BASE_URL=https://abc.ngrok-free.app
///   flutter test --dart-define=API_HOST=10.0.0.5
void main() {
  group('bentuk alamat', () {
    test('baseUrl selalu berakhiran /api tepat satu kali', () {
      expect(ApiConstants.baseUrl.endsWith('/api'), isTrue);
      expect('/api'.allMatches(ApiConstants.baseUrl).length, 1);
    });

    test('baseUrl tidak pernah memuat garis miring ganda setelah skema', () {
      final tanpaSkema = ApiConstants.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
      expect(tanpaSkema.contains('//'), isFalse,
          reason: 'alamat: ${ApiConstants.baseUrl}');
    });

    test('alamatAktif tidak berakhiran garis miring maupun /api', () {
      expect(ApiConstants.alamatAktif.endsWith('/'), isFalse);
      expect(ApiConstants.alamatAktif.endsWith('/api'), isFalse);
    });
  });

  group('WebSocket mengikuti skema HTTP', () {
    test('https berpasangan dengan wss, http dengan ws', () {
      // Menyambung ke ws:// dari alamat https ditolak browser, dan panic
      // button akan diam-diam mati. Pasangannya harus selalu cocok.
      if (ApiConstants.alamatAktif.startsWith('https://')) {
        expect(ApiConstants.wsUrl.startsWith('wss://'), isTrue);
      } else {
        expect(ApiConstants.wsUrl.startsWith('ws://'), isTrue);
      }
    });

    test('wsUrl menunjuk host yang sama dengan baseUrl', () {
      final hostHttp = Uri.parse(ApiConstants.baseUrl).host;
      final hostWs = Uri.parse(ApiConstants.wsUrl).host;
      expect(hostWs, hostHttp);
    });

    test('wsUrl tidak memakai akhiran /api', () {
      expect(ApiConstants.wsUrl.contains('/api'), isFalse);
    });
  });

  group('endpoint tersusun dari baseUrl', () {
    test('endpoint mewarisi host yang sama', () {
      final host = Uri.parse(ApiConstants.baseUrl).host;
      for (final e in [
        ApiConstants.login,
        ApiConstants.bills,
        ApiConstants.payMulai,
        ApiConstants.payStatus('RT-1'),
        ApiConstants.warga,
      ]) {
        expect(Uri.parse(e).host, host, reason: e);
      }
    });

    test('endpoint tidak pernah memuat placeholder yang belum terisi', () {
      expect(ApiConstants.payStatus('RT-123').contains('RT-123'), isTrue);
      expect(ApiConstants.bills.contains(r'$'), isFalse);
    });
  });
}
