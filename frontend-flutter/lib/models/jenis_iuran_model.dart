/// Master jenis iuran yang bisa dikelola admin (Kebersihan, Keamanan, dan
/// seterusnya) beserta nominal bawaannya.
class JenisIuranModel {
  final int id;
  final String namaIuran;
  final double nominalDefault;
  final String periode;
  final bool isAktif;
  final String? keterangan;

  /// Berapa tagihan yang sudah memakai jenis ini. Dipakai layar untuk
  /// menonaktifkan tombol hapus sebelum request ditolak backend.
  final int jumlahTagihan;

  const JenisIuranModel({
    required this.id,
    required this.namaIuran,
    required this.nominalDefault,
    required this.periode,
    required this.isAktif,
    this.keterangan,
    this.jumlahTagihan = 0,
  });

  factory JenisIuranModel.fromJson(Map<String, dynamic> json) {
    return JenisIuranModel(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      namaIuran: json['nama_iuran']?.toString() ?? '-',
      nominalDefault: json['nominal_default'] is num
          ? (json['nominal_default'] as num).toDouble()
          : double.tryParse('${json['nominal_default']}') ?? 0,
      periode: json['periode']?.toString() ?? 'bulanan',
      isAktif: json['is_aktif'] != false,
      keterangan: json['keterangan']?.toString(),
      jumlahTagihan: json['jumlah_tagihan'] is int
          ? json['jumlah_tagihan'] as int
          : int.tryParse('${json['jumlah_tagihan']}') ?? 0,
    );
  }

  bool get bisaDihapus => jumlahTagihan == 0;

  String get periodeLabel {
    switch (periode) {
      case 'tahunan':
        return 'Tahunan';
      case 'sekali':
        return 'Sekali Bayar';
      default:
        return 'Bulanan';
    }
  }
}
