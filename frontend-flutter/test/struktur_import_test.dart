import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga yang tidak bisa digantikan oleh `flutter analyze`.
///
/// Analyzer menangkap nama folder yang salah — `../../provider/` (kurang huruf
/// s) langsung dilaporkan sebagai *Target of URI doesn't exist*. Tetapi ia
/// **buta total terhadap kedalaman yang salah**: diuji langsung, mengubah satu
/// import menjadi `../../../../` dan bahkan `../../../../../../` tetap
/// menghasilkan "No issues found!".
///
/// Sebabnya normalisasi URI. Resolusi jalur relatif membuang segmen `..` yang
/// melewati akar paket, jadi berapa pun tingkat kelebihannya akan mendarat di
/// tempat yang sama. Kodenya benar secara kebetulan, bukan secara sengaja.
///
/// Karena itulah 69 baris seperti ini sempat menumpuk di 13 berkas tanpa satu
/// pun peringatan: tidak ada perkakas di rantai build yang bisa melihatnya.
void main() {
  test('tidak ada import relatif yang menunjuk ke luar lib/', () {
    final pelanggar = <String>[];

    for (final berkas in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final jalur = berkas.path.replaceAll(r'\', '/');
      if (!jalur.endsWith('.dart')) continue;

      // Kedalaman berkas di bawah lib/ = jumlah folder di antaranya.
      // lib/main.dart              -> 0, tidak boleh ada '../' sama sekali
      // lib/core/pesan.dart        -> 1, paling banyak '../'
      // lib/screens/admin/x.dart   -> 2, paling banyak '../../'
      final relatif = jalur.substring('lib/'.length);
      final kedalaman = relatif.split('/').length - 1;

      final baris = berkas.readAsLinesSync();
      for (var i = 0; i < baris.length; i++) {
        final cocok = RegExp(r"^import '((?:\.\./)+)").firstMatch(baris[i]);
        if (cocok == null) continue;

        final naik = '../'.allMatches(cocok.group(1)!).length;
        if (naik > kedalaman) {
          pelanggar.add(
            '$jalur:${i + 1} naik $naik tingkat dari kedalaman $kedalaman '
            '— ${baris[i].trim()}',
          );
        }
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason:
          'Import ini menunjuk ke luar lib/, dan hanya bekerja karena resolusi\n'
          'URI membuang segmen ".." yang melewati akar paket. Pembacanya\n'
          'diberi tahu ada folder di tempat yang tidak ada, dan flutter analyze\n'
          'tidak akan pernah melaporkannya.\n'
          'Ditemukan:\n  ${pelanggar.join("\n  ")}',
    );
  });
}
