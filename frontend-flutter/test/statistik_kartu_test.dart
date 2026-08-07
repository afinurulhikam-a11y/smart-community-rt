import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/models/demographic_model.dart';
import 'package:smart_community/providers/demographic_provider.dart';
import 'package:smart_community/screens/admin/statistik_kependudukan_screen.dart';

/// Respons demografi apa adanya dari backend, dengan angka yang saling
/// konsisten: 36 jiwa, 12 KK, dan setiap grafik menjumlah ke angka itu.
Map<String, dynamic> respons({int lakiLaki = 18, int perempuan = 18, int genderKosong = 0}) {
  final total = lakiLaki + perempuan + genderKosong;
  return {
    'summary': {
      'total_warga': total,
      'total_kk': 12,
      'laki_laki': lakiLaki,
      'perempuan': perempuan,
    },
    'rentan': {'balita': 2, 'lansia': 2, 'janda_duda': 4},
    'gender': [
      {'label': 'Laki-laki', 'jumlah': lakiLaki},
      {'label': 'Perempuan', 'jumlah': perempuan},
      if (genderKosong > 0) {'label': 'Tidak Diisi', 'jumlah': genderKosong},
    ],
    'usia': [
      {'label': 'Balita (0–4)', 'jumlah': 2},
      {'label': 'Anak (5–11)', 'jumlah': 4},
      {'label': 'Remaja (12–24)', 'jumlah': 8},
      {'label': 'Dewasa (25–59)', 'jumlah': total - 16},
      {'label': 'Lansia (60+)', 'jumlah': 2},
      {'label': 'Tidak Diisi', 'jumlah': 0},
    ],
    'pernikahan': [
      {'label': 'Kawin', 'jumlah': total},
    ],
    'domisili': [
      {'label': 'Milik Sendiri', 'jumlah': 12},
    ],
    'pendidikan': [
      {'label': 'SMA', 'jumlah': total},
    ],
    'pekerjaan': [
      {'label': 'Wiraswasta', 'jumlah': total},
    ],
    'agama': [
      {'label': 'Islam', 'jumlah': total},
    ],
  };
}

/// Provider yang sudah membawa data, supaya layarnya melewati keadaan memuat
/// tanpa perlu backend hidup.
class DemografiSiap extends DemographicProvider {
  DemografiSiap(Map<String, dynamic> json) : _isi = DemographicData.fromJson(json);

  final DemographicData _isi;

  @override
  DemographicData? get data => _isi;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
}

Future<void> bukaStatistik(WidgetTester tester, Map<String, dynamic> json) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<DemographicProvider>.value(
      value: DemografiSiap(json),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(child: StatistikKependudukanScreen()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('kartu KK Sewa/Kos sudah tidak ada', (tester) async {
    await bukaStatistik(tester, respons());
    expect(find.textContaining('Sewa'), findsNothing);
    expect(find.textContaining('Kos'), findsNothing);
  });

  testWidgets('kelompok rentan menyisakan tiga kartu, semuanya per jiwa', (tester) async {
    await bukaStatistik(tester, respons());
    expect(find.text('Balita (0-4 th)'), findsOneWidget);
    expect(find.text('Lansia (≥60 th)'), findsOneWidget);
    expect(find.text('Janda / Duda'), findsOneWidget);
  });

  testWidgets('kartu ringkasan menampilkan angka dari respons, bukan angka tetap', (tester) async {
    // Dua respons berbeda harus menghasilkan dua tampilan berbeda. Uji yang
    // hanya memeriksa satu respons akan tetap lolos seandainya angkanya
    // di-hardcode di layar.
    await bukaStatistik(tester, respons(lakiLaki: 18, perempuan: 18));
    expect(find.text('36'), findsWidgets);
    expect(find.text('12'), findsWidgets);

    await bukaStatistik(tester, respons(lakiLaki: 40, perempuan: 31));
    expect(find.text('71'), findsWidgets, reason: 'Total Jiwa tidak mengikuti respons');
    expect(find.text('40'), findsWidgets);
    expect(find.text('31'), findsWidgets);
    expect(find.text('36'), findsNothing, reason: 'angka respons sebelumnya masih tertinggal');
  });

  testWidgets('subjudul Total Jiwa tidak lagi mengaku "aktif"', (tester) async {
    // Penyaring is_aktif sudah dilepas dari kueri supaya Statistik dan Data
    // Warga melaporkan jumlah yang sama. Subjudul yang masih menyebut "aktif"
    // akan menjelaskan angkanya dengan aturan yang tidak berlaku lagi.
    await bukaStatistik(tester, respons());
    expect(find.text('Warga aktif terdata'), findsNothing);
    expect(find.text('Seluruh warga terdata'), findsOneWidget);
  });

  testWidgets('warga tanpa jenis kelamin tetap muncul di grafik gender', (tester) async {
    // Dulu mereka hilang tanpa suara: total menghitungnya, grafik gender tidak.
    await bukaStatistik(tester, respons(lakiLaki: 18, perempuan: 17, genderKosong: 1));
    expect(find.text('71'), findsNothing);
    expect(find.textContaining('Tidak Diisi'), findsWidgets,
        reason: 'warga tanpa jenis kelamin tidak terwakili di grafik gender');
  });
}
