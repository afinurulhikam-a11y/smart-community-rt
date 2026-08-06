import 'dart:math';

/// Pembuat sandi awal untuk akun warga — cerminan `src/utils/sandi.js`.
///
/// Alfabetnya sengaja sama persis dengan yang di backend: tanpa 0/O dan 1/l/I.
/// Sandi ini dibacakan lewat telepon, ditulis tangan di kertas, dan diketik
/// ulang di ponsel — situasi ketika huruf yang mirip berubah menjadi keluhan
/// "tidak bisa masuk" yang sebenarnya hanya salah baca.
const String _huruf = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

final Random _acak = Random.secure();

/// Sandi acak sepanjang [panjang] karakter.
///
/// `Random.secure()`, bukan `Random()`: yang terakhir dapat ditebak dari
/// benihnya. Untuk sandi, itu perbedaan antara acak dan tampak acak.
String sandiAcak([int panjang = 10]) =>
    List.generate(panjang, (_) => _huruf[_acak.nextInt(_huruf.length)]).join();
