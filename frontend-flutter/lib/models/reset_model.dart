import 'package:flutter/material.dart';

/// Satu kelompok data yang bisa direset, apa adanya dari backend.
class ResetGroup {
  final String kode;
  final String nama;
  final String deskripsi;
  final String ikon;
  final int jumlah;

  /// Frasa yang harus diketik pengguna. Backend yang menentukan, bukan layar,
  /// supaya keduanya tidak mungkin berbeda.
  final String konfirmasi;

  /// Kelompok ini tidak bisa dijalankan dalam lingkup RT yang sedang dipilih.
  ///
  /// Hari ini hanya kelompok Sensor: `sensor_logs` tidak menyimpan RT sama
  /// sekali. Ditandai dari server, bukan disimpulkan layar — daftar tabel per
  /// kelompok hanya ada di `reset-groups.js`, dan menyalin pengetahuan itu ke
  /// sini berarti dua sumber yang bisa berbeda diam-diam.
  final bool terkunci;

  const ResetGroup({
    required this.kode,
    required this.nama,
    required this.deskripsi,
    required this.ikon,
    required this.jumlah,
    required this.konfirmasi,
    this.terkunci = false,
  });

  bool get kosong => jumlah == 0;
  bool get isTotal => kode == 'total';

  factory ResetGroup.fromJson(Map<String, dynamic> j) => ResetGroup(
    kode: j['kode']?.toString() ?? '',
    nama: j['nama']?.toString() ?? '',
    deskripsi: j['deskripsi']?.toString() ?? '',
    ikon: j['ikon']?.toString() ?? 'kotak',
    jumlah: (j['jumlah'] as num?)?.toInt() ?? 0,
    konfirmasi: j['konfirmasi']?.toString() ?? j['nama']?.toString() ?? '',
    terkunci: j['terkunci'] == true,
  );

  /// Backend sengaja tidak tahu-menahu soal widget, jadi pemetaan ikon ada di
  /// sini. Kunci yang tidak dikenal jatuh ke ikon netral, bukan error.
  IconData get ikonData =>
      const {
        'receipt': Icons.receipt_long,
        'wallet': Icons.account_balance_wallet,
        'akun_saldo': Icons.savings,
        'kotak': Icons.inventory_2,
        'surat': Icons.mail_outline,
        'kalender': Icons.event,
        'suara': Icons.how_to_vote,
        'bantuan': Icons.volunteer_activism,
        'toko': Icons.storefront,
        'keluarga': Icons.family_restroom,
        'akun': Icons.manage_accounts,
        'log': Icons.history,
        'sensor': Icons.sensors,
        'peringatan': Icons.dangerous,
      }[ikon] ??
      Icons.folder_outlined;
}

/// Jumlah baris yang akan terhapus pada satu tabel.
class ResetBaris {
  final String tabel;
  final int jumlah;

  const ResetBaris({required this.tabel, required this.jumlah});

  factory ResetBaris.fromJson(Map<String, dynamic> j) =>
      ResetBaris(tabel: j['tabel']?.toString() ?? '-', jumlah: (j['jumlah'] as num?)?.toInt() ?? 0);
}

/// Dampak lengkap sebuah reset sebelum dijalankan.
///
/// `ikutan` adalah baris yang terhapus karena rantai foreign key, bukan karena
/// ia sasaran kelompok ini — misalnya tagihan iuran yang ikut lenyap saat data
/// keluarga dihapus. Layar menampilkannya terpisah supaya tidak ada yang
/// hilang tanpa disadari.
class ResetPreview {
  final String kode;
  final String nama;
  final String deskripsi;
  final String konfirmasi;
  final List<ResetBaris> utama;
  final List<ResetBaris> ikutan;
  final int total;

  /// Nomor RT yang sedang dilingkupi; null berarti seluruh RW.
  final String? rtKode;

  /// Tabel yang TIDAK ikut terhapus karena tidak menyimpan RT.
  ///
  /// Ditampilkan, bukan disembunyikan: yang berbahaya bukan melewati sesuatu,
  /// melainkan melewatinya tanpa memberi tahu — angka nol pada sebuah tabel
  /// terbaca persis seperti "memang tidak ada datanya".
  final List<String> dilewati;

  const ResetPreview({
    required this.kode,
    required this.nama,
    required this.deskripsi,
    required this.konfirmasi,
    required this.utama,
    required this.ikutan,
    required this.total,
    this.rtKode,
    this.dilewati = const [],
  });

  bool get adaIkutan => ikutan.isNotEmpty;
  bool get kosong => total == 0;

  static List<ResetBaris> _baris(dynamic v) => (v as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(ResetBaris.fromJson)
      .where((b) => b.jumlah > 0)
      .toList();

  factory ResetPreview.fromJson(Map<String, dynamic> j) => ResetPreview(
    kode: j['kode']?.toString() ?? '',
    nama: j['nama']?.toString() ?? '',
    deskripsi: j['deskripsi']?.toString() ?? '',
    konfirmasi: j['konfirmasi']?.toString() ?? '',
    utama: _baris(j['utama']),
    ikutan: _baris(j['ikutan']),
    total: (j['total'] as num?)?.toInt() ?? 0,
    rtKode: j['rt_kode']?.toString(),
    dilewati: (j['dilewati'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
  );
}
