import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/screens/admin/bantuan_sosial_screen.dart';
import 'package:smart_community/screens/admin/bop_screen.dart';
import 'package:smart_community/screens/admin/data_barang_screen.dart';
import 'package:smart_community/screens/admin/data_warga_screen.dart';
import 'package:smart_community/screens/admin/e_visitor_screen.dart';
import 'package:smart_community/screens/admin/iuran_warga_screen.dart';
import 'package:smart_community/screens/admin/kas_rt_screen.dart';
import 'package:smart_community/screens/admin/log_aktivitas_screen.dart';
import 'package:smart_community/screens/admin/peminjaman_screen.dart';
import 'package:smart_community/screens/admin/pengaduan_screen.dart';
import 'package:smart_community/screens/admin/polling_warga_screen.dart';
import 'package:smart_community/screens/admin/reset_sistem_screen.dart';
import 'package:smart_community/screens/admin/kelola_rt_screen.dart';
import 'package:smart_community/screens/admin/perbandingan_rt_screen.dart';
import 'package:smart_community/screens/admin/statistik_kependudukan_screen.dart';
import 'package:smart_community/screens/admin/status_darurat_screen.dart';
import 'package:smart_community/screens/admin/surat_menyurat_screen.dart';

import 'bantuan_uji.dart';

/// Menjaga mode gelap tetap berfungsi.
///
/// Mode gelap dulu rusak dan tidak ada satu pun dari 133 pengujian yang
/// menyadarinya, karena semuanya merender dalam tema terang saja. Temanya
/// bahkan sudah ada dan lengkap — yang kurang cuma `darkTheme:` di
/// `MaterialApp`, sehingga hanya satu subtree yang ikut menggelap.
///
/// **Batas pengujian ini harus dinyatakan terus terang.** Ia membuktikan
/// layarnya tidak meledak dalam tema gelap, DAN bahwa permukaan utamanya
/// benar-benar mengikuti tema. Ia TIDAK membuktikan setiap teks punya kontras
/// yang cukup — sebuah label yang masih memakai warna ditulis mati akan lolos
/// di sini. Untuk itu tetap perlu dilihat dengan mata di perangkat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final layar = <String, Widget Function()>{
    'Kas RT': () => const KasRtScreen(),
    'Iuran Warga': () => const IuranWargaScreen(),
    'Dana BOP': () => const BopScreen(),
    'Data Warga': () => const DataWargaScreen(),
    'Bantuan Sosial': () => const BantuanSosialScreen(),
    'Statistik Kependudukan': () => const StatistikKependudukanScreen(),
    'Data Barang': () => const DataBarangScreen(),
    'Peminjaman': () => const PeminjamanScreen(),
    'E-Visitor': () => const EVisitorScreen(),
    'Surat Menyurat': () => const SuratMenyuratScreen(),
    'Pengaduan': () => const PengaduanScreen(),
    'Polling Warga': () => const PollingWargaScreen(),
    'Status Darurat': () => const StatusDaruratScreen(),
    'Log Aktivitas': () => const LogAktivitasScreen(),
    'Reset Sistem': () => const ResetSistemScreen(),
    'Kelola RT': () => const KelolaRtScreen(),
    'Perbandingan RT': () => const PerbandinganRtScreen(),
  };

  group('setiap layar dirender dalam tema gelap', () {
    layar.forEach((nama, buat) {
      testWidgets('$nama tanpa error di mode gelap', (tester) async {
        pasangKondisi(tester, kondisiUji[1]); // ponsel umum 360x800
        await tester.pumpWidget(bungkusLayar(buat(), gelap: true));
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull, reason: '$nama meledak di mode gelap');
      });
    });
  });

  testWidgets('MainDashboard dirender di mode gelap', (tester) async {
    pasangKondisi(tester, kondisiUji[1]);
    await tester.pumpWidget(bungkusDasbor(gelap: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Scaffold benar-benar memakai warna gelap, bukan sekadar tidak meledak', (
    tester,
  ) async {
    pasangKondisi(tester, kondisiUji[1]);
    await tester.pumpWidget(bungkusLayar(const KasRtScreen(), gelap: true));
    await tester.pump(const Duration(milliseconds: 100));

    // Inilah pemeriksaan yang membedakan "gelap" dari "tidak error": kalau
    // `darkTheme` lepas dari MaterialApp lagi, nilai ini kembali ke warna
    // terang dan pengujian gagal.
    final konteks = tester.element(find.byType(Scaffold).first);
    final tema = Theme.of(konteks);

    expect(tema.brightness, Brightness.dark);
    expect(tema.scaffoldBackgroundColor, AppTheme.darkTheme.scaffoldBackgroundColor);
    expect(tema.cardColor, AppTheme.darkTheme.cardColor);
  });

  testWidgets('tema terang tetap terang — mode gelap tidak bocor ke mana-mana', (tester) async {
    pasangKondisi(tester, kondisiUji[1]);
    await tester.pumpWidget(bungkusLayar(const KasRtScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    final tema = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(tema.brightness, Brightness.light);
  });
}
