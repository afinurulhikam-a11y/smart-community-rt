/// Izin satu role terhadap satu menu.
class Izin {
  final bool lihat;
  final bool tambah;
  final bool ubah;
  final bool hapus;

  const Izin({this.lihat = false, this.tambah = false, this.ubah = false, this.hapus = false});

  factory Izin.fromJson(Map<String, dynamic> j) => Izin(
    lihat: j['can_view'] == true,
    tambah: j['can_create'] == true,
    ubah: j['can_update'] == true,
    hapus: j['can_delete'] == true,
  );

  factory Izin.penuh() => const Izin(lihat: true, tambah: true, ubah: true, hapus: true);

  Map<String, dynamic> toJson() => {
    'can_view': lihat,
    'can_create': tambah,
    'can_update': ubah,
    'can_delete': hapus,
  };

  Izin salin({bool? lihat, bool? tambah, bool? ubah, bool? hapus}) => Izin(
    lihat: lihat ?? this.lihat,
    tambah: tambah ?? this.tambah,
    ubah: ubah ?? this.ubah,
    hapus: hapus ?? this.hapus,
  );

  /// Boleh membuka menunya tetapi tidak boleh mengubah apa pun di dalamnya.
  /// Inilah yang memunculkan lencana "View" di sidebar.
  bool get hanyaLihat => lihat && !tambah && !ubah && !hapus;

  bool get adaAkses => lihat || tambah || ubah || hapus;
}

/// Satu entri menu beserta izin seluruh role — dipakai layar Menu & Akses.
class MenuItemModel {
  final int id;
  final String kode;
  final String nama;
  final String grup;
  final int? menuIndex;
  final bool isAktif;

  /// Menu sistem (Menu & Akses, Reset) tidak bisa diberikan ke role lain.
  final bool isSistem;

  /// Izin per role, hanya terisi pada respons untuk admin.
  final Map<String, Izin> izin;

  const MenuItemModel({
    required this.id,
    required this.kode,
    required this.nama,
    required this.grup,
    this.menuIndex,
    this.isAktif = true,
    this.isSistem = false,
    this.izin = const {},
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> j) {
    final raw = j['izin'] as Map<String, dynamic>? ?? {};
    return MenuItemModel(
      id: int.tryParse('${j['id']}') ?? 0,
      kode: j['kode']?.toString() ?? '',
      nama: j['nama']?.toString() ?? '-',
      grup: j['grup']?.toString() ?? 'Lainnya',
      menuIndex: j['menu_index'] == null ? null : int.tryParse('${j['menu_index']}'),
      isAktif: j['is_aktif'] != false,
      isSistem: j['is_sistem'] == true,
      izin: raw.map((role, v) => MapEntry(role, Izin.fromJson(v as Map<String, dynamic>))),
    );
  }
}

/// Role yang ditampilkan sebagai kolom di layar Menu & Akses.
class RoleInfo {
  final String kode;
  final String nama;

  /// Admin selalu berakses penuh dan sakelarnya dikunci — itu yang mencegah
  /// siapa pun mengunci dirinya sendiri dari sistem.
  final bool terkunci;

  const RoleInfo({required this.kode, required this.nama, this.terkunci = false});

  factory RoleInfo.fromJson(Map<String, dynamic> j) => RoleInfo(
    kode: j['kode']?.toString() ?? '',
    nama: j['nama']?.toString() ?? '',
    terkunci: j['terkunci'] == true,
  );
}
