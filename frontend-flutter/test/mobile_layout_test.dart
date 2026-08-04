import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:smart_community/screens/admin/status_darurat_screen.dart';
import 'package:smart_community/screens/admin/surat_menyurat_screen.dart';

import 'bantuan_uji.dart';

/// Menjaga agar layar tidak meluber di ponsel.
///
/// `flutter analyze` tidak bisa melihat galat tata letak sama sekali — sebuah
/// Row yang isinya 460px di layar 360px lolos analisis dengan bersih dan baru
/// ketahuan sebagai garis kuning-hitam di perangkat. Cara yang sudah terbukti
/// menangkapnya adalah merender pada ukuran nyata lalu memeriksa
/// `takeException()`, persis seperti `login_screen_test.dart` menangkap cacat
/// Stack di layar login.
///
/// BATASNYA: provider di sini kosong karena tidak ada backend saat pengujian,
/// jadi yang tertangkap adalah cacat STRUKTUR — bilah header, filter, toolbar,
/// paginasi — bukan yang hanya muncul saat datanya panjang. Risiko yang kedua
/// ditangani `tabel_responsif_test.dart`, yang memang memakai teks panjang.
void main() {
  // Panggilan jaringan di initState akan gagal tanpa backend; ApiService
  // menangkapnya sendiri dan mengembalikan success: false, jadi layarnya tetap
  // dirender — yang justru dibutuhkan pengujian ini.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Layar yang dibuka pengurus maupun warga dari ponsel.
  final layar = <String, Widget Function()>{
    'Kas RT': () => const KasRtScreen(),
    'Iuran Warga': () => const IuranWargaScreen(),
    'Dana BOP': () => const BopScreen(),
    'Data Warga': () => const DataWargaScreen(),
    'Bantuan Sosial': () => const BantuanSosialScreen(),
    'Data Barang': () => const DataBarangScreen(),
    'Peminjaman': () => const PeminjamanScreen(),
    'E-Visitor': () => const EVisitorScreen(),
    'Surat Menyurat': () => const SuratMenyuratScreen(),
    'Pengaduan': () => const PengaduanScreen(),
    'Polling Warga': () => const PollingWargaScreen(),
    'Status Darurat': () => const StatusDaruratScreen(),
    'Log Aktivitas': () => const LogAktivitasScreen(),
  };

  // Kondisi uji ada di `bantuan_uji.dart` — termasuk dua varian yang meniru
  // HP Android sungguhan: berponi, berbilah gestur, dan dengan font sistem
  // diperbesar. Ketiganya tidak bisa ditiru Chrome, dan itulah sebabnya cacat
  // tampilan lolos sampai ke perangkat.
  for (final k in kondisiUji) {
    layar.forEach((namaLayar, buat) {
      testWidgets('$namaLayar dirender tanpa error pada ${k.nama}', (tester) async {
        pasangKondisi(tester, k);

        await tester.pumpWidget(bungkusLayar(buat(), skalaFont: k.skalaFont));
        // pump, bukan pumpAndSettle: layar memuat data lewat
        // addPostFrameCallback dan pumpAndSettle akan menunggu selamanya bila
        // ada animasi berulang seperti CircularProgressIndicator.
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Dashboard dirender tanpa error pada ${k.nama}', (tester) async {
      pasangKondisi(tester, k);

      await tester.pumpWidget(bungkusDasbor(skalaFont: k.skalaFont));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
