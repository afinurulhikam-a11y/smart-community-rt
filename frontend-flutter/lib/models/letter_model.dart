class LetterModel {
  final String id;
  final String userId;
  final String jenisSurat;
  final String keperluan;
  final String status;
  final String? namaPemohon;
  final String? alamat;
  final String? noKk;
  final String? approvedBy;
  final String? approvedByNama;
  final String? responseNote;
  final DateTime tanggalPengajuan;
  final DateTime? tanggalRespon;

  LetterModel({
    required this.id,
    required this.userId,
    required this.jenisSurat,
    required this.keperluan,
    required this.status,
    this.namaPemohon,
    this.alamat,
    this.noKk,
    this.approvedBy,
    this.approvedByNama,
    this.responseNote,
    required this.tanggalPengajuan,
    this.tanggalRespon,
  });

  factory LetterModel.fromJson(Map<String, dynamic> json) {
    return LetterModel(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      jenisSurat: json['jenis_surat'] as String,
      keperluan: json['keperluan'] as String,
      status: json['status'] as String,
      namaPemohon: json['nama_pemohon'] as String?,
      alamat: json['alamat'] as String?,
      noKk: json['no_kk'] as String?,
      approvedBy: json['approved_by']?.toString(),
      approvedByNama: json['approved_by_nama'] as String?,
      responseNote: json['response_note'] as String?,
      tanggalPengajuan: DateTime.parse((json['created_at'] ?? json['tanggal_pengajuan']) as String).toLocal(),
      tanggalRespon: json['tanggal_respon'] != null
          ? DateTime.parse(json['tanggal_respon'] as String).toLocal()
          : null,
    );
  }

  /// Sudah diteruskan pengurus RT, menunggu pengesahan Ketua RW.
  ///
  /// Tahap ini lahir bersama alur surat bertingkat: di Indonesia surat
  /// pengantar mengalir RT → RW → Kelurahan, dan sebelumnya sistem hanya
  /// memodelkan satu tahap.
  bool get isMenungguRw => status.toLowerCase() == 'menunggu_rw';

  /// Belum selesai — termasuk yang sedang menunggu Ketua RW.
  ///
  /// `menunggu_rw` WAJIB ikut di sini. Tanpa itu surat yang sudah diteruskan
  /// tidak terhitung "pending" maupun "selesai", sehingga ia lenyap dari
  /// setiap penyaring dan setiap kartu hitungan — tersimpan rapi dan tidak
  /// terlihat oleh siapa pun, persis kelas cacat yang paling sulit disadari.
  bool get isPending {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'diproses' || s == 'diajukan'
        || s == 'menunggu' || s == 'menunggu_rw';
  }

  bool get isDisetujui {
    final s = status.toLowerCase();
    return s == 'disetujui' || s == 'approved';
  }

  bool get isDitolak {
    final s = status.toLowerCase();
    return s == 'ditolak' || s == 'rejected';
  }

  String get statusLabel {
    if (isDisetujui) return 'Disetujui';
    if (isDitolak) return 'Ditolak';
    if (isMenungguRw) return 'Menunggu RW';
    if (status.toLowerCase() == 'diproses') return 'Diproses';
    return 'Diajukan';
  }
}
