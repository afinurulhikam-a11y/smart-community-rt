double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Ringkasan Dana BOP.
///
/// Sengaja terpisah dari `FinanceSummary` walaupun sebagian field-nya sama:
/// BOP punya pagu yang tidak ada padanannya di Kas RT, dan `FinanceSummary`
/// dipakai bersama enam layar lain sehingga menambah field khas BOP ke sana
/// hanya akan memperbesar keterikatan yang sudah ada.
///
/// `saldo` dipertahankan karena `main_dashboard.dart` membacanya.
class BopSummary {
  final int tahun;
  final String periode;

  /// Pagu dana tahun berjalan.
  final double alokasi;

  /// Realisasi belanja tahun berjalan.
  final double terpakai;

  /// alokasi − terpakai. Jatah belanja yang belum terpakai.
  final double sisaPagu;

  final double pemasukanBulan;
  final double pengeluaranBulan;

  final double totalPemasukan;
  final double totalPengeluaran;

  /// pemasukan − pengeluaran sepanjang masa. Uang yang benar-benar ada,
  /// dan bisa berbeda dari [sisaPagu] ketika dana belum cair seluruhnya.
  final double saldo;

  const BopSummary({
    this.tahun = 0,
    this.periode = '',
    this.alokasi = 0,
    this.terpakai = 0,
    this.sisaPagu = 0,
    this.pemasukanBulan = 0,
    this.pengeluaranBulan = 0,
    this.totalPemasukan = 0,
    this.totalPengeluaran = 0,
    this.saldo = 0,
  });

  factory BopSummary.fromJson(Map<String, dynamic> json) {
    return BopSummary(
      tahun: _toInt(json['tahun']),
      periode: json['periode']?.toString() ?? '',
      alokasi: _toDouble(json['alokasi']),
      terpakai: _toDouble(json['terpakai']),
      sisaPagu: _toDouble(json['sisa_pagu']),
      pemasukanBulan: _toDouble(json['pemasukan_bulan']),
      pengeluaranBulan: _toDouble(json['pengeluaran_bulan']),
      totalPemasukan: _toDouble(json['total_pemasukan']),
      totalPengeluaran: _toDouble(json['total_pengeluaran']),
      saldo: _toDouble(json['saldo']),
    );
  }

  /// True bila belanja tahun ini sudah melampaui pagu.
  bool get melampauiPagu => alokasi > 0 && terpakai > alokasi;

  /// Porsi pagu yang sudah terpakai, dibatasi 0–1 untuk indikator progres.
  double get porsiTerpakai => alokasi <= 0 ? 0 : (terpakai / alokasi).clamp(0.0, 1.0);
}

/// Satu baris pagu dana BOP untuk satu tahun + termin.
class AlokasiBopModel {
  final int id;
  final int tahun;
  final String termin;
  final double nominal;
  final String? sumberDana;
  final String? keterangan;

  /// Realisasi belanja pada TAHUN baris ini — bukan per termin, karena
  /// transaksi BOP hanya punya tanggal tanpa penanda termin.
  final double realisasiTahun;
  final double totalPaguTahun;

  const AlokasiBopModel({
    required this.id,
    required this.tahun,
    required this.termin,
    required this.nominal,
    this.sumberDana,
    this.keterangan,
    this.realisasiTahun = 0,
    this.totalPaguTahun = 0,
  });

  factory AlokasiBopModel.fromJson(Map<String, dynamic> json) {
    return AlokasiBopModel(
      id: _toInt(json['id']),
      tahun: _toInt(json['tahun']),
      termin: json['termin']?.toString() ?? 'Tahunan',
      nominal: _toDouble(json['nominal']),
      sumberDana: json['sumber_dana']?.toString(),
      keterangan: json['keterangan']?.toString(),
      realisasiTahun: _toDouble(json['realisasi_tahun']),
      totalPaguTahun: _toDouble(json['total_pagu_tahun']),
    );
  }

  /// Sisa pagu tahun ini secara keseluruhan, bukan sisa termin ini saja.
  double get sisaTahun => totalPaguTahun - realisasiTahun;

  /// Alokasi hanya boleh dihapus selama tahunnya belum punya belanja.
  bool get bisaDihapus => realisasiTahun == 0;
}
