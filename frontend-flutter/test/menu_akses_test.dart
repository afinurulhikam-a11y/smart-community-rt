import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/widgets/sidebar_menu.dart';

import 'bantuan_uji.dart';

/// Sinkronisasi Menu & Akses ↔ sidebar.
///
/// ===================================================================
/// Yang diuji di sini
/// ===================================================================
///
/// Bahwa saklar di layar Menu & Akses benar-benar mengubah NAVIGASI, bukan
/// hanya tampilannya sendiri. Sumber izinnya satu — `PermissionProvider` —
/// dan sidebar membacanya dari sana, jadi menyetel provider di sini setara
/// dengan administrator menekan saklar lalu pengguna sasaran masuk kembali.
///
/// Penegakan sisi server diuji terpisah oleh `backend-node/test-menu-akses.js`;
/// menyembunyikan menu memang bukan lapis keamanannya.

/// Membangun izin seperti yang dikirim `GET /menu-akses/me`.
Map<String, dynamic> _dataIzin(Map<String, List<bool>> menus, {String role = 'ketua_rt'}) => {
      'role': role,
      'role_label': role,
      'menus': [
        for (final e in menus.entries)
          {
            'kode': e.key,
            'can_view': e.value[0],
            'can_create': e.value[1],
            'can_update': e.value[2],
            'can_delete': e.value[3],
          },
      ],
    };

const _penuh = [true, true, true, true];
const _lihatSaja = [true, false, false, false];
const _tertutup = [false, false, false, false];

Widget _bungkusSidebar(PermissionProvider izin, {required String role, int terpilih = 12}) {
  return MultiProvider(
    providers: [
      ...semuaProvider(),
      ChangeNotifierProvider<PermissionProvider>.value(value: izin),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: 280,
          // Tinggi dilebihkan dengan sengaja. Isi sidebar berada di dalam
          // ListView yang membangun anaknya secara malas — entri di bawah garis
          // pandang tidak pernah dibuat, sehingga `find.text` melaporkannya
          // "tidak ada" padahal ia hanya belum tergulir. Grup Pengaturan yang
          // berada paling bawah persis mengenai jebakan itu.
          height: 2400,
          child: SidebarMenu(
            selectedIndex: terpilih,
            role: role,
            onItemSelected: (_) {},
            onLogout: () {},
          ),
        ),
      ),
    ),
  );
}

PermissionProvider _izinDari(Map<String, List<bool>> menus, {String role = 'ketua_rt'}) {
  final p = PermissionProvider();
  p.terapkanData(_dataIzin(menus, role: role));
  return p;
}


/// Memasang layar tinggi lebih dulu, baru menggambar sidebar.
///
/// Isi sidebar berada di dalam ListView yang membangun anaknya secara malas,
/// dan tingginya dibatasi UKURAN LAYAR uji (bawaan 800x600) — bukan oleh
/// SizedBox pembungkusnya, yang justru ikut terpangkas oleh batas itu.
/// Akibatnya grup Pengaturan di paling bawah tidak pernah dibangun, dan
/// pencarian teks melaporkannya hilang padahal ia hanya belum tergulir.
Future<void> _pumpSidebar(
  WidgetTester tester,
  PermissionProvider izin, {
  required String role,
  int terpilih = 12,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_bungkusSidebar(izin, role: role, terpilih: terpilih));
  await tester.pumpAndSettle();
}

