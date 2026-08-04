import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../widgets/responsive_layout.dart';

/// Aturan ukuran yang dipakai bersama seluruh layar.
///
/// Sebelum berkas ini ada, setiap layar menulis angkanya sendiri —
/// `EdgeInsets.all(24)`, `width: 180`, `width: 460` — tanpa memeriksa lebar
/// layar sama sekali. Di ponsel 360px angka-angka itu memakan ruang yang tidak
/// dipunyai, dan hasilnya tampilan terasa sempit serta berserakan.
///
/// Ambang ukurannya sengaja MENUMPANG pada [ResponsiveLayout] yang sudah
/// dipakai sidebar dan grid, bukan ambang baru. Dua sumber ambang yang berbeda
/// akan membuat sidebar dan isinya berganti bentuk pada lebar yang tidak sama.

/// Jarak tepi konten halaman.
///
/// Di ponsel padding 24 di kiri dan kanan memakan 48px — 13% dari layar 360px —
/// dan itu terasa langsung karena membuat tabel serta kartu ikut terjepit.
double paddingKonten(BuildContext c) {
  if (ResponsiveLayout.isMobile(c)) return 12;
  if (ResponsiveLayout.isTablet(c)) return 16;
  return 24;
}

/// Jarak tepi di dalam kartu (kotak putih berisi filter, tabel, ringkasan).
///
/// Terpisah dari [paddingKonten] karena keduanya bertumpuk: padding halaman
/// 12 ditambah padding kartu 20 sudah memakan 64px dari layar 360px.
double paddingKartu(BuildContext c) => ResponsiveLayout.isMobile(c) ? 12 : 20;

/// Lebar isi dialog yang tidak pernah melebihi layar.
///
/// `SizedBox(width: 460)` di dalam `AlertDialog` tidak menyusut sendiri saat
/// layarnya lebih sempit; isinya meluber dan kolom isian ikut terjepit. Nilai
/// di sini selalu lebih kecil dari lebar layar, sekaligus tidak melar
/// berlebihan di desktop.
///
/// [maksimal] adalah lebar yang diinginkan pada layar lebar — biasanya angka
/// yang dulu dipatok di layar tersebut.
double lebarDialog(BuildContext c, {double maksimal = 480}) {
  // AlertDialog sendiri sudah menyisakan margin di kiri-kanan; 48 di bawah ini
  // adalah ruang di dalamnya supaya isi tidak menempel ke dinding dialog.
  final tersedia = MediaQuery.of(c).size.width - 48;
  return math.max(0, math.min(tersedia, maksimal));
}

/// Lebar satu kotak filter atau kotak pencarian di dalam `Wrap`.
///
/// Mengembalikan `double.infinity` di ponsel supaya kotaknya mengisi penuh satu
/// baris dan bertumpuk rapi. Dengan lebar tetap 180, tiap filter tetap turun ke
/// barisnya sendiri di layar sempit tetapi menyisakan ruang kosong di
/// kanannya — itulah yang membuat tampilan terlihat berserakan.
///
/// HANYA aman di dalam `Wrap` atau `Column`, yang memberi batas lebar. Di dalam
/// `Row` lebar tak hingga justru melempar galat; di sana pakai `Expanded`.
double lebarKolomFilter(BuildContext c, {double maksimal = 180}) {
  if (ResponsiveLayout.isMobile(c)) return double.infinity;
  return maksimal;
}

/// Apakah tabel sebaiknya diganti kartu bertumpuk.
///
/// Dipakai [TabelResponsif] dan layar yang memilih bentuknya sendiri, supaya
/// keputusannya seragam di seluruh aplikasi.
bool pakaiKartu(BuildContext c) => ResponsiveLayout.isMobile(c);
