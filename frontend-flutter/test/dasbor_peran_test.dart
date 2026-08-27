import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/peran.dart';
import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/providers/rt_provider.dart';

import 'bantuan_uji.dart';

/// Dasbor harus SELESAI membangun untuk setiap peran.
///
/// ===================================================================
/// Kenapa uji ini ada
/// ===================================================================
///
/// Uji tata letak yang sudah ada merender dasbor dengan provider KOSONG:
/// tanpa peran, tanpa izin, tanpa daftar RT. Itu menangkap luapan tata letak,
/// tetapi buta terhadap satu kelas cacat yang jauh lebih terasa — pohon widget
/// yang tidak pernah berhenti membangun ulang.
///
/// Gejalanya di peramban bukan galat melainkan halaman yang berat dan tidak
/// bisa ditekan; tidak ada yang tercetak di konsol, karena tidak ada yang
/// gagal. `pumpAndSettle` adalah alat yang tepat untuk itu: ia memompa frame
/// sampai tidak ada lagi yang terjadwal, dan MELEMPAR ketika keadaan itu tidak
/// pernah tercapai.
///
/// Diuji per peran, karena isi dasbor bergantung pada izin dan pada jumlah RT
/// yang terlihat — dan peran lintas RT adalah satu-satunya yang memunculkan
/// pemilih RT.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const duaRt = [
    RtModel(id: 'a', kode: '001', nama: 'RT 001', rwKode: '005'),
    RtModel(id: 'b', kode: '002', nama: 'RT 002 Kenanga', rwKode: '005'),
  ];

  /// Muatan `/menu-akses/me` seperti yang dikirim server: `kode`, plus empat
  /// bendera aksi per menu. Bentuknya diambil dari `menu_akses.controller.js`.
  Map<String, dynamic> izinUntuk(String role, {required bool bolehUbah}) => {
        'role': role,
        'role_label': Peran.label(role),
        'menus': [
          for (final kode in const [
            'kependudukan.warga',
            'kependudukan.kk',
            'kependudukan.bansos',
            'kependudukan.statistik',
            'keuangan.iuran',
            'keuangan.kas',
            'keuangan.bop',
            'inventaris.barang',
            'inventaris.peminjaman',
            'layanan.visitor',
            'layanan.surat',
            'kegiatan.agenda',
            'aspirasi.darurat',
            'aspirasi.pengaduan',
            'aspirasi.polling',
            'pengaturan.log',
          ])
            {
              'kode': kode,
              'can_view': true,
              'can_create': bolehUbah,
              'can_update': bolehUbah,
              'can_delete': bolehUbah,
            },
        ],
      };

  Future<void> ujiPeran(
    WidgetTester tester,
    String role, {
    required List<RtModel> daftarRt,
    required bool bolehUbah,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(bungkusDasbor());
    final ctx = tester.element(find.byType(Scaffold).first);

    ctx.read<AuthService>().pasangUji(user: {
      'id': 'uji-$role',
      'nama': Peran.label(role),
      'role': role,
      'must_change_password': false,
    });
    ctx.read<PermissionProvider>()
      ..setRole(role)
      ..terapkanData(izinUntuk(role, bolehUbah: bolehUbah));
    ctx.read<RtProvider>().isiUntukUji(daftarRt);

    // Inilah pemeriksaannya. Bila pohonnya membangun ulang tanpa henti,
    // `pumpAndSettle` tidak pernah tenang dan melempar — persis keadaan yang
    // di peramban terlihat sebagai halaman berat yang tidak bisa ditekan.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: 'Dasbor melempar saat dirender sebagai $role.');
  }

  testWidgets('Ketua RW — dua RT, pemilih lingkup tampil', (tester) async {
    await ujiPeran(tester, Peran.ketuaRw, daftarRt: duaRt, bolehUbah: false);
    // Kendali positif: kalau pemilihnya tidak tampil, uji ini tidak sedang
    // memeriksa keadaan yang dimaksud.
    expect(find.byIcon(Icons.apartment_rounded), findsWidgets);
  });

  testWidgets('Ketua RT — satu RT, tanpa pemilih', (tester) async {
    await ujiPeran(tester, Peran.ketuaRt, daftarRt: [duaRt.first], bolehUbah: true);
  });

  testWidgets('Administrator — dua RT', (tester) async {
    await ujiPeran(tester, Peran.admin, daftarRt: duaRt, bolehUbah: true);
  });

  testWidgets('Warga — satu RT', (tester) async {
    await ujiPeran(tester, Peran.warga, daftarRt: [duaRt.first], bolehUbah: false);
  });
}
