/// Satu bacaan meteran air, untuk satu rumah pada satu periode.
///
/// **Bacaan meteran bukan tagihan.** Ia lahir tanggal 1 saat warga mengisi;
/// tagihannya baru lahir tanggal 25 saat difinalisasi. Selama di antara
/// keduanya, baris ini ada sendirian dan `billId` masih null — itu keadaan
/// normal, bukan data yang belum lengkap.
///
/// Pemakaian (`terpakai`) sengaja **tidak** ada di backend. Ia selalu bisa
/// dihitung ulang dari kedua angka meterannya, dan menyimpan turunan berarti
/// membuka kemungkinan ia berbeda dari bahan penyusunnya — tanpa cara
/// mengetahui mana yang benar. Alasan yang sama dipakai `bills`.
class MeteranModel {
  final String id;
  final int keluargaId;
  final String periode;
  final int? meteranLalu;
  final int? meteranSekarang;

  /// `menunggu` / `terisi` / `anomali` — sama persis dengan CHECK di database.
  final String status;

  /// Alasan anomali, atau alasan koreksi pengurus.
  final String? catatan;

  final DateTime? diisiPada;
  final DateTime? dikoreksiPada;

  /// Terisi begitu bacaan ini menjadi tagihan. Null = tagihan belum terbit,
  /// dan selama itu warga masih boleh mengubah angkanya.
  final String? billId;

  // Data pelanggan, ikut dari JOIN — dipakai layar pengurus.
  final String? noKk;
  final String? kepalaKeluarga;
  final String? blok;
  final String? alamat;

  /// Status tagihan yang lahir dari bacaan ini, bila sudah ada.
  final String? statusTagihan;
  final double? nominal;
  final bool? langgananSampah;

  const MeteranModel({
    required this.id,
    required this.keluargaId,
    required this.periode,
    required this.status,
    this.meteranLalu,
    this.meteranSekarang,
    this.catatan,
    this.diisiPada,
    this.dikoreksiPada,
    this.billId,
    this.noKk,
    this.kepalaKeluarga,
    this.blok,
    this.alamat,
    this.statusTagihan,
    this.nominal,
    this.langgananSampah,
  });

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  static DateTime? _tanggal(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse('$v');
  }

  factory MeteranModel.fromJson(Map<String, dynamic> json) {
    return MeteranModel(
      id: json['id']?.toString() ?? '',
      keluargaId: _int(json['keluarga_id']) ?? 0,
      periode: json['periode']?.toString() ?? '',
      status: json['status']?.toString() ?? 'menunggu',
      meteranLalu: _int(json['meteran_lalu']),
      meteranSekarang: _int(json['meteran_sekarang']),
      catatan: json['catatan']?.toString(),
      diisiPada: _tanggal(json['diisi_pada']),
      dikoreksiPada: _tanggal(json['dikoreksi_pada']),
      billId: json['bill_id']?.toString(),
      noKk: json['no_kk']?.toString(),
      kepalaKeluarga: json['kepala_keluarga']?.toString(),
      blok: json['blok']?.toString(),
      alamat: json['alamat']?.toString(),
      statusTagihan: json['status_tagihan']?.toString(),
      langgananSampah: json['langganan_sampah'] == true,
      // Postgres mengirim NUMERIC sebagai string: "50000", bukan 50000.
      nominal: json['nominal'] == null
          ? null
          : (json['nominal'] is num
              ? (json['nominal'] as num).toDouble()
              : double.tryParse('${json['nominal']}')),
    );
  }

  /// Pemakaian m³, dihitung — tidak pernah dibaca dari server.
  ///
  /// Dibatasi bawah 0 supaya bacaan anomali tidak pernah tampil negatif di
  /// layar. Anomalinya sendiri terlihat dari [anomali], bukan dari angka minus.
  int? get terpakai {
    if (meteranSekarang == null || meteranLalu == null) return null;
    final selisih = meteranSekarang! - meteranLalu!;
    return selisih < 0 ? 0 : selisih;
  }

  bool get sudahDiisi => meteranSekarang != null;
  bool get anomali => status == 'anomali';
  bool get sudahJadiTagihan => billId != null && billId!.isNotEmpty;

  /// Masih boleh diubah warga — selama tagihannya belum terbit.
  bool get bisaDiubah => !sudahJadiTagihan;

  String get statusLabel {
    switch (status) {
      case 'terisi':
        return 'Terisi';
      case 'anomali':
        return 'Anomali';
      default:
        return 'Menunggu';
    }
  }
}

/// Keadaan periode berjalan milik warga, dari `GET /meteran/saya`.
///
/// Bentuknya lebih luas daripada satu bacaan karena layar perlu tahu keadaan
/// yang belum punya baris sama sekali: periode pertama, apakah masih boleh
/// mengisi, dan berapa angka pembandingnya.
class MeteranSaya {
  final String namaPelanggan;
  final String? noKk;
  final String? blok;
  final String? alamat;
  final bool langgananSampah;

  final String periode;

  /// Periode pertama dikenali dari tidak adanya bacaan sebelumnya — bukan dari
  /// tanggal. Rumah yang baru masuk di tengah tahun pun menjalani periode
  /// pertamanya sendiri, dan pada periode itu warga mengisi DUA angka.
  final bool periodePertama;

  final int? meteranLalu;
  final MeteranModel? bacaan;

  /// Tanggal 1–5. Setelah itu koreksi hanya lewat pengurus.
  final bool bolehIsi;
  final int batasTanggal;

  const MeteranSaya({
    required this.namaPelanggan,
    required this.periode,
    required this.periodePertama,
    required this.bolehIsi,
    required this.batasTanggal,
    required this.langgananSampah,
    this.noKk,
    this.blok,
    this.alamat,
    this.meteranLalu,
    this.bacaan,
  });

  factory MeteranSaya.fromJson(Map<String, dynamic> json) {
    final pelanggan = (json['pelanggan'] as Map<String, dynamic>?) ?? const {};
    final bacaanJson = json['bacaan'] as Map<String, dynamic>?;
    return MeteranSaya(
      namaPelanggan: pelanggan['nama']?.toString() ?? '-',
      noKk: pelanggan['no_kk']?.toString(),
      blok: pelanggan['blok']?.toString(),
      alamat: pelanggan['alamat']?.toString(),
      langgananSampah: pelanggan['langganan_sampah'] == true,
      periode: json['periode']?.toString() ?? '',
      periodePertama: json['periode_pertama'] == true,
      meteranLalu: MeteranModel._int(json['meteran_lalu']),
      bacaan: bacaanJson == null ? null : MeteranModel.fromJson(bacaanJson),
      bolehIsi: json['boleh_isi'] == true,
      batasTanggal: MeteranModel._int(json['batas_tanggal']) ?? 5,
    );
  }

  bool get sudahDiisi => bacaan?.sudahDiisi == true;
  bool get terkunci => bacaan?.sudahJadiTagihan == true;
}
