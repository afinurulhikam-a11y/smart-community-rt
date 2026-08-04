class EmergencyModel {
  final String id;
  final String userId;
  final String message;
  final double? latitude;
  final double? longitude;
  final String status;
  final String? namaWarga;
  final String? alamat;
  final String? noHp;
  final String? dismissedByNama;
  final DateTime? dismissedAt;
  final DateTime createdAt;

  EmergencyModel({
    required this.id,
    required this.userId,
    required this.message,
    this.latitude,
    this.longitude,
    required this.status,
    this.namaWarga,
    this.alamat,
    this.noHp,
    this.dismissedByNama,
    this.dismissedAt,
    required this.createdAt,
  });

  factory EmergencyModel.fromJson(Map<String, dynamic> json) {
    return EmergencyModel(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      message: json['message'] as String,
      latitude: json['latitude'] != null ? double.parse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.parse(json['longitude'].toString()) : null,
      status: json['status'] as String,
      namaWarga: json['nama_warga'] as String?,
      alamat: json['alamat'] as String?,
      noHp: json['no_hp'] as String?,
      dismissedByNama: json['dismissed_by_nama'] as String?,
      dismissedAt: json['dismissed_at'] != null
          ? DateTime.parse(json['dismissed_at'] as String).toLocal()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  bool get isActive => status == 'active';
}
