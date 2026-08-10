import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/screens/admin/bantuan_sosial_screen.dart';
import 'bantuan_uji.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BantuanSosialScreen Form Dialog Date Picker opens without error', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));

    final widgetLayar = bungkusLayar(const BantuanSosialScreen());

    await tester.pumpWidget(widgetLayar);

    final permProvider = tester.element(find.byType(BantuanSosialScreen)).read<PermissionProvider>();
    permProvider.setRole('admin');

    await tester.pumpAndSettle();

    // Cari tombol Tambah Penerima
    final tombolTambah = find.widgetWithText(ElevatedButton, 'Tambah Penerima');
    expect(tombolTambah, findsOneWidget);

    await tester.tap(tombolTambah);
    await tester.pumpAndSettle();

    // Dialog Tambah Penerima harus muncul
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Tanggal Bantuan *'), findsOneWidget);

    // Buka Date Picker
    final fieldTanggal = find.text('Tanggal Bantuan *');
    expect(fieldTanggal, findsOneWidget);
    await tester.tap(fieldTanggal);
    await tester.pumpAndSettle();

    // DatePickerDialog harus muncul tanpa throw exception
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Pilih tombol OK
    final tombolOK = find.text('OK');
    if (tombolOK.evaluate().isNotEmpty) {
      await tester.tap(tombolOK);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('BantuanSosialScreen parseDateString formats dates properly without timezone shift', (tester) async {
    final dt1 = parseDateString('2026-08-15');
    expect(dt1, isNotNull);
    expect(dt1!.year, 2026);
    expect(dt1.month, 8);
    expect(dt1.day, 15);

    final dt2 = parseDateString('2026-08-15T00:00:00.000Z');
    expect(dt2, isNotNull);
    expect(dt2!.year, 2026);
    expect(dt2.month, 8);
    expect(dt2.day, 15);
  });
}
