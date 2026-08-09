import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/screens/admin/data_warga_screen.dart';

/// Keempat kotak isian dialog Akun & Kredensial, dibangun dengan
/// [dekorKredensial] yang ASLI — bukan salinan nilainya di berkas uji ini.
///
/// Menyalin dekorasinya ke sini akan membuat uji ini lolos selamanya, termasuk
/// ketika dekorasi yang sebenarnya diubah menjadi salah.
List<Widget> kotakKredensial(BuildContext c) => [
  // Username Login — hanya-baca
  InputDecorator(
    key: const Key('username'),
    decoration: dekorKredensial(c),
    child: Text(
      '3201991000000012',
      style: gayaIsiKredensial(c).copyWith(fontWeight: FontWeight.w600),
    ),
  ),
  // Nomor HP / WhatsApp
  TextField(
    key: const Key('no_hp'),
    style: gayaIsiKredensial(c),
    decoration: dekorKredensial(c, hint: 'Misal: 081234567890'),
  ),
  // Role / Peran Sistem
  InputDecorator(
    key: const Key('role'),
    decoration: dekorKredensial(c),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: 'warga',
        isExpanded: true,
        isDense: true,
        style: gayaIsiKredensial(c),
        onChanged: (_) {},
        items: const [
          DropdownMenuItem(value: 'warga', child: Text('Warga')),
          DropdownMenuItem(value: 'admin', child: Text('Administrator')),
        ],
      ),
    ),
  ),
  // Ubah / Reset Password
  TextField(
    key: const Key('sandi'),
    style: gayaIsiKredensial(c),
    decoration: dekorKredensial(
      c,
      hint: 'Kosongkan jika tidak ingin mengubah',
      suffixIcon: IconButton(
        icon: const Icon(Icons.visibility_outlined, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 48,
          maxWidth: 48,
          minHeight: AppTheme.sasaranSentuh,
          maxHeight: AppTheme.sasaranSentuh,
        ),
        onPressed: () {},
      ),
    ),
  ),
];

const kunci = ['username', 'no_hp', 'role', 'sandi'];

Future<void> pasang(WidgetTester tester, {required bool gelap}) async {
  await tester.binding.setSurfaceSize(const Size(600, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: gelap ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: Builder(
              builder: (c) => Column(
                mainAxisSize: MainAxisSize.min,
                children: kotakKredensial(c),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final gelap in [false, true]) {
    final mode = gelap ? 'gelap' : 'terang';

    testWidgets('keempat kotak sama tinggi dan sama lebar — mode $mode', (tester) async {
      await pasang(tester, gelap: gelap);

      final ukuran = {
        for (final k in kunci) k: tester.getSize(find.byKey(Key(k))),
      };
      final acuan = ukuran['no_hp']!;

      for (final k in kunci) {
        expect(
          ukuran[k],
          acuan,
          reason:
              'Kotak "$k" berukuran ${ukuran[k]}, kotak isian lain $acuan. '
              'Keempatnya bertumpuk vertikal di dialog yang sama — beda dua '
              'piksel pun langsung terbaca sebagai kotak yang tidak sejajar. '
              'Semua ukuran: $ukuran',
        );
      }

      // Tingginya harus sasaranSentuh, bukan sekadar "kebetulan sama".
      // Empat kotak yang sama-sama salah tinggi tetap lolos uji di atas.
      expect(acuan.height, AppTheme.sasaranSentuh);
    });

    testWidgets('tepi kiri dan kanannya lurus satu garis — mode $mode', (tester) async {
      await pasang(tester, gelap: gelap);
      final kiri = {for (final k in kunci) k: tester.getTopLeft(find.byKey(Key(k))).dx};
      final kanan = {for (final k in kunci) k: tester.getTopRight(find.byKey(Key(k))).dx};
      expect(kiri.values.toSet(), hasLength(1), reason: 'tepi kiri tidak lurus: $kiri');
      expect(kanan.values.toSet(), hasLength(1), reason: 'tepi kanan tidak lurus: $kanan');
    });
  }

  testWidgets('radius, padding, dan latar identik untuk keempatnya', (tester) async {
    // Ukuran yang sama masih bisa datang dari radius atau latar yang berbeda —
    // itu justru bentuk ketidakseragaman yang paling terlihat pada dropdown,
    // yang dulu sendirian berlatar putih di antara kotak abu-abu.
    late InputDecoration d;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              d = dekorKredensial(c);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    for (final entri in {
      'border': d.border,
      'enabledBorder': d.enabledBorder,
      'disabledBorder': d.disabledBorder,
      'focusedBorder': d.focusedBorder,
    }.entries) {
      final b = entri.value;
      expect(b, isA<OutlineInputBorder>(), reason: '${entri.key} bukan OutlineInputBorder');
      expect(
        (b! as OutlineInputBorder).borderRadius.topLeft.x,
        AppTheme.radiusS,
        reason:
            '${entri.key} memakai radius lain. Menyetel `border` saja tidak '
            'cukup: `enabledBorder` dari inputDecorationTheme menang untuk '
            'keadaan enabled, dan itulah yang membuat radius 8 yang tertulis '
            'di layar ini tidak pernah terpakai.',
      );
    }

    expect(d.filled, isTrue);
    expect(d.isDense, isTrue);
    expect(d.contentPadding, const EdgeInsets.symmetric(horizontal: 12, vertical: 14));
  });

  test('dialog Akun & Kredensial tidak membangun dekorasinya sendiri', () {
    // Uji render di atas membuktikan dekorasinya benar; yang membuat dialognya
    // seragam adalah tidak adanya jalur kedua. Sebelum penyatuan, keempat kotak
    // itu ditulis sendiri-sendiri dan menghasilkan tinggi 42, 48, 48, dan 50.
    final baris = File('lib/screens/admin/data_warga_screen.dart').readAsLinesSync();

    final mulai = baris.indexWhere((b) => b.contains('Future<void> _tampilkanDialogKredensial'));
    expect(mulai, isNonNegative, reason: 'fungsi dialognya tidak ditemukan lagi — perbarui uji ini');

    // Batas bawah: deklarasi anggota kelas berikutnya pada indentasi dua spasi.
    var akhir = baris.length;
    for (var i = mulai + 1; i < baris.length; i++) {
      if (RegExp(r'^  [A-Za-z_<]').hasMatch(baris[i]) && baris[i].contains('(')) {
        akhir = i;
        break;
      }
    }

    final pelanggar = <String>[];
    for (var i = mulai; i < akhir; i++) {
      if (baris[i].contains('InputDecoration(')) {
        pelanggar.add('baris ${i + 1}: ${baris[i].trim()}');
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason:
          'Pakai dekorKredensial() untuk setiap kotak isian di dialog ini.\n'
          'Menulis InputDecoration sendiri berarti memilih tinggi, radius, dan '
          'latarnya sendiri pula.\nDitemukan:\n  ${pelanggar.join("\n  ")}',
    );
  });
}
