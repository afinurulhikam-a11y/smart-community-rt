/// Postgres mengirim NUMERIC sebagai string, jadi konversinya dibuat toleran
/// di satu tempat — pola yang sama dipakai di demographic_model.dart.
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

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// Satu tagihan iuran. Sejak migrasi v6 tagihan melekat pada **kartu keluarga**,
/// bukan perorangan — `userId` sekarang berarti siapa yang membayar.
class BillModel {
  final String id;
  final int keluargaId;
  final String noKk;
  final String kepalaKeluarga;
  final String? alamat;

  /// Nomor HP kepala keluarga, untuk penagihan lewat WhatsApp.
  final String? noHp;

  /// False bila nama kepala keluarga masih memakai nama anggota pertama sebagai
  /// penanda sementara — KK itu belum punya anggota berstatus Kepala Keluarga.
  final bool kepalaTerkonfirmasi;
  final int? jenisIuranId;
  final String namaIuran;
  final String bulan;
  final double nominal;
  final String status;
  final String? keterangan;
  final DateTime? jatuhTempo;
  final DateTime createdAt;

  // Terisi hanya bila tagihan sudah dibayar.
  final String? userId;
  final DateTime? paidAt;
  final String? metodeBayar;
  final String? invoiceNumber;

  BillModel({
    required this.id,
    required this.keluargaId,
    required this.noKk,
    required this.kepalaKeluarga,
    this.alamat,
    this.noHp,
    this.kepalaTerkonfirmasi = true,
    this.jenisIuranId,
    required this.namaIuran,
    required this.bulan,
    required this.nominal,
    required this.status,
    this.keterangan,
    this.jatuhTempo,
    required this.createdAt,
    this.userId,
    this.paidAt,
    this.metodeBayar,
    this.invoiceNumber,
  });

  factory BillModel.fromJson(Map<String, dynamic> json) {
    return BillModel(
      id: json['id'].toString(),
      keluargaId: _toInt(json['keluarga_id']),
      noKk: json['no_kk']?.toString() ?? '-',
      // Import Excel menulis '-' bila baris pertama sebuah KK bukan kepala
      // keluarga, jadi jangan tampilkan tanda hubung telanjang di tabel.
      kepalaKeluarga: (json['kepala_keluarga']?.toString().trim().isNotEmpty ?? false)
          ? json['kepala_keluarga'].toString()
          : '(Belum diisi)',
      alamat: json['alamat']?.toString(),
      noHp: json['no_hp']?.toString(),
      kepalaTerkonfirmasi: json['kepala_terkonfirmasi'] != false,
      jenisIuranId: json['jenis_iuran_id'] == null ? null : _toInt(json['jenis_iuran_id']),
      namaIuran: json['nama_iuran']?.toString() ?? json['jenis_tagihan']?.toString() ?? '-',
      bulan: json['bulan']?.toString() ?? '-',
      nominal: _toDouble(json['nominal']),
      status: json['status']?.toString() ?? 'unpaid',
      keterangan: json['keterangan']?.toString(),
      jatuhTempo: _toDate(json['jatuh_tempo']),
      createdAt: _toDate(json['created_at']) ?? DateTime.now(),
      userId: json['user_id']?.toString(),
      paidAt: _toDate(json['paid_at']),
      metodeBayar: json['metode_bayar']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
    );
  }

  bool get isLunas => status == 'lunas';
  String get statusLabel => isLunas ? 'Lunas' : 'Belum Bayar';

  /// Tagihan lewat jatuh tempo dan belum dibayar — dipakai untuk penanda merah
  /// dan untuk menyusun pesan penagihan WhatsApp.
  bool get isTerlambat => !isLunas && jatuhTempo != null && jatuhTempo!.isBefore(DateTime.now());
}

/// Ringkasan untuk kartu statistik di layar Iuran Warga. Selalu mengikuti
/// filter yang sedang aktif, sama seperti daftar tagihannya.
class BillStats {
  final int totalTagihan;
  final int jumlahLunas;
  final int jumlahTunggakan;
  final double nominalTerkumpul;
  final double nominalTertunggak;
  final double nominalTotal;
  final int jumlahKk;
  final double persentaseLunas;

  const BillStats({
    required this.totalTagihan,
    required this.jumlahLunas,
    required this.jumlahTunggakan,
    required this.nominalTerkumpul,
    required this.nominalTertunggak,
    required this.nominalTotal,
    required this.jumlahKk,
    required this.persentaseLunas,
  });

  factory BillStats.kosong() => const BillStats(
    totalTagihan: 0,
    jumlahLunas: 0,
    jumlahTunggakan: 0,
    nominalTerkumpul: 0,
    nominalTertunggak: 0,
    nominalTotal: 0,
    jumlahKk: 0,
    persentaseLunas: 0,
  );

  factory BillStats.fromJson(Map<String, dynamic> json) {
    return BillStats(
      totalTagihan: _toInt(json['total_tagihan']),
      jumlahLunas: _toInt(json['jumlah_lunas']),
      jumlahTunggakan: _toInt(json['jumlah_tunggakan']),
      nominalTerkumpul: _toDouble(json['nominal_terkumpul']),
      nominalTertunggak: _toDouble(json['nominal_tertunggak']),
      nominalTotal: _toDouble(json['nominal_total']),
      jumlahKk: _toInt(json['jumlah_kk']),
      persentaseLunas: _toDouble(json['persentase_lunas']),
    );
  }
}
