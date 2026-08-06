import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Satu-satunya tempat warna snackbar ditentukan.
///
/// Sebelum ini setiap layar memilih sendiri, dan hasilnya **tiga merah dan lima
/// hijau** beredar bersamaan: `Colors.red` (#F44336) berdampingan dengan
/// `0xFFEF4444` dan `AppTheme.dangerColor`; `Colors.green` (#4CAF50) dengan
/// `0xFF10B981`, `0xFF059669`, dan `0xFF1B7A6A` — yang terakhir itu teal, warna
/// merek aplikasi, bukan hijau berhasil sama sekali.
///
/// Empat belas pemanggil bahkan tidak menyetel warna apa pun, jadi pesannya
/// keluar dengan abu-abu bawaan Material. Dua di antaranya berdampingan dalam
/// alur yang sama di Bantuan Sosial: "Pilih warga terlebih dahulu" (gagal) dan
/// "Data ditambahkan" (berhasil) tampil dengan latar yang persis sama, sehingga
/// warna berhenti menyampaikan apa pun.
///
/// Aturannya sekarang satu kalimat: **merah berarti tidak jadi, hijau berarti
/// jadi.** Tidak ada warna ketiga — biru dan oranye yang sempat dipakai di
/// Agenda hanya menghias dialognya, bukan memberi tahu hasilnya.
///
/// Warnanya diambil dari [AppTheme] dan bukan ditulis ulang di sini, supaya
/// mengubah palet aplikasi tidak meninggalkan snackbar dengan warna lama.
class Pesan {
  const Pesan._();

  static const Color latarGagal = AppTheme.dangerColor;
  static const Color latarSukses = AppTheme.successColor;

  /// Teks selalu putih. Kedua latar itu gelap, dan warna teks bawaan snackbar
  /// mengikuti `onInverseSurface` yang ikut berubah di mode gelap — pada latar
  /// merah hasilnya bisa nyaris tidak terbaca.
  static const Color _teks = Colors.white;

  static SnackBar _bangun(
    String teks, {
    required bool sukses,
    Duration? durasi,
    SnackBarBehavior? perilaku,
  }) => SnackBar(
    content: Text(teks, style: const TextStyle(color: _teks)),
    backgroundColor: sukses ? latarSukses : latarGagal,
    duration: durasi ?? const Duration(seconds: 4),
    behavior: perilaku,
  );
}

/// Tampilkan pesan hasil operasi.
///
/// Pakai ini alih-alih `ScaffoldMessenger.of(context).showSnackBar(SnackBar(…))`
/// langsung, agar warnanya tidak bercabang lagi.
///
/// [durasi] dan [perilaku] sengaja dibiarkan bisa diatur: beberapa layar memang
/// menahan pesannya lebih lama karena isinya panjang (hasil impor Excel), dan
/// beberapa memakai snackbar melayang. Yang disatukan di sini hanya warnanya.
void tampilkanPesan(
  BuildContext context,
  String teks, {
  required bool sukses,
  Duration? durasi,
  SnackBarBehavior? perilaku,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    Pesan._bangun(teks, sukses: sukses, durasi: durasi, perilaku: perilaku),
  );
}

void pesanSukses(BuildContext context, String teks) =>
    tampilkanPesan(context, teks, sukses: true);

void pesanGagal(BuildContext context, String teks) =>
    tampilkanPesan(context, teks, sukses: false);

/// Versi untuk pemanggil yang sudah menyimpan messenger-nya sebelum `await`.
///
/// Itu pola yang benar dan harus tetap bisa dipakai: mengambil
/// `ScaffoldMessenger.of(context)` **setelah** operasi async berisiko memakai
/// context yang widget-nya sudah dilepas.
void tampilkanPesanDi(
  ScaffoldMessengerState messenger,
  String teks, {
  required bool sukses,
}) {
  messenger.showSnackBar(Pesan._bangun(teks, sukses: sukses));
}
