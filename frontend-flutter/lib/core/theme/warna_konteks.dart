import 'package:flutter/material.dart';

/// Warna permukaan dan teks yang mengikuti tema aktif.
///
/// Ini sasaran migrasi dari warna yang ditulis mati. Layar dulu memakai
/// `Color(0xFF64748B)` dan sejenisnya secara langsung, sehingga tetap terang
/// walaupun temanya gelap — 1.108 literal `Color(0x…)` tersebar di 25 layar.
///
/// **Warna merek dan semantik tidak ada di sini dan memang tidak seharusnya.**
/// Teal primary, merah bahaya, hijau sukses, biru info, dan oranye peringatan
/// sudah benar di kedua mode; yang perlu berganti hanyalah permukaan, teks,
/// dan garis. Memisahkan keduanya membuat jelas mana yang boleh diganti
/// mekanis dan mana yang harus dibiarkan.
extension WarnaTema on BuildContext {
  ThemeData get _tema => Theme.of(this);

  bool get gelap => _tema.brightness == Brightness.dark;

  /// Latar belakang halaman — di belakang kartu.
  Color get latarHalaman => _tema.scaffoldBackgroundColor;

  /// Permukaan kartu, dialog, dan panel.
  ///
  /// Inilah pengganti `Colors.white` **ketika ia dipakai sebagai latar**.
  /// `Colors.white` yang dipakai sebagai teks atau ikon di atas warna merek
  /// harus tetap putih — lihat catatan di CLAUDE.md.
  Color get latarKartu => _tema.cardColor;

  /// Teks judul dan isi utama.
  Color get teksUtama => _tema.colorScheme.onSurface;

  /// Teks pendukung: label, keterangan, satuan.
  Color get teksKedua => _tema.colorScheme.onSurfaceVariant;

  /// Teks paling redup: placeholder, keterangan sekunder.
  Color get teksTersier => _tema.colorScheme.onSurfaceVariant.withValues(alpha: 0.72);

  /// Garis pemisah dan tepi kartu.
  Color get garis => _tema.dividerColor;

  /// Latar isian lembut — kotak isian, chip netral, baris tabel bergantian.
  Color get latarLembut =>
      gelap ? _tema.colorScheme.surfaceContainerHighest : const Color(0xFFF8FAFC);

  /// Warna tombol/ikon penutup (Batal, Tutup, Kembali, dsb.).
  /// Putih (#FFFFFF) pada mode gelap, Hitam (#000000) pada mode terang.
  Color get warnaTombolTutup =>
      gelap ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
}
