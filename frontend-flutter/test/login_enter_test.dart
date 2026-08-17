import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/services/auth_service.dart';
import 'package:smart_community/screens/login_screen.dart';

/// AuthService yang menghitung panggilan `login` dan bisa ditahan.
///
/// Ditahan dengan sengaja: penjaga kirim-ganda hanya berarti selama permintaan
/// pertama masih berjalan. Kalau fake-nya selesai seketika, pemicuan kedua
/// terjadi setelah yang pertama beres — dan itu bukan kirim ganda, itu login
/// dua kali yang wajar.
class AuthPalsu extends AuthService {
  AuthPalsu({this.tahan = true});

  final bool tahan;
  int jumlahPanggilan = 0;
  final List<List<String>> argumen = [];
  final _selesai = Completer<bool>();

  @override
  Future<bool> login(String email, String password) async {
    jumlahPanggilan++;
    argumen.add([email, password]);
    if (!tahan) return false;
    return _selesai.future;
  }

  void lepaskan({bool berhasil = false}) {
    if (!_selesai.isCompleted) _selesai.complete(berhasil);
  }

  @override
  String? get errorMessage => 'Login gagal';
}

Future<void> bukaLogin(WidgetTester tester, AuthPalsu auth, {Size? ukuran}) async {
  await tester.binding.setSurfaceSize(ukuran ?? const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  await tester.pump();
}

Finder get kolomUsername => find.widgetWithText(TextFormField, 'Masukkan NIK atau Username');
Finder get kolomPassword => find.widgetWithText(TextFormField, 'Masukkan password');

Future<void> isiKredensial(WidgetTester tester) async {
  await tester.enterText(kolomUsername, '3201991000000012');
  await tester.enterText(kolomPassword, 'rahasia123');
  await tester.pump();
}

void main() {
  testWidgets('Enter di kolom Username mengirim form', (tester) async {
    final auth = AuthPalsu();
    await bukaLogin(tester, auth);
    await isiKredensial(tester);

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(auth.jumlahPanggilan, 1);
    auth.lepaskan();
    await tester.pumpAndSettle();
  });

  testWidgets('Enter di kolom Password mengirim form', (tester) async {
    final auth = AuthPalsu();
    await bukaLogin(tester, auth);
    await isiKredensial(tester);

    // Fokuskan kolom password lebih dulu supaya aksinya berasal dari sana.
    await tester.tap(kolomPassword);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(auth.jumlahPanggilan, 1);
    auth.lepaskan();
    await tester.pumpAndSettle();
  });

  testWidgets('Enter memicu aksi yang sama persis dengan tombol Masuk', (tester) async {
    // Dua jalur, satu hasil: argumen yang dikirim harus identik, bukan sekadar
    // sama-sama memanggil login.
    final lewatEnter = AuthPalsu();
    await bukaLogin(tester, lewatEnter);
    await isiKredensial(tester);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    lewatEnter.lepaskan();
    await tester.pumpAndSettle();

    final lewatTombol = AuthPalsu();
    await bukaLogin(tester, lewatTombol);
    await isiKredensial(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Masuk'));
    await tester.pump();
    lewatTombol.lepaskan();
    await tester.pumpAndSettle();

    expect(lewatEnter.argumen, lewatTombol.argumen);
    expect(lewatEnter.argumen.single, ['3201991000000012', 'rahasia123']);
  });

  testWidgets('dua pemicuan dalam satu frame hanya mengirim sekali', (tester) async {
    // Inilah kasus yang tidak tertangkap oleh `auth.isLoading` saja.
    // `login()` memang menyetel isLoading sebelum await pertamanya, tetapi
    // tombol membacanya lewat context.watch dan notifyListeners baru membangun
    // ulang pada frame BERIKUTNYA. Tanpa `pump()` di antara kedua pemicuan,
    // keduanya melihat pohon widget yang sama dan tombol yang sama-sama aktif.
    //
    // Dipicu lewat dua ketukan, bukan dua Enter: `testTextInput.receiveAction`
    // hanya terkirim SEKALI per frame di harness uji — diukur, tiga panggilan
    // berturut-turut menghasilkan satu pemicuan bahkan ketika penjaganya
    // dilepas. Jadi Enter tidak bisa membuktikan apa pun di sini. Keduanya
    // bermuara ke `_handleLogin` yang sama, dan di situlah penjaganya berada.
    final auth = AuthPalsu();
    await bukaLogin(tester, auth);
    await isiKredensial(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      auth.jumlahPanggilan,
      1,
      reason: 'dua pemicuan dalam satu frame menghasilkan '
          '${auth.jumlahPanggilan} permintaan login',
    );

    auth.lepaskan();
    await tester.pumpAndSettle();
  });

  testWidgets('Enter lalu klik tombol juga hanya mengirim sekali', (tester) async {
    final auth = AuthPalsu();
    await bukaLogin(tester, auth);
    await isiKredensial(tester);

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    // Setelah rebuild tombolnya sudah nonaktif; ketukan ini tidak boleh lolos.
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();

    expect(auth.jumlahPanggilan, 1);
    auth.lepaskan();
    await tester.pumpAndSettle();
  });

  testWidgets('Enter dengan kolom kosong tidak mengirim apa pun', (tester) async {
    // Validasi form tetap berjalan lebih dulu — logika autentikasinya tidak
    // berubah, Enter hanya memakai pintu yang sama.
    final auth = AuthPalsu();
    await bukaLogin(tester, auth);

    // Kolomnya HARUS difokuskan dulu. Tanpa itu `receiveAction` tidak terkirim
    // ke widget mana pun, `onFieldSubmitted` tidak pernah berjalan, dan uji ini
    // akan lolos hanya karena Enter-nya tidak pernah sampai — bukan karena
    // validasinya menahan. Ketahuan waktu pesan validasinya tidak muncul.
    await tester.tap(kolomUsername);
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(auth.jumlahPanggilan, 0);
    expect(find.text('Username wajib diisi'), findsOneWidget);
    expect(find.text('Password wajib diisi'), findsOneWidget);
  });

  testWidgets('setelah login gagal, form bisa dikirim lagi', (tester) async {
    // Penjaganya harus dibuka kembali; kalau tidak, satu kali salah sandi
    // mengunci layar login sampai aplikasi dijalankan ulang.
    final auth = AuthPalsu();
    await bukaLogin(tester, auth);
    await isiKredensial(tester);

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    auth.lepaskan(berhasil: false);
    await tester.pumpAndSettle();

    expect(auth.jumlahPanggilan, 1);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Masuk'));
    await tester.pump();
    expect(auth.jumlahPanggilan, 2, reason: 'layar terkunci setelah percobaan pertama gagal');
  });

  testWidgets('berlaku juga pada tata letak ponsel', (tester) async {
    final auth = AuthPalsu();
    await bukaLogin(tester, auth, ukuran: const Size(390, 844));
    await isiKredensial(tester);

    // Enter membuktikan pengirimannya sampai, dua ketukan membuktikan
    // penjaganya menahan — keduanya diperlukan pada tata letak ini juga.
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(auth.jumlahPanggilan, 1);

    auth.lepaskan();
    await tester.pumpAndSettle();

    final auth2 = AuthPalsu();
    await bukaLogin(tester, auth2, ukuran: const Size(390, 844));
    await isiKredensial(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(auth2.jumlahPanggilan, 1);

    auth2.lepaskan();
    await tester.pumpAndSettle();
  });
}
