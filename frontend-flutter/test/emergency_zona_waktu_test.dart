import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:smart_community/models/emergency_model.dart';

/// Regresi: sisi klien tidak boleh menambahkan offset KEDUA.
///
/// Backend kini mengirim instant sejati (`2026-08-16T09:45:00.000Z` untuk
/// kejadian pukul 16:45 WIB) karena kolom `timestamp without time zone`
/// ditafsirkan di perbatasan SQL memakai `::timestamptz`. Tugas klien tinggal
/// satu: `DateTime.parse(...).toLocal()`, sekali saja.
///
/// Yang dijaga berkas ini adalah "sekali saja" itu. Menambahkan `.toUtc()`,
/// `Duration(hours: 7)`, atau menempelkan `Z` pada nilai yang sudah benar akan
/// menggeser tampilan menjadi 23:45 — persis bug yang dilaporkan dari produksi.
void main() {
  // Instant yang benar untuk 16:45 WIB dan 17:20 WIB.
  const kawatDibuat = '2026-08-16T09:45:00.000Z';
  const kawatDitutup = '2026-08-16T10:20:00.000Z';

  final instantDibuat = DateTime.utc(2026, 8, 16, 9, 45);
  final instantDitutup = DateTime.utc(2026, 8, 16, 10, 20);

  Map<String, dynamic> contohJson() => {
        'id': 'e1',
        'user_id': 'u1',
        'message': 'Uji zona waktu',
        'status': 'dismissed',
        'nama_warga': 'Warga Uji',
        'alamat': 'Jl. Uji No. 1',
        'no_hp': '08123456789',
        'dismissed_by_nama': 'Ketua RT',
        'created_at': kawatDibuat,
        'dismissed_at': kawatDitutup,
      };

  group('EmergencyModel — zona waktu', () {
    test('createdAt menunjuk instant yang sama persis dengan yang dikirim server', () {
      final m = EmergencyModel.fromJson(contohJson());

      // Bebas zona: apa pun zona mesin penguji, instant-nya harus identik.
      // Inilah yang gagal bila ada yang menambahkan offset kedua.
      expect(m.createdAt.isAtSameMomentAs(instantDibuat), isTrue,
          reason: 'createdAt bergeser dari instant yang dikirim server '
              '(${m.createdAt.toUtc().toIso8601String()} ≠ ${instantDibuat.toIso8601String()})');
    });

    test('dismissedAt menunjuk instant yang sama persis dengan yang dikirim server', () {
      final m = EmergencyModel.fromJson(contohJson());

      expect(m.dismissedAt, isNotNull);
      expect(m.dismissedAt!.isAtSameMomentAs(instantDitutup), isTrue,
          reason: 'dismissedAt bergeser dari instant yang dikirim server '
              '(${m.dismissedAt!.toUtc().toIso8601String()} ≠ ${instantDitutup.toIso8601String()})');
    });

    test('dismissedAt tetap null saat kejadian masih aktif', () {
      final json = contohJson()
        ..['status'] = 'active'
        ..['dismissed_at'] = null;

      final m = EmergencyModel.fromJson(json);
      expect(m.dismissedAt, isNull);
      expect(m.isActive, isTrue);
    });

    test('createdAt dalam waktu lokal, bukan UTC mentah', () {
      final m = EmergencyModel.fromJson(contohJson());

      // `.toLocal()` wajib dipanggil model. Tanpa itu DateFormat akan
      // memformat jam UTC (09:45) alih-alih jam dinding perangkat.
      expect(m.createdAt.isUtc, isFalse,
          reason: 'model harus memanggil .toLocal(); nilai UTC mentah akan '
              'tampil 09:45 di layar, bukan 16:45');
    });
  });

  group('Tampilan Status Darurat pada perangkat WIB', () {
    // Rangkaian ini hanya berarti bila mesin penguji benar-benar berada di
    // UTC+7. Di zona lain "16:45" memang bukan jawaban yang benar, dan
    // memaksanya lulus akan mengunci uji ini pada satu mesin saja.
    final offset = DateTime.now().timeZoneOffset;
    final diWib = offset == const Duration(hours: 7);

    test('kejadian 16:45 WIB tampil 16:45 — bukan 23:45, bukan 09:45', () {
      if (!diWib) {
        markTestSkipped('Mesin penguji bukan UTC+7 (offset $offset) — '
            'pemeriksaan jam dinding WIB dilewati.');
        return;
      }

      final m = EmergencyModel.fromJson(contohJson());
      // Format yang SAMA dengan status_darurat_screen.dart.
      final teks = DateFormat('dd MMM yyyy, HH:mm').format(m.createdAt);

      expect(teks, endsWith('16:45'),
          reason: 'jam dinding salah: "$teks"');
      expect(teks, isNot(endsWith('23:45')),
          reason: 'gejala bug produksi: waktu maju 7 jam');
      expect(teks, isNot(endsWith('09:45')),
          reason: 'gejala kebalikannya: waktu mundur 7 jam (UTC mentah)');
    });

    test('penutupan 17:20 WIB tampil 17:20', () {
      if (!diWib) {
        markTestSkipped('Mesin penguji bukan UTC+7 (offset $offset).');
        return;
      }

      final m = EmergencyModel.fromJson(contohJson());
      final teks = DateFormat('dd MMM yyyy, HH:mm').format(m.dismissedAt!);

      expect(teks, endsWith('17:20'), reason: 'jam dinding salah: "$teks"');
      expect(teks, isNot(endsWith('00:20')),
          reason: 'dismissed_at maju 7 jam dan berpindah hari');
    });
  });
}
