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

  String get statusLabel {
    switch (status) {
      case 'diajukan':
        return 'Diajukan';
      case 'diproses':
        return 'Diproses';
      case 'disetujui':
        return 'Disetujui';
      case 'ditolak':
        return 'Ditolak';
      default:
        return status;
    }
  }
}
