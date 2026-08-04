/// Master kategori buku kas. `tipe` mengikuti CHECK constraint di database:
/// 'IN' hanya untuk pemasukan, 'OUT' hanya untuk pengeluaran.
class KategoriKasModel {
  final int id;
  final String namaKategori;
  final String tipe;
  final bool isAktif;
  final String? keterangan;

  /// Berapa transaksi yang sudah memakai kategori ini. Dipakai layar untuk
  /// menonaktifkan tombol hapus sebelum request ditolak backend.
  final int jumlahTransaksi;

  const KategoriKasModel({
    required this.id,
    required this.namaKategori,
    required this.tipe,
    required this.isAktif,
    this.keterangan,
    this.jumlahTransaksi = 0,
  });

  factory KategoriKasModel.fromJson(Map<String, dynamic> json) {
    return KategoriKasModel(
      id: int.tryParse('${json['id']}') ?? 0,
      namaKategori: json['nama_kategori']?.toString() ?? '-',
      tipe: json['tipe']?.toString() ?? 'IN',
      isAktif: json['is_aktif'] != false,
      keterangan: json['keterangan']?.toString(),
      jumlahTransaksi: int.tryParse('${json['jumlah_transaksi']}') ?? 0,
    );
  }

  bool get isPemasukan => tipe == 'IN';
  bool get bisaDihapus => jumlahTransaksi == 0;
  String get tipeLabel => isPemasukan ? 'Pemasukan' : 'Pengeluaran';
}
