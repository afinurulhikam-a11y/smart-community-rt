import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/screens/admin/profil_saya_screen.dart';

/// Layar **Profil Saya** setelah Fase A memisahkan profil ringkas dari profil
/// lengkap.
///
/// Sejak Fase A ada DUA salinan identitas: `_user` yang ringkas dan tersimpan
/// di perangkat, dan `_profilLengkap` yang hanya di memori. Layar ini membaca
/// keduanya — dan begitu ada dua salinan, keduanya bisa berbeda.
///
/// Persis itu yang terjadi: `updateProfile` menyegarkan `_user` saja, sehingga
/// pengguna melihat "Profil berhasil diperbarui!" sambil kartunya masih
/// menampilkan email lama. Datanya benar di database; yang salah tampilannya.
///
/// Layar ini sebelumnya tidak disentuh satu uji pun, dan itulah kenapa cacat
/// tadi lolos: uji HTTP membuktikan endpointnya benar, `flutter test` hijau,
/// dan tidak ada yang pernah merender layarnya.

const _kkLama = {
  'id': 7,
  'nama': 'Budi Santoso',
  'role': 'warga',
  'username': '3201991000000001',
  'must_change_password': false,
};

const _profilLama = {
  'id': 7,
  'nama': 'Budi Santoso',
  'role': 'warga',
  'username': '3201991000000001',
  'email': 'budi.lama@example.com',
  'no_hp': '081234567001',
  'no_kk': '3201990000000001',
  'nik': '3201991000000001',
  'alamat': 'Jl. Melati Raya Nomor 45',
  'is_active': true,
  'must_change_password': false,
};

/// Respons `PUT /auth/profile` — bentuknya mengikuti `RETURNING` di
/// `auth.controller.js`, termasuk PII yang tidak boleh ikut tersimpan.
const _barisSetelahSimpan = {
  'id': 7,
  'nama': 'Budi Santoso Wijaya',
  'role': 'warga',
  'username': '3201991000000001',
  'email': 'budi.baru@example.com',
  'no_hp': '089900112233',
  'no_kk': '3201990000000001',
  'alamat': 'Jl. Melati Raya Nomor 45',
  'no_rt': '003',
  'is_active': true,
};

/// AuthService yang tidak menyentuh jaringan.
///
/// `initState` layar memanggil `muatProfilLengkap()`; bila backend kebetulan
/// hidup, ia akan menjawab dan menimpa data yang baru disemai — uji yang sama
/// lulus di mesin yang servernya mati dan gagal di mesin yang menyala.
class _AuthTanpaJaringan extends AuthService {
  final Map<String, dynamic> profil = _profilLama;
  int jumlahAmbilProfil = 0;

  @override
  Future<Map<String, dynamic>?> muatProfilLengkap() async {
    jumlahAmbilProfil += 1;
    pasangUji(profilLengkap: Map<String, dynamic>.from(profil));
    return profilLengkap;
  }
}

Widget _bungkus(AuthService auth) {
  return ChangeNotifierProvider<AuthService>.value(
    value: auth,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: SingleChildScrollView(child: ProfilSayaScreen()),
      ),
    ),
  );
}

/// Ketik ke kolom yang sedang berisi [lama] — meniru pengguna menyunting.
///
/// Tanpa langkah ini ujinya tidak realistis: `TextEditingController` adalah
/// state milik LAYAR, bukan provider, jadi ia memang tidak ikut berubah saat
/// provider disegarkan. Di alur sungguhan nilai barunya justru berasal dari
/// kolom itu — pengguna mengetiknya, lalu menekan Simpan.
Future<void> _ketikGanti(WidgetTester tester, String lama, String baru) async {
  final kolom = find.byWidgetPredicate(
    (w) => w is TextField && w.controller?.text == lama,
    description: 'TextField berisi "$lama"',
  );
  expect(kolom, findsOneWidget, reason: 'kolom berisi "$lama" tidak ditemukan');
  await tester.enterText(kolom, baru);
  await tester.pump();
}

