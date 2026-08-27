import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/core/peran.dart';

/// Daftar peran klien harus mengenal setiap peran yang ada di backend.
///
/// ===================================================================
/// Kenapa uji ini ada
/// ===================================================================
///
/// Peran `ketua_rw` ditambahkan di backend beserta seluruh baris izinnya.
/// Klien menyimpan daftar perannya sendiri dan tidak ikut diperbarui, dan
/// yang paling merusak ada di `AuthGate`: peran di luar daftar dikembalikan
/// ke layar Login.
///
/// Akibatnya login **berhasil** — server menjawab 200, token tersimpan — lalu
/// layarnya kembali ke Login tanpa satu pun pesan. Dari sisi pemakai: menekan
/// Masuk tidak terjadi apa-apa. Tidak ada galat untuk dibaca, tidak ada yang
/// bisa ditebak.
///
/// Tidak ada uji yang bisa melihatnya, karena setiap berkas benar menurut
/// kodenya sendiri. Yang salah adalah dua daftar yang tidak lagi sama.
///
/// ===================================================================
/// Kenapa membaca berkas backend, bukan menyalin daftarnya ke sini
/// ===================================================================
///
/// Menuliskan daftar peran di berkas uji ini hanya memindahkan masalahnya:
/// ia menjadi salinan KETIGA yang juga bisa tertinggal. Yang dibutuhkan
/// adalah pemeriksaan yang gagal ketika kedua sisi berbeda, jadi ujinya
/// membaca `permissions.js` — berkas yang oleh backend sendiri disebut satu-
/// satunya sumber kebenaran untuk peran dan izin.
///
/// Peran warisan yang hanya dikenal klien (`pengurus_rt`) tidak dituntut ada
/// di backend: ia sengaja dipertahankan supaya token lama tidak terlempar.
void main() {
  test('setiap peran di backend dikenal klien', () {
    final berkas = File('../backend-node/src/config/permissions.js');
    if (!berkas.existsSync()) {
      markTestSkipped('permissions.js tidak ditemukan — dijalankan di luar repo lengkap');
      return;
    }

    final isi = berkas.readAsStringSync();
    final cocok = RegExp(r"const ROLES\s*=\s*\[([^\]]*)\]").firstMatch(isi);
    expect(cocok, isNotNull,
        reason: 'Blok `const ROLES = [...]` tidak ditemukan di permissions.js. '
            'Bila bentuknya berubah, sesuaikan uji ini — jangan menghapusnya, '
            'karena tanpa uji ini peran baru berikutnya akan membuat login '
            'gagal tanpa pesan.');

    final peranBackend = RegExp("'([a-z_]+)'")
        .allMatches(cocok!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(peranBackend, isNotEmpty);

    final tertinggal = peranBackend.difference(Peran.semua);
    expect(
      tertinggal,
      isEmpty,
      reason: 'Peran ${tertinggal.join(", ")} ada di backend tetapi tidak di '
          '`Peran.semua`. Login sebagai peran itu akan BERHASIL lalu kembali '
          'ke layar Login tanpa pesan apa pun.',
    );
  });

  test('setiap peran yang dikenal punya nama tampil', () {
    // Peran yang tidak punya nama akan tampil sebagai "Pengguna" di menu akun —
    // benar menurut kodenya, dan tidak berguna bagi yang membacanya.
    for (final peran in Peran.semua) {
      expect(Peran.label(peran), isNot('Pengguna'),
          reason: 'Peran "$peran" belum punya nama tampil di Peran.label().');
    }
    expect(Peran.label('peran_yang_tidak_ada'), 'Pengguna');
  });

  test('peran lintas RT adalah bagian dari peran yang dikenal', () {
    expect(Peran.semua.containsAll(Peran.lintasRt), isTrue);
    expect(Peran.semua.containsAll(Peran.pengurus), isTrue);
    // Warga tidak boleh masuk daftar pengurus: `isPengurus` dipakai untuk
    // memutuskan apakah sebuah permintaan layak ditembakkan sama sekali.
    expect(Peran.pengurus.contains(Peran.warga), isFalse);
  });
}
