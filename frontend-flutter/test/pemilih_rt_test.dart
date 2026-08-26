import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/providers/rt_provider.dart';

import 'bantuan_uji.dart';

/// Pemilih RT harus muncul di KEDUA tata letak.
///
/// ===================================================================
/// Kenapa uji ini ada
/// ===================================================================
///
/// `MainDashboard` memberi `Scaffold` sebuah `appBar` hanya ketika bukan
/// desktop. Pemilih RT semula hanya ditanam di AppBar itu, jadi administrator
/// yang membuka aplikasi di Chrome atau Windows — cara aplikasi ini paling
/// sering dibuka — tidak punya satu pun cara mengganti RT yang dilihatnya.
///
/// Seluruh uji tata letak yang ada tidak bisa melihatnya, dan alasannya layak
/// diingat: tanpa backend, `RtProvider` selalu kosong, `bolehMemilih` selalu
/// false, dan pemilihnya memang tidak seharusnya dirender. Jadi ujinya lolos
/// pada layar yang pemilihnya hilang. `isiUntukUji` ada khusus untuk menutup
/// celah itu — datanya harus ada lebih dulu sebelum ketiadaannya berarti apa
/// pun.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const duaRt = [
    RtModel(id: 'a', kode: '001', nama: 'RT 001', rwKode: '005'),
    RtModel(id: 'b', kode: '002', nama: 'RT 002 Kenanga', rwKode: '005'),
  ];

  Future<void> pasang(WidgetTester tester, Size ukuran, List<RtModel> daftar) async {
    tester.view.physicalSize = ukuran;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(bungkusDasbor());
    // Provider diisi SETELAH pohon terpasang, lalu dipompa sekali: itulah
    // urutan yang sama dengan kenyataan — daftar RT datang dari jaringan,
    // beberapa saat sesudah frame pertama.
    final ctx = tester.element(find.byType(Scaffold).first);
    ctx.read<RtProvider>().isiUntukUji(daftar);
    await tester.pump();
  }

  testWidgets('muncul di ponsel (AppBar)', (tester) async {
    await pasang(tester, const Size(412, 915), duaRt);
    expect(find.byIcon(Icons.apartment_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muncul di layar lebar (header), bukan hanya di AppBar', (tester) async {
    await pasang(tester, const Size(1440, 900), duaRt);
    // Pada lebar ini `Scaffold.appBar` bernilai null, jadi apa pun yang
    // ditemukan di sini hanya bisa berasal dari `_buildHeaderBar`.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.apartment_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tidak muncul bila hanya ada satu RT', (tester) async {
    // Pengurus RT dan warga hanya menerima RT-nya sendiri dari server. Pilihan
    // yang isinya cuma satu bukan pilihan, dan ruang di bilah atas ponsel
    // terlalu sempit untuk kontrol yang tidak pernah berguna.
    await pasang(tester, const Size(1440, 900), [duaRt.first]);
    expect(find.byIcon(Icons.apartment_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
