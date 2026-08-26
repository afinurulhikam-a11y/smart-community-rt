class UserModel {
  final String? id;
  final String nama;
  final String email;
  final String? username;
  final String? noHp;
  final String? noKk;
  final String? alamat;
  final String? noRt;
  final String role;
  final bool isActive;
  final String? nik;
  final DateTime? createdAt;

  UserModel({
    this.id,
    required this.nama,
    required this.email,
    this.username,
    this.noHp,
    this.noKk,
    this.alamat,
    this.noRt,
    required this.role,
    this.isActive = true,
    this.nik,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString(),
      nama: json['nama']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString(),
      noHp: json['no_hp']?.toString(),
      noKk: json['no_kk']?.toString(),
      alamat: json['alamat']?.toString(),
      noRt: json['no_rt']?.toString(),
      role: json['role']?.toString() ?? 'warga',
      isActive: json['is_active'] == true || json['is_active'] == 1 || json['is_active']?.toString() == 'true',
      nik: json['nik']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nama': nama,
      'email': email,
      if (username != null) 'username': username,
      if (noHp != null) 'no_hp': noHp,
      if (noKk != null) 'no_kk': noKk,
      if (alamat != null) 'alamat': alamat,
      if (noRt != null) 'no_rt': noRt,
      'role': role,
      'is_active': isActive,
      if (nik != null) 'nik': nik,
    };
  }

  String get roleLabel {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'ketua_rw':
        return 'Ketua RW';
      case 'ketua_rt':
        return 'Ketua RT';
      case 'sekretaris':
        return 'Sekretaris';
      case 'bendahara':
        return 'Bendahara';
      case 'warga':
      default:
        return 'Warga';
    }
  }
}
