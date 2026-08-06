import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan mode terang/gelap pengguna.
///
/// Sebelumnya keadaan ini hanya `bool _isDarkMode` di dalam `MainDashboard`,
/// dengan dua akibat: pilihannya hilang setiap aplikasi ditutup, dan hanya
/// bagian layar yang kebetulan berada di bawah pembungkus `Theme()` yang ikut
/// menggelap — AppBar, laci, navigasi bawah, dan **setiap dialog** tidak pernah
/// ikut, karena semuanya membaca tema dari akar.
///
/// Dipindahkan ke provider supaya satu sumber dibaca oleh `MaterialApp`
/// sekaligus, dan supaya nilainya bisa disimpan.
class TemaProvider extends ChangeNotifier {
  static const String _kunci = 'mode_gelap';

  bool _gelap;

  TemaProvider({bool gelapAwal = false}) : _gelap = gelapAwal;

  bool get gelap => _gelap;

  ThemeMode get mode => _gelap ? ThemeMode.dark : ThemeMode.light;

  /// Membaca pilihan tersimpan **sebelum** `runApp`.
  ///
  /// Dibaca lebih dulu, bukan dimuat di latar, supaya bingkai pertama sudah
  /// memakai tema yang benar — memuatnya belakangan membuat aplikasi berkedip
  /// dari terang ke gelap tepat di depan mata pengguna.
  ///
  /// Ini penyimpanan lokal, bukan jaringan; aturan "tidak ada panggilan
  /// jaringan di jalur mulai" tidak dilanggar. Bila gagal dibaca karena alasan
  /// apa pun, nilainya jatuh ke kecerahan sistem — bukan melempar galat, karena
  /// preferensi tampilan tidak pernah cukup penting untuk menggagalkan startup.
  static Future<bool> bacaTersimpan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tersimpan = prefs.getBool(_kunci);
      if (tersimpan != null) return tersimpan;
    } catch (_) {
      // Sengaja diabaikan; lihat penjelasan di atas.
    }
    // Bila belum ada preferensi tersimpan, default aplikasi adalah mode terang (whitemode).
    return false;
  }

  Future<void> ganti() => setGelap(!_gelap);

  Future<void> setGelap(bool nilai) async {
    if (_gelap == nilai) return;
    _gelap = nilai;
    notifyListeners();

    // Penyimpanan dilakukan SETELAH notifyListeners: tampilan tidak perlu
    // menunggu disk, dan kegagalan menulis tidak boleh membatalkan perubahan
    // yang sudah terlihat di layar.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kunci, nilai);
    } catch (_) {
      // Diabaikan: pilihannya tetap berlaku untuk sesi ini.
    }
  }
}
