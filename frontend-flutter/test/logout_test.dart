import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_community/core/services/api_service.dart';
import 'package:smart_community/core/services/auth_service.dart';

/// Menjaga agar menekan "Keluar" selalu benar-benar mengeluarkan pengguna dari
/// perangkat ini — bahkan ketika server tidak terjangkau.
///
/// Sejak Fase B, `logout()` memanggil `POST /auth/logout` supaya server
/// menaikkan `users.token_versi` dan sesi di SEMUA perangkat ikut mati. Panggil
/// server itulah yang menciptakan risiko baru: bila hasilnya ikut menentukan
/// apakah penyimpanan lokal dibersihkan, maka seseorang yang menekan Keluar di
/// luar jangkauan sinyal akan tetap berada di dalam aplikasi — persis kebalikan
/// dari yang ia minta, pada momen ia paling ingin keluar.
///
/// Pengujian ini berjalan TANPA backend, jadi keadaan "server tidak terjangkau"
/// terjadi dengan sendirinya. Itu bukan keterbatasan uji ini melainkan isinya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sesiTersimpan = {
    'id': 'uji-1',
    'nama': 'Warga Demo',
    'role': 'warga',
    'username': '3201990000000001',
  };

  Future<AuthService> sesiHidup() async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-yang-masih-sah',
      'user_data': jsonEncode(sesiTersimpan),
    });
    final auth = AuthService();
    await auth.tryAutoLogin();
    expect(auth.isLoggedIn, isTrue, reason: 'prasyarat: harus masuk dulu');
    return auth;
  }

  test('logout membersihkan perangkat ini walau server tidak terjangkau', () async {
    final auth = await sesiHidup();

    await auth.logout();

    expect(auth.isLoggedIn, isFalse);
    // `userRole` mengembalikan string kosong, bukan null, ketika tidak ada
    // sesi — perilaku yang sudah ada dan dipakai layar-layar lain.
    expect(auth.userRole, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), isNull,
        reason: 'token harus hilang; kalau tidak, aplikasi terbuka lagi dalam keadaan masuk');
    expect(prefs.getString('user_data'), isNull);
    expect(ApiService.token, isNull,
        reason: 'token di memori juga harus dilepas, bukan hanya yang di penyimpanan');
  });

  test('logout tidak menahan pengguna menunggu jaringan', () async {
    final auth = await sesiHidup();

    final jam = Stopwatch()..start();
    await auth.logout();
    jam.stop();

    // `ApiService` mencoba tiga kali dengan batas 10 detik ditambah jeda mundur —
    // sekitar 31 detik bila server tak terjangkau. Menunggu selama itu setelah
    // menekan Keluar membuat aplikasi tampak menggantung, dan pengguna tidak
    // punya cara tahu bahwa ia sebenarnya sudah keluar.
    //
    // Batasnya: di lingkungan uji, HttpClient menjawab 400 seketika alih-alih
    // kehabisan waktu, jadi jalur retry tidak benar-benar dijalani di sini. Yang
    // dijaga uji ini adalah hal yang lebih mendasar — bahwa `logout()` tidak
    // pernah menunggu sesuatu yang tak kunjung selesai.
    expect(
      jam.elapsed,
      lessThan(const Duration(seconds: 35)),
      reason: 'logout menggantung lebih lama daripada batas retry ApiService',
    );
  });

  test('logout dua kali beruntun tidak meledak', () async {
    final auth = await sesiHidup();

    await auth.logout();
    await auth.logout();

    expect(auth.isLoggedIn, isFalse);
  });

  test('logout tanpa panggilan server tetap membersihkan penyimpanan', () async {
    // Jalur yang dipakai `_periksaSesiDiLatar` ketika server sudah menjawab
    // 401/403: sesinya memang sudah mati, jadi memanggil /auth/logout hanya
    // akan ditolak lagi. Yang tetap wajib terjadi adalah pembersihan lokal.
    final auth = await sesiHidup();

    await auth.logout(panggilServer: false);

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(prefs.getString('auth_token'), isNull);
    expect(prefs.getString('user_data'), isNull);
  });
}