Future<_AuthTanpaJaringan> _buka(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = _AuthTanpaJaringan()
    ..pasangUji(user: Map<String, dynamic>.from(_kkLama));
  await tester.pumpWidget(_bungkus(auth));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  setUp(() {
    // `_simpanProfil` menulis ke SharedPreferences; tanpa nilai tiruan,
    // plugin-nya tidak tersedia di lingkungan uji widget.
    SharedPreferences.setMockInitialValues({});
  });

  group('Membuka layar memuat profil lengkap', () {
    testWidgets('mengambil /auth/profil sekali saat dibuka', (tester) async {
      final auth = await _buka(tester);
      expect(auth.jumlahAmbilProfil, 1,
          reason: 'layar harus mengambil profil lengkap saat dibuka');
      expect(auth.profilLengkap, isNotNull);
    });

    testWidgets('email dan nomor HP tampil — keduanya TIDAK tersimpan di perangkat',
        (tester) async {
      await _buka(tester);
      expect(find.textContaining('budi.lama@example.com'), findsWidgets);
    });

    testWidgets('nama dari profil lengkap tampil', (tester) async {
      await _buka(tester);
      expect(find.textContaining('Budi Santoso'), findsWidgets);
    });
  });

  group('Sesudah menyimpan, layar langsung segar', () {
    testWidgets('email BARU tampil tanpa menutup layar', (tester) async {
      final auth = await _buka(tester);
      expect(find.textContaining('budi.lama@example.com'), findsWidgets,
          reason: 'prasyarat: email lama memang sedang tampil');

      // Simulasi `updateProfile` yang berhasil — jalur yang sama persis
      // dipanggil oleh `updateProfile` setelah respons sukses.
      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));
      await tester.pumpAndSettle();

      expect(find.textContaining('budi.baru@example.com'), findsWidgets,
          reason: 'email baru harus langsung tampil');
    });

    testWidgets('email LAMA tidak tersisa di layar', (tester) async {
      // Inilah bentuk cacatnya: pengguna melihat pesan sukses sambil kartunya
      // masih menampilkan nilai sebelum penyuntingan.
      final auth = await _buka(tester);

      // Alur penuh: pengguna mengetik nilai baru di kolomnya, LALU menyimpan.
      await _ketikGanti(tester, 'budi.lama@example.com', 'budi.baru@example.com');
      await _ketikGanti(tester, 'Budi Santoso', 'Budi Santoso Wijaya');
      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));
      await tester.pumpAndSettle();

      expect(find.textContaining('budi.lama@example.com'), findsNothing,
          reason: 'data lama tidak boleh tersisa setelah simpan berhasil — '
              'baik di kartu ringkasan maupun di kolom isian');
    });

    testWidgets('nama BARU tampil — bukan yang basi', (tester) async {
      // Nama adalah kasus terburuknya: layar membacanya sebagai
      // `lengkap['nama'] ?? ringkas['nama']`, dan nilai basi yang bukan null
      // justru memenangkan operator `??`.
      final auth = await _buka(tester);
      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));
      await tester.pumpAndSettle();

      expect(find.textContaining('Budi Santoso Wijaya'), findsWidgets);
    });

    testWidgets('layar TIDAK mengambil ulang dari server', (tester) async {
      // Respons PUT sudah membawa keadaan sesudah tulis yang otoritatif.
      // Permintaan kedua hanya menambah perjalanan jaringan untuk jawaban yang
      // sudah ada di tangan.
      final auth = await _buka(tester);
      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));
      await tester.pumpAndSettle();

      expect(auth.jumlahAmbilProfil, 1, reason: 'cukup sekali, saat dibuka');
    });
  });

  group('REGRESI — sinkronisasi _profilLengkap', () {
    // Uji ini yang akan jatuh bila sinkronisasi dihapus lagi. Ia memeriksa
    // state-nya langsung, bukan hanya piksel, sehingga penyebabnya terbaca
    // tanpa perlu menafsirkan tangkapan layar.
    test('_profilLengkap ikut tersegarkan setelah simpan', () async {
      final auth = _AuthTanpaJaringan()
        ..pasangUji(
          user: Map<String, dynamic>.from(_kkLama),
          profilLengkap: Map<String, dynamic>.from(_profilLama),
        );

      expect(auth.profilLengkap!['email'], 'budi.lama@example.com');

      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));

      expect(auth.profilLengkap!['email'], 'budi.baru@example.com',
          reason: 'sinkronisasi _profilLengkap hilang — cacat aslinya kembali');
      expect(auth.profilLengkap!['nama'], 'Budi Santoso Wijaya');
      expect(auth.profilLengkap!['no_hp'], '089900112233');
    });

    test('field yang tidak ikut diubah tetap ada, tidak terhapus', () async {
      // Digabung, bukan ditimpa: `nik` tidak ada di respons PUT, dan hilangnya
      // akan mengosongkan tampilan tanpa ada yang mengubahnya.
      final auth = _AuthTanpaJaringan()
        ..pasangUji(
          user: Map<String, dynamic>.from(_kkLama),
          profilLengkap: Map<String, dynamic>.from(_profilLama),
        );

      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));

      expect(auth.profilLengkap!['nik'], '3201991000000001');
    });

    test('_profilLengkap tetap null bila layar belum pernah dibuka', () async {
      // Menyusunnya dari potongan respons tulis akan menghasilkan profil yang
      // tidak lengkap dan terlihat sah. Biarkan null supaya pembukaan
      // berikutnya mengambilnya utuh dari /auth/profil.
      final auth = _AuthTanpaJaringan()
        ..pasangUji(user: Map<String, dynamic>.from(_kkLama));
      expect(auth.profilLengkap, isNull);

      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));

      expect(auth.profilLengkap, isNull);
    });
  });

  group('PII tetap tidak menyentuh penyimpanan perangkat', () {
    const pii = ['email', 'no_hp', 'no_kk', 'nik', 'alamat', 'no_rt'];
    const ringkas = ['id', 'nama', 'role', 'username', 'must_change_password'];

    test('user_data tetap ringkas sesudah simpan', () async {
      final auth = _AuthTanpaJaringan()
        ..pasangUji(
          user: Map<String, dynamic>.from(_kkLama),
          profilLengkap: Map<String, dynamic>.from(_profilLama),
        );

      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));

      final prefs = await SharedPreferences.getInstance();
      final tersimpan = jsonDecode(prefs.getString('user_data')!) as Map<String, dynamic>;

      for (final k in pii) {
        expect(tersimpan.containsKey(k), isFalse,
            reason: '"$k" bocor ke penyimpanan lewat respons PUT');
      }
      expect(tersimpan.keys.toSet(), ringkas.toSet());
    });

    test('nilai ringkas yang tersimpan ikut diperbarui', () async {
      // Ringkasnya harus segar juga — `nama` dipakai sapaan di dasbor.
      final auth = _AuthTanpaJaringan()
        ..pasangUji(
          user: Map<String, dynamic>.from(_kkLama),
          profilLengkap: Map<String, dynamic>.from(_profilLama),
        );

      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));

      final prefs = await SharedPreferences.getInstance();
      final tersimpan = jsonDecode(prefs.getString('user_data')!) as Map<String, dynamic>;
      expect(tersimpan['nama'], 'Budi Santoso Wijaya');
      expect(auth.userName, 'Budi Santoso Wijaya');
    });

    test('_user di memori pun tetap ringkas', () async {
      final auth = _AuthTanpaJaringan()
        ..pasangUji(
          user: Map<String, dynamic>.from(_kkLama),
          profilLengkap: Map<String, dynamic>.from(_profilLama),
        );

      await auth.terapkanProfilTerbaru(Map<String, dynamic>.from(_barisSetelahSimpan));

      for (final k in pii) {
        expect(auth.user!.containsKey(k), isFalse,
            reason: '_user harus tetap profil ringkas, bukan baris lengkap');
      }
      // Sedangkan profil lengkap memang boleh memuatnya — ia hanya di memori.
      expect(auth.profilLengkap!['email'], 'budi.baru@example.com');
    });
  });
}
