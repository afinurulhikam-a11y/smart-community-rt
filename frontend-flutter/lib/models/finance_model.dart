/// Postgres mengirim NUMERIC sebagai string, jadi konversinya dibuat toleran
/// di satu tempat — pola yang sama dipakai di bill_model.dart.
double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// Satu baris buku kas.
///
/// PENTING: kelas ini dipakai bersama oleh layar BOP (`bop_provider.dart`
/// sengaja memakai ulang model ini), Laporan Keuangan, dashboard admin,
/// dashboard pengurus, dan layar warga. Field baru harus punya nilai bawaan
/// agar endpoint BOP yang tidak mengirimnya tetap bekerja.
class FinanceModel {
  final String id;
  final String tipe;
  final String kategori;
  final double jumlah;
  final String deskripsi;
  final DateTime tanggal;
  final String? createdByNama;
  final DateTime createdAt;

  // --- Tambahan modul Kas RT (opsional, aman untuk BOP) ---

  final int? kategoriId;

  /// 'manual' bila dicatat bendahara, 'iuran' bila otomatis dari pembayaran.
  final String sumber;

  /// Id baris bill_payments asal, hanya terisi untuk transaksi dari iuran.
  final String? refId;

  /// Saldo kumulatif sampai baris ini, dihitung backend lewat window function.
  final double saldoBerjalan;

  FinanceModel({
    required this.id,
    required this.tipe,
    required this.kategori,
    required this.jumlah,
    required this.deskripsi,
    required this.tanggal,
    this.createdByNama,
    required this.createdAt,
    this.kategoriId,
    this.sumber = 'manual',
    this.refId,
    this.saldoBerjalan = 0,
  });

  factory FinanceModel.fromJson(Map<String, dynamic> json) {
    return FinanceModel(
      id: json['id'].toString(),
      tipe: json['tipe']?.toString() ?? 'pemasukan',
      kategori: json['kategori']?.toString() ?? 'Umum',
      jumlah: _toDouble(json['jumlah']),
      deskripsi: json['deskripsi']?.toString() ?? '-',
      tanggal: DateTime.tryParse('${json['tanggal']}') ?? DateTime.now(),
      createdByNama: json['created_by_nama']?.toString(),
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
      kategoriId: json['kategori_id'] == null ? null : int.tryParse('${json['kategori_id']}'),
      sumber: json['sumber']?.toString() ?? 'manual',
      refId: json['ref_id']?.toString(),
      saldoBerjalan: _toDouble(json['saldo_berjalan']),
    );
  }

  bool get isPemasukan => tipe == 'pemasukan';
  String get tipeLabel => isPemasukan ? 'Pemasukan' : 'Pengeluaran';

  /// Transaksi hasil pembayaran iuran tidak boleh disunting dari buku kas —
  /// koreksinya lewat data Iuran Warga agar saldo tetap cocok.
  bool get dariIuran => sumber == 'iuran';
  bool get bolehDiubah => !dariIuran;
}

/// Ringkasan buku kas.
///
/// Field lama (`totalPemasukan`, `totalPengeluaran`, `saldo`) dipertahankan
/// apa adanya karena dipakai layar BOP dan lima layar lain. Field baru punya
/// bawaan 0 sehingga respons BOP yang tidak memuatnya tetap aman.
class FinanceSummary {
  final double totalPemasukan;
  final double totalPengeluaran;
  final double saldo;

  // --- Tambahan modul Kas RT ---

  /// Periode yang dipakai kartu "bulan ini", format YYYY-MM.
  final String periode;

  /// Hanya bulan berjalan — untuk dua kartu pertama.
  final double pemasukanBulan;
  final double pengeluaranBulan;

  /// Selalu sepanjang masa, tidak pernah ikut tersaring periode — kartu ketiga.
  final double saldoTotal;

  FinanceSummary({
    required this.totalPemasukan,
    required this.totalPengeluaran,
    required this.saldo,
    this.periode = '',
    this.pemasukanBulan = 0,
    this.pengeluaranBulan = 0,
    this.saldoTotal = 0,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      totalPemasukan: _toDouble(json['total_pemasukan']),
      totalPengeluaran: _toDouble(json['total_pengeluaran']),
      saldo: _toDouble(json['saldo']),
      periode: json['periode']?.toString() ?? '',
      pemasukanBulan: _toDouble(json['pemasukan_bulan']),
      pengeluaranBulan: _toDouble(json['pengeluaran_bulan']),
      saldoTotal: _toDouble(json['saldo_total']),
    );
  }
}
