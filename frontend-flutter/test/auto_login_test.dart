import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_community/core/services/auth_service.dart';

/// Menjaga agar sesi pengguna tidak terhapus hanya karena backend sedang tidak
/// terjangkau saat aplikasi dibuka.
///
/// `tryAutoLogin` dulu memanggil `/auth/me` lalu memperlakukan SETIAP jawaban
/// yang bukan `success` sebagai token ditolak, dan langsung `logout()`. Padahal
/// `ApiService` tidak pernah melempar galat: kegagalan jaringan pun kembali
/// sebagai `success: false`. Cukup backend belum hidup, ngrok belum tersambung,
/// atau ponsel belum dapat Wi-Fi pada detik aplikasi dibuka — token terhapus,
/// dan tiap kali dibuka pengguna disodori layar masuk lagi.
///
/// Pengujian ini berjalan TANPA backend, jadi keadaan "server tidak terjangkau"
/// terjadi dengan sendirinya — persis keadaan yang dulu membuat sesi hilang.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sesiTersimpan = {
    'id': 'uji-1',
    'nama': 'Warga Demo',
    'email': 'warga@example.com',
    'role': 'warga',
  };

  test('sesi tersimpan tetap dipakai ketika server tidak terjangkau', () async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-lama-yang-masih-sah',
      'user_data': jsonEncode(sesiTersimpan),
    });

    final auth = AuthService();
    final hasil = await auth.tryAutoLogin();

    expect(hasil, isTrue, reason: 'pengguna seharusnya tetap masuk');
    expect(auth.isLoggedIn, isTrue);
    expect(auth.userRole, 'warga');

    // Yang paling menentukan: tokennya TIDAK boleh ikut terhapus, karena itu
    // yang membuat pembukaan aplikasi berikutnya juga berakhir di layar masuk.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), isNotNull);
    expect(prefs.getString('user_data'), isNotNull);
  });

  test('pemulihan sesi tidak menunggu jaringan', () async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-lama-yang-masih-sah',
      'user_data': jsonEncode(sesiTersimpan),
    });

    final jam = Stopwatch()..start();
    await AuthService().tryAutoLogin();
    jam.stop();

    // ApiService mencoba tiga kali dengan batas 10 detik ditambah jeda mundur —
    // sekitar 31 detik bila server tak terjangkau. Dulu layar splash menahan
    // selama itu, ditambah `izin.muat()` sesudahnya, hingga hampir satu menit
    // aplikasi diam tanpa tanda apa pun. Pemeriksaan token kini berjalan di
    // latar, jadi pemulihan sesi harus selesai nyaris seketika.
    expect(
      jam.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason: 'pemulihan sesi menunggu jaringan lagi (${jam.elapsed.inSeconds}s)',
    );
  });

  test('tanpa sesi tersimpan, tetap diarahkan ke layar masuk', () async {
    SharedPreferences.setMockInitialValues({});

    final auth = AuthService();
    final hasil = await auth.tryAutoLogin();

    expect(hasil, isFalse);
    expect(auth.isLoggedIn, isFalse);
  });
}
