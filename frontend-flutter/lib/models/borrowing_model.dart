int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _toDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// Satu catatan peminjaman barang.
///
/// [status] adalah nilai yang tersimpan (`Dipinjam` / `Dikembalikan`),
/// sedangkan [statusEfektif] dihitung backend dan bisa bernilai `Terlambat`.
/// Keterlambatan sengaja tidak disimpan: peminjaman menjadi terlambat karena
/// berlalunya waktu, bukan karena suatu kejadian, jadi menghitungnya saat
/// dibaca selalu benar tanpa perlu proses penjadwal.
class BorrowingModel {
  final int id;
  final int inventoryId;
  final String namaBarang;
  final String? kategori;
  final String? userId;
  final String namaPeminjam;
  final String? dicatatOlehNama;
  final int jumlah;
  final DateTime? tanggalPinjam;
  final DateTime? tanggalRencanaKembali;
  final DateTime? tanggalKembali;
  final String status;
  final String statusEfektif;
  final int hariTerlambat;
  final String? keterangan;

  const BorrowingModel({
    required this.id,
    required this.inventoryId,
    required this.namaBarang,
    this.kategori,
    this.userId,
    required this.namaPeminjam,
    this.dicatatOlehNama,
    required this.jumlah,
    this.tanggalPinjam,
    this.tanggalRencanaKembali,
    this.tanggalKembali,
    required this.status,
    required this.statusEfektif,
    this.hariTerlambat = 0,
    this.keterangan,
  });

  factory BorrowingModel.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString() ?? 'Dipinjam';
    return BorrowingModel(
      id: _toInt(json['id']),
      inventoryId: _toInt(json['inventory_id']),
      namaBarang: json['nama_barang']?.toString() ?? '-',
      kategori: json['kategori']?.toString(),
      userId: json['user_id']?.toString(),
      namaPeminjam: json['nama_peminjam']?.toString() ?? '-',
      dicatatOlehNama: json['dicatat_oleh_nama']?.toString(),
      jumlah: _toInt(json['jumlah']),
      tanggalPinjam: _toDate(json['tanggal_pinjam']),
      tanggalRencanaKembali: _toDate(json['tanggal_rencana_kembali']),
      tanggalKembali: _toDate(json['tanggal_kembali']),
      status: status,
      statusEfektif: json['status_efektif']?.toString() ?? status,
      hariTerlambat: _toInt(json['hari_terlambat']),
      keterangan: json['keterangan']?.toString(),
    );
  }

  bool get isDipinjam => status == 'Dipinjam';
  bool get isDikembalikan => status == 'Dikembalikan';
  bool get isTerlambat => statusEfektif == 'Terlambat';

  /// Riwayat pengembalian adalah jejak yang perlu dijaga; yang boleh
  /// dibatalkan hanya peminjaman yang belum selesai (salah catat).
  bool get bisaDibatalkan => !isDikembalikan;
}

/// Ringkasan untuk kartu di layar Peminjaman.
class BorrowingStats {
  final int total;
  final int dipinjam;
  final int dikembalikan;
  final int terlambat;

  const BorrowingStats({
    this.total = 0,
    this.dipinjam = 0,
    this.dikembalikan = 0,
    this.terlambat = 0,
  });

  factory BorrowingStats.fromJson(Map<String, dynamic> json) {
    return BorrowingStats(
      total: _toInt(json['total']),
      dipinjam: _toInt(json['dipinjam']),
      dikembalikan: _toInt(json['dikembalikan']),
      terlambat: _toInt(json['terlambat']),
    );
  }
}
