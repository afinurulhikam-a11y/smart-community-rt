import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_community/main.dart';

/// Smoke test: aplikasi bisa dibangun dan menampilkan layar pertamanya.
///
/// Menggantikan tes template bawaan Flutter yang menguji aplikasi penghitung —
/// aplikasi yang tidak pernah ada di proyek ini, sehingga tesnya selalu gagal.
///
/// Tanpa token tersimpan, `AuthGate` memanggil `tryAutoLogin()` lalu berpindah
/// ke layar login. Backend tidak dihubungi karena tidak ada token, jadi tes ini
/// tidak butuh server yang hidup.
///
/// Sengaja TIDAK memeriksa teks tertentu: layar pembuka hanya tampil selagi
/// `tryAutoLogin()` berjalan, dan itu selesai secepat apa pun tergantung mesin.
/// Yang dijaga di sini adalah bahwa seluruh pohon widget — MultiProvider,
/// AuthGate, sampai layar pertamanya — terbangun tanpa melempar apa pun.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('aplikasi terbangun tanpa error sampai layar pertamanya',
      (tester) async {
    await tester.pumpWidget(const SmartCommunityApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
