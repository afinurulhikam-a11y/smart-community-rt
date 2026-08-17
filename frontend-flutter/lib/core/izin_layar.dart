import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'theme/app_theme.dart';
import 'theme/warna_konteks.dart';

/// Getter izin untuk sebuah layar bermodul.
///
/// Blok empat baris ini disalin apa adanya ke dua belas layar:
///
/// ```dart
/// bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
/// bool get _bolehUbah   => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
/// bool get _bolehHapus  => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);
/// ```
///
/// Duplikasi seperti ini bukan sekadar bertele-tele. Ia berarti perubahan
/// aturan izin harus diingat di dua belas tempat, dan yang terlewat tidak akan
/// menimbulkan galat apa pun — hanya satu layar yang perilakunya berbeda dari
/// sebelas lainnya, dan itu justru bentuk cacat yang paling lama tidak
/// ketahuan.
///
/// Pemakaian:
/// ```dart
/// class _DataBarangScreenState extends State<DataBarangScreen> with IzinLayar {
///   @override
///   String get kodeIzin => 'inventaris.barang';
///   ...
///   if (bolehTambah) TombolTambah(...)
/// }
/// ```
mixin IzinLayar<T extends StatefulWidget> on State<T> {
  /// Kode modul di tabel izin, mis. `keuangan.kas`.
  String get kodeIzin;

  PermissionProvider get _izin => context.watch<PermissionProvider>();

  bool get bolehLihat => _izin.bolehLihat(kodeIzin);
  bool get bolehTambah => _izin.bolehTambah(kodeIzin);
  bool get bolehUbah => _izin.bolehUbah(kodeIzin);
  bool get bolehHapus => _izin.bolehHapus(kodeIzin);

  /// Boleh membuka, tidak boleh mengubah. Inilah yang memunculkan banner
  /// "Anda hanya bisa melihat".
  bool get hanyaLihat => _izin.hanyaLihat(kodeIzin);
}

/// Dialog konfirmasi untuk tindakan yang tidak bisa dibatalkan.
///
/// Ditulis tangan di delapan layar sebelumnya, dengan kalimat, warna tombol,
/// dan urutan tombol yang tidak seragam. Pada dialog penghapusan, ketidak-
/// seragaman itu berbahaya: orang belajar posisi tombol, bukan membacanya —
/// dan tombol merah yang kadang di kiri kadang di kanan berarti seseorang
/// suatu saat akan menekan Hapus ketika bermaksud Batal.
///
/// Mengembalikan `true` hanya bila pengguna benar-benar menekan tombol
/// tindakan. Menutup dialog dengan tap di luar mengembalikan null → dianggap
/// batal, yang memang perilaku yang aman.
Future<bool> konfirmasiHapus(
  BuildContext context, {
  required String judul,
  required String pesan,
  String labelAksi = 'Hapus',
}) async {
  final hasil = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.latarKartu,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusL)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
          const SizedBox(width: AppTheme.spasiS),
          Expanded(
            child: Text(
              judul,
              style: TextStyle(
                color: ctx.teksUtama,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        pesan,
        style: TextStyle(color: ctx.teksKedua),
      ),
      actions: [
        // Batal SELALU di kiri dan dinamis warna konteks (hitam/gelap di mode terang, putih/terang di mode gelap)
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(
            foregroundColor: ctx.teksKedua,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(labelAksi, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return hasil == true;
}
