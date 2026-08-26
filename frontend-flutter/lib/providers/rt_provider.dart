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

  /// Mengisi daftar tanpa memanggil server.
  ///
  /// Ada semata-mata untuk pengujian widget. Tanpa ini `_daftar` selalu kosong
  /// di lingkungan uji, `bolehMemilih` selalu false, dan pemilih RT tidak
  /// pernah dirender — sehingga uji tata letak "lolos" pada layar yang
  /// pemilihnya justru tidak muncul. Itu persis bentuk cacat yang membuat
  /// pemilih RT sempat hilang dari mode desktop tanpa ada yang menangkapnya.
  @visibleForTesting
  void isiUntukUji(List<RtModel> daftar, {String? terpilih}) {
    _daftar = daftar;
    _terpilih = terpilih;
    notifyListeners();
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

  /// Menambah RT baru. Hanya administrator yang diizinkan server.
  ///
  /// Mengembalikan pesan galat, atau `null` bila berhasil. Bentuk ini dipilih
  /// alih-alih `bool` karena server punya satu penolakan yang harus terbaca
  /// apa adanya: nomor RT yang sudah terpakai dibalas 409 dengan kalimatnya
  /// sendiri, dan menggantinya dengan "gagal menambah" menghilangkan satu-
  /// satunya keterangan yang berguna.
  Future<String?> tambah({
    required String kode,
    String? nama,
    String? rwKode,
    String? alamatSekretariat,
  }) async {
    final response = await ApiService.post(ApiConstants.rt, body: {
      'kode': kode,
      if (nama != null && nama.isNotEmpty) 'nama': nama,
      if (rwKode != null && rwKode.isNotEmpty) 'rw_kode': rwKode,
      if (alamatSekretariat != null && alamatSekretariat.isNotEmpty)
        'alamat_sekretariat': alamatSekretariat,
    });
    if (response['success'] == true) {
      await muat();
      return null;
    }
    return (response['message'] as String?) ?? 'Gagal menambah RT.';
  }

  /// Mengubah nama dan alamat sekretariat. Nomor RT sengaja tidak bisa diubah
  /// — ia sudah tertanam pada topik MQTT setiap perangkat alarm yang terpasang.
  Future<String?> ubah(
    String id, {
    String? nama,
    String? alamatSekretariat,
  }) async {
    final response = await ApiService.put(ApiConstants.rtDetail(id), body: {
      if (nama != null) 'nama': nama,
      if (alamatSekretariat != null) 'alamat_sekretariat': alamatSekretariat,
    });
    if (response['success'] == true) {
      await muat();
      return null;
    }
    return (response['message'] as String?) ?? 'Gagal memperbarui RT.';
  }

  /// Menghapus RT. Server menolak bila masih ada kartu keluarga atau akun di
  /// dalamnya, dan pesannya menyebutkan berapa banyak — jadi diteruskan utuh.
  Future<String?> hapus(String id) async {
    final response = await ApiService.delete(ApiConstants.rtDetail(id));
    if (response['success'] == true) {
      // RT yang sedang dilihat bisa saja RT yang baru dihapus; `muat()`
      // mengembalikan lingkupnya ke seluruh RW bila itu terjadi.
      await muat();
      return null;
    }
    return (response['message'] as String?) ?? 'Gagal menghapus RT.';
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
