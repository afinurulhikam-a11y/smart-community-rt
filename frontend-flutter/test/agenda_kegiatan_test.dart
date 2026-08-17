import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/screens/admin/agenda_kegiatan_screen.dart';

import 'bantuan_uji.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-uji',
      'user_data': jsonEncode({
        'id': 'user-123',
        'nama': 'Admin RT 01',
        'role': 'admin',
        'username': 'admin01',
      }),
    });
  });

  testWidgets('AgendaKegiatanScreen terpasang dan berinteraksi normal', (tester) async {
    pasangKondisi(tester, kondisiUji[4]); // desktop 1440x900

    await tester.pumpWidget(bungkusLayar(const AgendaKegiatanScreen()));
    await tester.pumpAndSettle();

    // Verifikasi judul / breadcrumb muncul
    expect(find.text('Kegiatan & Info / Agenda Kegiatan'), findsOneWidget);
    expect(find.text('Semua Agenda'), findsOneWidget);
    expect(find.text('Akan Datang'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
  });
}
