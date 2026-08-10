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

  /// `tetap` (nominal pasti) atau `meteran` (dihitung dari selisih meteran).
  ///
  /// Bawaannya `tetap` supaya jenis iuran lama yang belum punya kolom ini —
  /// dan backend versi lama yang belum mengirimkannya — tetap berperilaku
  /// persis seperti sebelumnya.
  final String tipeHitung;

  final double tarifPerM3;
  final double abondement;

  /// Biaya sampah ikut di dalam tagihan air, bukan iuran terpisah. Warga
  /// membayarnya sekali, dan hanya bila rumahnya berlangganan.
  final double biayaSampah;

  const JenisIuranModel({
    required this.id,
    required this.namaIuran,
    required this.nominalDefault,
    required this.periode,
    required this.isAktif,
    this.keterangan,
    this.jumlahTagihan = 0,
    this.tipeHitung = 'tetap',
    this.tarifPerM3 = 0,
    this.abondement = 0,
    this.biayaSampah = 0,
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
      tipeHitung: json['tipe_hitung']?.toString() ?? 'tetap',
      tarifPerM3: _uang(json['tarif_per_m3']),
      abondement: _uang(json['abondement']),
      biayaSampah: _uang(json['biaya_sampah']),
    );
  }

  /// Postgres mengirim NUMERIC sebagai string: `"3000"`, bukan `3000`.
  static double _uang(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  bool get bisaDihapus => jumlahTagihan == 0;

  /// Ditagih berdasarkan meteran air, bukan nominal pasti.
  bool get pakaiMeteran => tipeHitung == 'meteran';

  /// Bagian yang ditagih walau meterannya belum dibaca sama sekali.
  double get bagianTetap => abondement + biayaSampah;

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
