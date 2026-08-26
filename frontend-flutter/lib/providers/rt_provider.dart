import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

/// Satu RT dalam sebuah RW.
class RtModel {
  final String id;
  final String kode;
  final String nama;
  final String rwKode;
  final String? ketuaNama;
  final int jumlahKk;
  final int jumlahAkun;

  const RtModel({
    required this.id,
    required this.kode,
    required this.nama,
    required this.rwKode,
    this.ketuaNama,
    this.jumlahKk = 0,
    this.jumlahAkun = 0,
  });

  factory RtModel.fromJson(Map<String, dynamic> j) => RtModel(
        id: (j['id'] ?? '').toString(),
        kode: (j['kode'] ?? '').toString(),
        nama: (j['nama'] ?? '').toString(),
        rwKode: (j['rw_kode'] ?? '').toString(),
        ketuaNama: j['ketua_nama'] as String?,
        // Postgres mengirim COUNT sebagai string; `::int` di kueri sudah
        // menanganinya, tetapi parse ganda ini menjaga bila kueri berubah.
        jumlahKk: int.tryParse('${j['jumlah_kk'] ?? 0}') ?? 0,
        jumlahAkun: int.tryParse('${j['jumlah_akun'] ?? 0}') ?? 0,
      );

  String get label => nama.isNotEmpty ? nama : 'RT $kode';
}

/// RT mana yang sedang dilihat, dan daftar RT yang boleh dipilih.
///
/// Provider ini TIDAK menentukan hak akses. Ia hanya menyimpan pilihan dan
/// menyalurkannya ke `ApiService.lingkupRt`; server yang memutuskan apakah
/// pilihan itu dihormati. Untuk peran selain administrator dan ketua RW,
/// server selalu mengunci ke RT pemiliknya, apa pun isi nilai di sini.
///
/// Itu disengaja: pemeriksaan yang bisa diubah dari sisi klien bukan
/// pemeriksaan sama sekali.
class RtProvider extends ChangeNotifier {
  List<RtModel> _daftar = [];
  String? _terpilih;
  bool _isLoading = false;
  String? _errorMessage;

  List<RtModel> get daftar => _daftar;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Id RT yang sedang dilihat; null berarti seluruh RW.
  String? get terpilih => _terpilih;

  /// Pemilih RT hanya masuk akal bila memang ada lebih dari satu pilihan.
  bool get bolehMemilih => _daftar.length > 1;

  RtModel? get rtTerpilih {
    if (_terpilih == null) return null;
    for (final r in _daftar) {
      if (r.id == _terpilih) return r;
    }
    return null;
  }

  /// Teks untuk AppBar: nama RT, atau seluruh RW ketika tidak ada yang dipilih.
  String get labelLingkup {
    final r = rtTerpilih;
    if (r != null) return r.label;
    if (_daftar.isEmpty) return '';
    return 'Semua RT (RW ${_daftar.first.rwKode})';
  }

  Future<void> muat() async {
    _isLoading = true;
    notifyListeners();

    final response = await ApiService.get(ApiConstants.rt);
    _isLoading = false;

    if (response['success'] == true) {
      _daftar = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RtModel.fromJson)
          .toList();
      _errorMessage = null;

      // Peran yang hanya menerima satu RT tidak punya pilihan untuk dibuat,
      // jadi lingkupnya dibiarkan kosong: menyisipkan `?rt=` untuk mereka
      // tidak menambah keamanan apa pun dan hanya mengotori setiap URL.
      if (_daftar.length <= 1) {
        pilih(null);
      } else if (_terpilih != null && rtTerpilih == null) {
        // RT yang sedang dilihat ternyata sudah dihapus.
        pilih(null);
      }
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  /// Mengganti RT yang dilihat. `null` berarti seluruh RW.
  void pilih(String? idRt) {
    _terpilih = idRt;
    ApiService.lingkupRt = idRt;
    notifyListeners();
  }

  /// Dipanggil saat keluar. Wajib ikut mengosongkan `ApiService.lingkupRt`:
  /// nilai statis itu hidup selama proses, dan pengguna berikutnya akan
  /// mewarisi lingkup RT milik pengguna sebelumnya.
  void bersihkan() {
    _daftar = [];
    _terpilih = null;
    _errorMessage = null;
    _isLoading = false;
    ApiService.lingkupRt = null;
    notifyListeners();
  }
}
