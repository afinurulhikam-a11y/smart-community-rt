import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_community/widgets/tabel_responsif.dart';

/// Menjaga [TabelResponsif] — satu-satunya tempat bentuk tabel dan bentuk kartu
/// diputuskan, jadi cacat di sini menular ke tiga belas layar sekaligus.
///
/// Datanya sengaja panjang. Merender tabel dengan data pendek hampir selalu
/// lolos; yang membuat tampilan meluber di lapangan justru keterangan panjang
/// dan angka rupiah berjajar — itulah yang diuji di sini.
void main() {
  /// Sepanjang yang mungkin ditulis bendahara di kolom keterangan.
  const keteranganPanjang =
      'Pembelian 4 galon air mineral, 2 dus snack kotak, dan sewa tenda '
      'untuk kegiatan kerja bakti bulanan RT tanggal 17 Agustus';

  List<BarisTabel> contohBaris({int jumlah = 3}) {
    return List.generate(jumlah, (i) {
      return BarisTabel(
        sel: [
          SelTabel.teks('NO', '${i + 1}', sembunyiDiKartu: true),
          SelTabel.teks('TANGGAL', '17 Agustus 2026'),
          SelTabel.teks('KETERANGAN', keteranganPanjang, utama: true),
          SelTabel.teks('PEMASUKAN', 'Rp 1.250.000'),
          SelTabel.teks('SALDO', 'Rp 12.750.000'),
        ],
        aksi: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
            IconButton(icon: const Icon(Icons.delete), onPressed: () {}),
          ],
        ),
      );
    });
  }

  Widget bungkus(Widget anak) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: anak,
          ),
        ),
      );

  const kolom = ['NO', 'TANGGAL', 'KETERANGAN', 'PEMASUKAN', 'SALDO'];

  const ukuran = <String, Size>{
    'ponsel kecil (320x568)': Size(320, 568),
    'ponsel umum (360x800)': Size(360, 800),
    'ponsel besar (412x915)': Size(412, 915),
    'tablet (800x1280)': Size(800, 1280),
    'desktop (1440x900)': Size(1440, 900),
  };

  ukuran.forEach((nama, size) {
    testWidgets('dirender tanpa error pada $nama', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        bungkus(TabelResponsif(kolom: kolom, baris: contohBaris())),
      );
      await tester.pump();

      // Menangkap galat tata letak apa pun, termasuk meluber.
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ponsel memakai kartu, bukan tabel yang digeser menyamping',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      bungkus(TabelResponsif(kolom: kolom, baris: contohBaris())),
    );
    await tester.pump();

    expect(find.byType(DataTable), findsNothing);
    // Isinya tetap harus tampil — "tidak error" saja tidak cukup kalau
    // datanya ternyata tidak ikut dirender.
    expect(find.textContaining('Rp 12.750.000'), findsWidgets);
  });

  testWidgets('desktop tetap memakai tabel', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      bungkus(TabelResponsif(kolom: kolom, baris: contohBaris())),
    );
    await tester.pump();

    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('kolom bertanda sembunyiDiKartu tidak muncul di kartu',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      bungkus(TabelResponsif(kolom: kolom, baris: contohBaris(jumlah: 1))),
    );
    await tester.pump();

    // Nomor urut tidak menambah apa pun di kartu; labelnya tidak boleh ikut.
    expect(find.text('NO'), findsNothing);
    expect(find.text('TANGGAL'), findsOneWidget);
  });

  testWidgets('daftar kosong menampilkan keterangan, bukan tabel kosong',
      (tester) async {
    await tester.pumpWidget(
      bungkus(const TabelResponsif(kolom: kolom, baris: [])),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Belum ada data.'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
  });

  testWidgets('baris tanpa tombol tetap sejajar dengan yang bertombol',
      (tester) async {
    // Jumlah sel harus tetap cocok dengan jumlah kolom walau sebagian baris
    // tidak punya aksi — kalau tidak, DataTable melempar galat.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final campuran = [
      contohBaris(jumlah: 1).first,
      BarisTabel(
        sel: [
          SelTabel.teks('NO', '2', sembunyiDiKartu: true),
          SelTabel.teks('TANGGAL', '18 Agustus 2026'),
          SelTabel.teks('KETERANGAN', 'Iuran warga', utama: true),
          SelTabel.teks('PEMASUKAN', 'Rp 50.000'),
          SelTabel.teks('SALDO', 'Rp 12.800.000'),
        ],
      ),
    ];

    await tester.pumpWidget(
      bungkus(TabelResponsif(kolom: kolom, baris: campuran)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('footer menampilkan ringkasan dan pagination saat totalData ada',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      bungkus(TabelResponsif(
        kolom: kolom,
        baris: contohBaris(jumlah: 10),
        currentPage: 2,
        totalPages: 6,
        totalData: 57,
        perPage: 10,
      )),
    );
    await tester.pump();

    // Rentang dihitung dari halaman (11–20), bukan dari panjang baris.
    expect(find.text('Menampilkan 11–20 dari 57 data'), findsOneWidget);
    expect(find.text('Halaman 2 dari 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer muncul walau hanya satu halaman', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      bungkus(TabelResponsif(
        kolom: kolom,
        baris: contohBaris(jumlah: 3),
        currentPage: 1,
        totalPages: 1,
        totalData: 3,
        perPage: 10,
      )),
    );
    await tester.pump();

    expect(find.text('Menampilkan 1–3 dari 3 data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
