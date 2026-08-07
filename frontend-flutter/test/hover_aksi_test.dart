import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/screens/admin/data_warga_screen.dart';

const _ikon = [Icons.edit_outlined, Icons.delete_outline, Icons.manage_accounts_outlined];
const _warna = [Color(0xFF0F766E), Color(0xFFEF4444), Color(0xFF10B981)];

/// Kolom AKSI seperti yang dibangun Data Warga, memakai [gayaAksiTabel] dan
/// [geserAksiTabel] yang ASLI — menyalin nilainya ke sini akan membuat uji ini
/// lolos selamanya, termasuk ketika yang sebenarnya salah.
///
/// Theme pembungkusnya meniru `_rapatkanAksi` di TabelResponsif, yang memang
/// membungkus sel aksi pada tabel sungguhan.
Future<void> pasangKolomAksi(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (c) {
              final tema = Theme.of(c);
              return Theme(
                data: tema.copyWith(
                  iconButtonTheme: IconButtonThemeData(
                    style: (tema.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
                      alignment: Alignment.centerLeft,
                      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    ),
                  ),
                ),
                child: Transform.translate(
                  offset: const Offset(geserAksiTabel, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        IconButton(
                          icon: Icon(_ikon[i], color: _warna[i], size: 20),
                          style: gayaAksiTabel(_warna[i]),
                          onPressed: () {},
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Rect sasaranSentuh(WidgetTester t, int i) => t.getRect(find.byType(IconButton).at(i));
Rect glif(WidgetTester t, int i) => t.getRect(find.byIcon(_ikon[i]));
Rect permukaanHover(WidgetTester t, int i) => t.getRect(
  find.descendant(of: find.byType(IconButton).at(i), matching: find.byType(InkWell)).first,
);

void main() {
  testWidgets('latar hover tepat di tengah ikon, ketiganya', (tester) async {
    await pasangKolomAksi(tester);
    for (var i = 0; i < 3; i++) {
      final h = permukaanHover(tester, i);
      final g = glif(tester, i);
      expect(
        h.center,
        g.center,
        reason:
            'Tombol $i: pusat latar hover ${h.center}, pusat ikon ${g.center}. '
            'Latar yang meleset terbaca seperti ikon yang meloncat saat kursor '
            'masuk — dan itu memang penyebabnya dulu, meleset 9px ke kanan '
            'karena alignment centerLeft di dalam kotak yang lebih lebar.',
      );
    }
  });

  testWidgets('ukuran hover dan area sentuh sama untuk ketiganya', (tester) async {
    await pasangKolomAksi(tester);
    final hover = [for (var i = 0; i < 3; i++) permukaanHover(tester, i).size];
    final sentuh = [for (var i = 0; i < 3; i++) sasaranSentuh(tester, i).size];

    expect(hover.toSet(), hasLength(1), reason: 'ukuran hover berbeda-beda: $hover');
    expect(sentuh.toSet(), hasLength(1), reason: 'area sentuh berbeda-beda: $sentuh');
    expect(hover.first, const Size(ukuranHoverAksi, ukuranHoverAksi));

    // Area sentuh TIDAK boleh ikut mengecil bersama latar hover-nya. Tombol ini
    // juga muncul di tampilan kartu pada ponsel, tempat 48dp itu berarti.
    expect(
      sentuh.first,
      const Size(kMinInteractiveDimension, kMinInteractiveDimension),
      reason: 'sasaran sentuh menyusut di bawah 48dp',
    );
  });

  testWidgets('hover tidak menggeser apa pun', (tester) async {
    // Inti permintaannya. Diukur SEBELUM dan SESUDAH kursor benar-benar masuk,
    // bukan disimpulkan dari fakta bahwa ButtonStyle "seharusnya" hanya
    // mengubah warna.
    await pasangKolomAksi(tester);

    final sebelumSentuh = [for (var i = 0; i < 3; i++) sasaranSentuh(tester, i)];
    final sebelumGlif = [for (var i = 0; i < 3; i++) glif(tester, i)];
    final sebelumHover = [for (var i = 0; i < 3; i++) permukaanHover(tester, i)];

    final kursor = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await kursor.addPointer(location: Offset.zero);
    addTearDown(kursor.removePointer);

    for (var i = 0; i < 3; i++) {
      await kursor.moveTo(tester.getCenter(find.byIcon(_ikon[i])));
      await tester.pumpAndSettle();

      for (var j = 0; j < 3; j++) {
        expect(sasaranSentuh(tester, j), sebelumSentuh[j],
            reason: 'area sentuh tombol $j bergeser saat tombol $i di-hover');
        expect(glif(tester, j), sebelumGlif[j],
            reason: 'ikon tombol $j bergeser saat tombol $i di-hover');
        expect(permukaanHover(tester, j), sebelumHover[j],
            reason: 'kotak hover tombol $j bergeser saat tombol $i di-hover');
      }
    }
  });

  testWidgets('ikon tetap rata kiri dan berjarak sama', (tester) async {
    await pasangKolomAksi(tester);
    final g = [for (var i = 0; i < 3; i++) glif(tester, i)];

    // Tepi kiri ikon pertama = (48 − 30) / 2 + (30 − 20) / 2 + geser = 5.
    // Angka ini adalah posisi ikon SEBELUM perbaikan; memusatkan hover tidak
    // boleh memindahkannya.
    expect(g[0].left, 5.0);
    expect(g[0].width, 20.0);

    // Jarak antar pusat ikon tetap satu sasaran sentuh penuh.
    expect(g[1].center.dx - g[0].center.dx, kMinInteractiveDimension);
    expect(g[2].center.dx - g[1].center.dx, kMinInteractiveDimension);

    // Dan ketiganya duduk pada garis dasar yang sama.
    expect({for (final r in g) r.top}, hasLength(1));
  });
}
