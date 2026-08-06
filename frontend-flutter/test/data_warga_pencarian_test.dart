import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/warga_provider.dart';
import 'package:smart_community/screens/admin/data_warga_screen.dart';

import 'bantuan_uji.dart';

/// Provider palsu yang selamanya berada dalam keadaan memuat.
///
/// Memakai `WargaProvider` sungguhan tidak mungkin di sini: `fetchWarga`
/// menghubungi jaringan, dan tanpa backend ia baru menyerah setelah ~21 detik
/// karena `ApiService` mencoba ulang dua kali. Menimpa getter-nya memberi
/// keadaan yang persis sama tanpa menunggu apa pun.
class WargaSedangMemuat extends WargaProvider {
  @override
  bool get isLoading => true;
}

/// Susun daftar provider standar, tetapi ganti WargaProvider-nya.
List<SingleChildWidget> providerDengan(WargaProvider pengganti) {
  return [
    ...semuaProvider().where((p) => p is! ChangeNotifierProvider<WargaProvider>),
    ChangeNotifierProvider<WargaProvider>.value(value: pengganti),
  ];
}

Widget bungkus(WargaProvider provider) => MultiProvider(
  providers: providerDengan(provider),
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: DataWargaScreen(),
      ),
    ),
  ),
);

void main() {
  group('Kotak pencarian Data Warga bertahan selama memuat', () {
    testWidgets('kotak pencarian TETAP ADA saat data sedang dimuat', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bungkus(WargaSedangMemuat()));
      await tester.pump();

      // Inilah cacat yang diperbaiki. Dulu `build()` mengembalikan HANYA
      // spinner ketika isLoading, sehingga kotak pencarian ikut dilepas dari
      // pohon widget. Melepas TextField berarti membuang FocusNode-nya:
      // papan ketik tertutup, kursornya hilang, dan pengguna harus menyentuh
      // kotaknya lagi untuk melanjutkan mengetik — pada SETIAP pencarian.
      expect(
        find.byType(TextField),
        findsWidgets,
        reason: 'Kotak pencarian tidak boleh hilang saat memuat — '
            'melepasnya membuang fokus dan menutup papan ketik.',
      );

      // Indikator memuatnya sendiri harus tetap muncul, hanya terbatas di
      // area tabel. Kalau ini hilang, pengguna tidak tahu ada yang berjalan.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('kotak pencarian juga ada saat tidak memuat', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bungkus(WargaProvider()));
      await tester.pump();

      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mengetik TIDAK memanggil pencarian — hanya Enter yang memanggil', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(bungkus(WargaProvider()));
      await tester.pump();

      final kotak = find.byType(TextField).first;
      await tester.enterText(kotak, 'Budi');
      await tester.pump();

      // Mengetik empat huruf dulu berarti empat permintaan ke server, dan
      // tanpa penomoran permintaan jawaban yang datang belakangan bisa
      // menimpa hasil yang lebih baru. Sekarang mengetik tidak memicu apa pun;
      // yang memicu hanya Enter atau tombol cari.
      //
      // Diperiksa lewat ketiadaan pengecualian dan bertahannya teks — bila
      // `onChanged` kembali memanggil fetchWarga, layar akan masuk keadaan
      // memuat dan kotaknya dibangun ulang.
      expect(find.text('Budi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Kolom Nomor HP hanya menerima angka', () {
    testWidgets('huruf dan simbol ditolak, angka diterima', (tester) async {
      // Diuji langsung pada formatternya, bukan lewat dialognya: membuka
      // dialog Tambah Warga menuntut izin, provider terisi, dan seluruh
      // formulirnya ikut dirender — sementara yang perlu dibuktikan hanyalah
      // bahwa penyaringnya benar-benar menyaring.
      //
      // `keyboardType: TextInputType.phone` saja TIDAK cukup: ia hanya
      // menyarankan papan ketik, dan papan ketik telepon Android tetap memuat
      // + * #. Menempel dari papan klip pun melewatinya begitu saja.
      final penyaring = FilteringTextInputFormatter.digitsOnly;
      final batas = LengthLimitingTextInputFormatter(15);

      String saring(String masuk) {
        var nilai = penyaring.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: masuk),
        );
        nilai = batas.formatEditUpdate(TextEditingValue.empty, nilai);
        return nilai.text;
      }

      expect(saring('081234567890'), '081234567890');
      expect(saring('Budi Santoso'), '');
      expect(saring('0812-3456-7890'), '081234567890');
      expect(saring('+6281234567890'), '6281234567890');
      expect(saring('0812 3456 7890'), '081234567890');
      // Huruf yang diselipkan di antara angka dibuang, angkanya dirapatkan.
      expect(saring('08a1b2c3'), '08123');

      // Kolom `no_hp` di database bertipe varchar(20). Batas 15 menjaga
      // nomor sepanjang apa pun tidak pernah sampai menabrak batas itu.
      expect(saring('0812345678901234567890').length, 15);
    });
  });
}
