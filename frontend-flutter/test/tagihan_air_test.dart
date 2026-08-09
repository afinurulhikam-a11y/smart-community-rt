import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/models/bill_model.dart';

/// Tagihan seperti yang dikirim backend, dengan kolom meteran apa adanya.
BillModel tagihan({
  int? lalu,
  int? kini,
  int? tarif = 3000,
  int? abondement = 25000,
  int? sampah = 30000,
  num nominal = 0,
}) => BillModel.fromJson({
  'id': 'x',
  'keluarga_id': 1,
  'no_kk': '3201990000000001',
  'kepala_keluarga': 'Budi Santoso',
  'jenis_tagihan': 'Iuran Air Sumur Bor',
  'bulan': '2026-06',
  'nominal': nominal,
  'status': 'unpaid',
  'created_at': '2026-06-01T00:00:00Z',
  'meteran_lalu': lalu,
  'meteran_sekarang': kini,
  'tarif_per_m3': tarif,
  'abondement': abondement,
  'biaya_sampah': sampah,
});

void main() {
  group('tagihan air', () {
    test('angka dari sistem lama RT tereproduksi', () {
      // Keempat baris ini disalin dari tagihan yang sedang berjalan di RT.
      // Uji ini yang membuktikan rumusnya benar — bukan pendapat siapa pun
      // tentang bagaimana seharusnya menghitung.
      const kasus = [
        [230, 234, 4, 12000, 67000],
        [227, 230, 3, 9000, 64000],
        [225, 227, 2, 6000, 61000],
        [221, 225, 4, 12000, 67000],
      ];

      for (final k in kasus) {
        final b = tagihan(lalu: k[0], kini: k[1]);
        expect(b.terpakai, k[2], reason: '${k[0]} → ${k[1]}');
        expect(b.biayaAir, k[3].toDouble(), reason: '${k[0]} → ${k[1]}');
        expect(
          b.biayaAir + b.abondement! + b.biayaSampah!,
          k[4].toDouble(),
          reason: 'total untuk ${k[0]} → ${k[1]}',
        );
      }
    });

    test('rumah tanpa pemakaian tetap membayar bagian tetapnya', () {
      final b = tagihan(lalu: 234, kini: 234);
      expect(b.terpakai, 0);
      expect(b.biayaAir, 0);
      expect(b.sudahDibaca, isTrue, reason: '0 m³ berbeda maknanya dari belum dibaca');
      expect(b.biayaAir + b.abondement! + b.biayaSampah!, 55000);
    });

    test('meteran belum dicatat dibedakan dari pemakaian nol', () {
      final b = tagihan(lalu: 234, kini: null);
      expect(b.sudahDibaca, isFalse);
      expect(b.terpakai, isNull, reason: 'null, bukan 0 — angkanya memang belum diketahui');
      expect(b.biayaAir, 0);
    });

    test('meteran mundur tidak menghasilkan tagihan negatif', () {
      // Database menolaknya lewat bills_meteran_maju, tetapi baris lama bisa
      // saja sudah masuk sebelum penjaga itu dipasang. Layar tidak boleh
      // menampilkan pemakaian minus.
      final b = tagihan(lalu: 234, kini: 230);
      expect(b.terpakai, 0);
      expect(b.biayaAir, greaterThanOrEqualTo(0));
    });

    test('pakaiMeteran ditentukan tarif tersalin, bukan nama iurannya', () {
      // Jenis iuran bisa diganti namanya kapan saja lewat layar master.
      // Menebak dari nama akan patah begitu itu terjadi.
      expect(tagihan(lalu: 1, kini: 2).pakaiMeteran, isTrue);
      expect(tagihan(lalu: null, kini: null, tarif: null).pakaiMeteran, isFalse);
    });

    test('tagihan bernominal tetap tidak terpengaruh sama sekali', () {
      final b = tagihan(
        lalu: null, kini: null, tarif: null,
        abondement: null, sampah: null, nominal: 50000,
      );
      expect(b.pakaiMeteran, isFalse);
      expect(b.terpakai, isNull);
      expect(b.nominal, 50000);
      expect(b.meteranLalu, isNull);
    });

    test('NUMERIC dari Postgres yang berupa string tetap terbaca', () {
      // Postgres mengirim NUMERIC sebagai string; INTEGER sebagai angka.
      // Keduanya harus diterima, karena bentuknya berbeda antar kolom.
      final b = BillModel.fromJson({
        'id': 'x',
        'keluarga_id': '1',
        'no_kk': '1',
        'kepala_keluarga': 'A',
        'jenis_tagihan': 'Iuran Air Sumur Bor',
        'bulan': '2026-06',
        'nominal': '67000',
        'status': 'unpaid',
        'created_at': '2026-06-01T00:00:00Z',
        'meteran_lalu': '230',
        'meteran_sekarang': '234',
        'tarif_per_m3': '3000',
        'abondement': '25000',
        'biaya_sampah': '30000',
      });
      expect(b.terpakai, 4);
      expect(b.nominal, 67000);
      expect(b.biayaAir, 12000);
    });
  });
}