void main() {
  group('Sidebar mengikuti izin dari Menu & Akses', () {
    testWidgets('Mematikan "Lihat" menyembunyikan menu itu dari sidebar', (tester) async {
      // Keadaan awal: Data Warga boleh dilihat.
      final izin = _izinDari({
        'kependudukan.warga': _penuh,
        'kependudukan.bansos': _penuh,
      });

      await _pumpSidebar(tester, izin, role: 'ketua_rt');
      expect(find.text('Data Warga'), findsOneWidget);

      // Administrator mematikan saklar "Lihat" untuk peran ini, lalu pengguna
      // sasaran memuat ulang izinnya.
      izin.terapkanData(_dataIzin({
        'kependudukan.warga': _tertutup,
        'kependudukan.bansos': _penuh,
      }));
      await _pumpSidebar(tester, izin, role: 'ketua_rt');

      expect(find.text('Data Warga'), findsNothing,
          reason: 'saklar Lihat harus benar-benar menghapus menu dari navigasi');
      expect(find.text('Bantuan Sosial'), findsOneWidget,
          reason: 'menu lain dalam grup yang sama tidak boleh ikut hilang');
    });

    testWidgets('Data KK mengikuti izin kependudukan.warga, bukan izin sendiri',
        (tester) async {
      // Data KK sengaja TIDAK punya baris izin sendiri — ia tampilan lain atas
      // data yang sama. Jadi ia harus muncul dan hilang bersama Data Warga.
      final ada = _izinDari({'kependudukan.warga': _penuh});
      await _pumpSidebar(tester, ada, role: 'ketua_rt');

      expect(find.text('Data Warga'), findsOneWidget);
      expect(find.text('Data KK'), findsOneWidget);

      // Izin tetangga SENGAJA dibiarkan menyala supaya grup Kependudukan tetap
      // tergambar. Tanpa itu seluruh grup ikut hilang, dan uji ini akan lulus
      // walau gerbang Data KK-nya sendiri dicabut — lulus karena alasan yang
      // salah. Ditemukan saat membuktikan uji ini benar-benar bergigi.
      final tiada = _izinDari({
        'kependudukan.warga': _tertutup,
        'kependudukan.bansos': _penuh,
      });
      await _pumpSidebar(tester, tiada, role: 'ketua_rt');

      expect(find.text('Bantuan Sosial'), findsOneWidget,
          reason: 'prasyarat: grup Kependudukan harus tetap tergambar');
      expect(find.text('Data Warga'), findsNothing);
      expect(find.text('Data KK'), findsNothing,
          reason: 'Data KK harus ikut tertutup bersama Data Warga');
    });

    testWidgets('Profil Saya selalu tersedia walau tanpa izin apa pun', (tester) async {
      // Data diri sendiri, bukan modul RT. Mencabutnya berarti seseorang tidak
      // bisa mengganti kata sandinya sendiri.
      final kosong = _izinDari(const {}, role: 'warga');
      await _pumpSidebar(tester, kosong, role: 'warga', terpilih: 81);

      expect(find.text('Profil Saya'), findsOneWidget);
    });

    testWidgets('Dashboard tetap tampil meski bukan lagi sebuah izin', (tester) async {
      // `dashboard` dihapus dari registry (migrasi v31). Beranda tetap ada
      // untuk semua peran — yang hilang hanya saklar yang tidak berpengaruh.
      final kosong = _izinDari(const {}, role: 'warga');
      await _pumpSidebar(tester, kosong, role: 'warga', terpilih: 0);

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('Status Darurat mengikuti aspirasi.darurat', (tester) async {
      final ada = _izinDari({'aspirasi.darurat': _penuh}, role: 'warga');
      await _pumpSidebar(tester, ada, role: 'warga', terpilih: 60);
      expect(find.text('Status Darurat'), findsOneWidget);

      final tiada = _izinDari({'aspirasi.darurat': _tertutup}, role: 'warga');
      await _pumpSidebar(tester, tiada, role: 'warga', terpilih: 60);
      expect(find.text('Status Darurat'), findsNothing);
    });
  });

  group('Menu sistem dan Administrator', () {
    testWidgets('Menu & Akses dan Reset Sistem hanya untuk Administrator', (tester) async {
      final adminIzin = _izinDari(const {}, role: 'admin');
      await _pumpSidebar(tester, adminIzin, role: 'admin', terpilih: 85);

      expect(find.text('Menu & Akses'), findsOneWidget);
      // Label disamakan dengan registry; sebelumnya sidebar menulis "Reset".
      expect(find.text('Reset Sistem'), findsOneWidget);
      expect(find.text('Reset'), findsNothing,
          reason: 'label lama tidak boleh tersisa — registry menyebutnya "Reset Sistem"');
    });

    testWidgets('Peran lain tidak melihat menu sistem walau izinnya dipaksa menyala',
        (tester) async {
      final izin = _izinDari({
        'pengaturan.akses': _penuh,
        'pengaturan.reset': _penuh,
      }, role: 'ketua_rt');

      await _pumpSidebar(tester, izin, role: 'ketua_rt', terpilih: 84);

      expect(find.text('Menu & Akses'), findsNothing);
      expect(find.text('Reset Sistem'), findsNothing);
    });

    testWidgets('Administrator melihat seluruh menu tanpa satu pun baris izin',
        (tester) async {
      // `izinUntuk` mengembalikan Izin.penuh() untuk admin sebelum melihat peta,
      // cerminan dari middleware yang meloloskan admin sebelum menyentuh tabel.
      final kosong = _izinDari(const {}, role: 'admin');

      for (final entri in {
        12: ['Data Warga', 'Data KK'],
        21: ['Iuran Warga', 'Kas RT', 'Dana BOP'],
        31: ['Data Barang', 'Peminjaman'],
        43: ['E-Visitor', 'Surat Menyurat'],
      }.entries) {
        await _pumpSidebar(tester, kosong, role: 'admin', terpilih: entri.key);
        for (final label in entri.value) {
          expect(find.text(label), findsOneWidget, reason: 'admin harus melihat "$label"');
        }
      }
    });
  });

  group('Izin gagal tertutup', () {
    test('Kode yang tidak ada di peta ditolak, bukan diizinkan', () {
      final p = _izinDari({'kependudukan.warga': _penuh}, role: 'warga');

      expect(p.bolehLihat('keuangan.bop', userRole: 'warga'), isFalse);
      expect(p.bolehTambah('keuangan.bop', userRole: 'warga'), isFalse);
      expect(p.bolehUbah('modul.yang.tidak.ada', userRole: 'warga'), isFalse);
      expect(p.bolehHapus('modul.yang.tidak.ada', userRole: 'warga'), isFalse);
    });

    test('Aksi dipisah: lihat menyala tidak membuka tambah/ubah/hapus', () {
      final p = _izinDari({'inventaris.barang': _lihatSaja}, role: 'sekretaris');

      expect(p.bolehLihat('inventaris.barang', userRole: 'sekretaris'), isTrue);
      expect(p.bolehTambah('inventaris.barang', userRole: 'sekretaris'), isFalse);
      expect(p.bolehUbah('inventaris.barang', userRole: 'sekretaris'), isFalse);
      expect(p.bolehHapus('inventaris.barang', userRole: 'sekretaris'), isFalse);
      expect(p.hanyaLihat('inventaris.barang', userRole: 'sekretaris'), isTrue);
    });

    test('Administrator penuh untuk kode apa pun, termasuk yang tak dikenal', () {
      final p = _izinDari(const {}, role: 'admin');
      expect(p.bolehHapus('kependudukan.warga', userRole: 'admin'), isTrue);
      expect(p.bolehHapus('apa.pun', userRole: 'admin'), isTrue);
    });

    test('bersihkan() menghapus izin pengguna sebelumnya', () {
      final p = _izinDari({'kependudukan.warga': _penuh}, role: 'ketua_rt');
      expect(p.bolehLihat('kependudukan.warga', userRole: 'ketua_rt'), isTrue);

      p.bersihkan();

      // Perangkat bersama: pengguna berikutnya tidak boleh mewarisi izin.
      expect(p.bolehLihat('kependudukan.warga', userRole: 'ketua_rt'), isFalse);
      expect(p.sudahDimuat, isFalse);
    });
  });
}
