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

DateTime? _toDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// Satu jenis barang inventaris RT.
///
/// [jumlahTotal] adalah barang yang DIMILIKI dan tidak pernah berubah saat
/// dipinjam. [tersedia] dihitung backend sebagai total dikurangi yang sedang
/// dipinjam — dulu keduanya tercampur menjadi satu kolom, sehingga RT
/// kehilangan catatan berapa barang yang sebenarnya dimiliki.
class InventoryModel {
  final int id;
  final String namaBarang;
  final String? kategori;
  final int jumlahTotal;
  final int sedangDipinjam;
  final int tersedia;
  final String kondisi;
  final String? lokasi;
  final double nilaiBarang;
  final double nilaiTotal;
  final DateTime? tanggalPerolehan;
  final String? keterangan;

  const InventoryModel({
    required this.id,
    required this.namaBarang,
    this.kategori,
    required this.jumlahTotal,
    required this.sedangDipinjam,
    required this.tersedia,
    required this.kondisi,
    this.lokasi,
    this.nilaiBarang = 0,
    this.nilaiTotal = 0,
    this.tanggalPerolehan,
    this.keterangan,
  });

  factory InventoryModel.fromJson(Map<String, dynamic> json) {
    return InventoryModel(
      id: _toInt(json['id']),
      namaBarang: json['nama_barang']?.toString() ?? '-',
      kategori: json['kategori']?.toString(),
      jumlahTotal: _toInt(json['jumlah_total'] ?? json['jumlah']),
      sedangDipinjam: _toInt(json['sedang_dipinjam']),
      tersedia: _toInt(json['tersedia'] ?? json['jumlah']),
      kondisi: json['kondisi']?.toString() ?? 'Baik',
      lokasi: json['lokasi']?.toString(),
      nilaiBarang: _toDouble(json['nilai_barang']),
      nilaiTotal: _toDouble(json['nilai_total']),
      tanggalPerolehan: _toDate(json['tanggal_perolehan']),
      keterangan: json['keterangan']?.toString(),
    );
  }

  bool get bisaDipinjam => tersedia > 0;

  /// Barang yang sedang dipinjam tidak boleh dihapus — backend juga menolak,
  /// tetapi menonaktifkan tombolnya lebih jujur daripada memunculkan error.
  bool get bisaDihapus => sedangDipinjam == 0;

  bool get kondisiBaik => kondisi == 'Baik';
}

/// Ringkasan untuk kartu di layar Data Barang.
class InventoryStats {
  final int totalAset;
  final int totalUnit;
  final int kondisiBaik;
  final int perluPerbaikan;
  final double totalNilai;
  final int unitDipinjam;
  final int unitTersedia;

  const InventoryStats({
    this.totalAset = 0,
    this.totalUnit = 0,
    this.kondisiBaik = 0,
    this.perluPerbaikan = 0,
    this.totalNilai = 0,
    this.unitDipinjam = 0,
    this.unitTersedia = 0,
  });

  factory InventoryStats.fromJson(Map<String, dynamic> json) {
    return InventoryStats(
      totalAset: _toInt(json['total_aset']),
      totalUnit: _toInt(json['total_unit']),
      kondisiBaik: _toInt(json['kondisi_baik']),
      perluPerbaikan: _toInt(json['perlu_perbaikan']),
      totalNilai: _toDouble(json['total_nilai']),
      unitDipinjam: _toInt(json['unit_dipinjam']),
      unitTersedia: _toInt(json['unit_tersedia']),
    );
  }
}
