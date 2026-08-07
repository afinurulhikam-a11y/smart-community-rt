/// Satu irisan kategori pada chart statistik, misalnya "Menikah: 12".
///
/// Backend mengirim seluruh pecahan demografi (usia, agama, pendidikan,
/// pekerjaan, perkawinan, domisili) dalam bentuk daftar yang sama, sehingga
/// satu kelas ini cukup untuk semuanya dan chart bisa dibangun secara generik.
class KategoriStat {
  final String label;
  final int jumlah;

  const KategoriStat({required this.label, required this.jumlah});

  factory KategoriStat.fromJson(Map<String, dynamic> json) {
    return KategoriStat(
      label: json['label']?.toString() ?? 'Tidak Diisi',
      jumlah: _toInt(json['jumlah']),
    );
  }

  static List<KategoriStat> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(KategoriStat.fromJson).toList();
  }
}

class DemographicSummary {
  final int totalWarga;
  final int totalKk;
  final int lakiLaki;
  final int perempuan;

  const DemographicSummary({
    required this.totalWarga,
    required this.totalKk,
    required this.lakiLaki,
    required this.perempuan,
  });

  factory DemographicSummary.fromJson(Map<String, dynamic> json) {
    return DemographicSummary(
      totalWarga: _toInt(json['total_warga']),
      totalKk: _toInt(json['total_kk']),
      lakiLaki: _toInt(json['laki_laki']),
      perempuan: _toInt(json['perempuan']),
    );
  }
}

/// Kelompok rentan & sosial — seluruhnya dihitung per jiwa.
///
/// `rumahSewaKos` dihapus bersama kartunya di layar Statistik. Ia satu-satunya
/// isi kelompok ini yang dihitung per kartu keluarga, bukan per jiwa, sehingga
/// berdiri sejajar dengan tiga angka lain yang tidak sebanding dengannya.
/// Hitungannya juga dilepas dari kueri backend, bukan sekadar disembunyikan.
class DemographicRentan {
  final int balita;
  final int lansia;
  final int jandaDuda;

  const DemographicRentan({
    required this.balita,
    required this.lansia,
    required this.jandaDuda,
  });

  factory DemographicRentan.fromJson(Map<String, dynamic> json) {
    return DemographicRentan(
      balita: _toInt(json['balita']),
      lansia: _toInt(json['lansia']),
      jandaDuda: _toInt(json['janda_duda']),
    );
  }
}

class DemographicData {
  final DemographicSummary summary;
  final DemographicRentan rentan;
  final List<KategoriStat> gender;
  final List<KategoriStat> usia;
  final List<KategoriStat> pernikahan;
  final List<KategoriStat> domisili;
  final List<KategoriStat> pendidikan;
  final List<KategoriStat> pekerjaan;
  final List<KategoriStat> agama;

  const DemographicData({
    required this.summary,
    required this.rentan,
    required this.gender,
    required this.usia,
    required this.pernikahan,
    required this.domisili,
    required this.pendidikan,
    required this.pekerjaan,
    required this.agama,
  });

  factory DemographicData.fromJson(Map<String, dynamic> json) {
    return DemographicData(
      summary: DemographicSummary.fromJson((json['summary'] as Map<String, dynamic>?) ?? const {}),
      rentan: DemographicRentan.fromJson((json['rentan'] as Map<String, dynamic>?) ?? const {}),
      gender: KategoriStat.listFromJson(json['gender']),
      usia: KategoriStat.listFromJson(json['usia']),
      pernikahan: KategoriStat.listFromJson(json['pernikahan']),
      domisili: KategoriStat.listFromJson(json['domisili']),
      pendidikan: KategoriStat.listFromJson(json['pendidikan']),
      pekerjaan: KategoriStat.listFromJson(json['pekerjaan']),
      agama: KategoriStat.listFromJson(json['agama']),
    );
  }
}

/// Postgres bisa mengirim angka sebagai int maupun string tergantung tipe
/// kolomnya, jadi konversinya dibuat toleran di satu tempat.
int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
