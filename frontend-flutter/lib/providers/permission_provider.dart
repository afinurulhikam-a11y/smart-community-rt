import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/permission_model.dart';

/// Menyimpan izin efektif pengguna yang sedang masuk, dan menjadi satu-satunya
/// sumber yang dipakai sidebar untuk menentukan menu apa yang ditampilkan.
///
/// Ini hanya lapisan tampilan. Penegakan yang sesungguhnya ada di backend
/// (`requirePermission`) — menyembunyikan menu bukan kontrol akses.
class PermissionProvider extends ChangeNotifier {
  Map<String, Izin> _izin = {};
  String _role = '';
  String _roleLabel = '';
  bool _isLoading = false;
  bool _sudahDimuat = false;

  String get role => _role;
  String get roleLabel => _roleLabel;
  bool get isLoading => _isLoading;
  bool get sudahDimuat => _sudahDimuat;

  bool get isAdmin => _role == 'admin';

  /// Sebelum izin selesai dimuat, jangan tampilkan apa pun yang belum pasti —
  /// lebih baik menu muncul terlambat daripada muncul lalu hilang.
  Izin izinUntuk(String kode) {
    if (isAdmin) return Izin.penuh();
    return _izin[kode] ?? const Izin();
  }

  bool bolehLihat(String kode) => izinUntuk(kode).lihat;
  bool bolehTambah(String kode) => izinUntuk(kode).tambah;
  bool bolehUbah(String kode) => izinUntuk(kode).ubah;
  bool bolehHapus(String kode) => izinUntuk(kode).hapus;

  /// True bila menunya boleh dibuka tetapi isinya tidak boleh diubah.
  bool hanyaLihat(String kode) => izinUntuk(kode).hanyaLihat;

  /// True bila salah satu dari beberapa menu boleh dilihat — dipakai untuk
  /// memutuskan apakah sebuah grup menu perlu ditampilkan.
  bool bolehLihatSalahSatu(List<String> kodeList) => kodeList.any(bolehLihat);

  Future<void> muat() async {
    _isLoading = true;
    notifyListeners();

    try {
      final r = await ApiService.get(ApiConstants.menuAksesSaya).timeout(const Duration(seconds: 5));
      if (r['success'] == true && r['data'] != null) {
        terapkanData(r['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
    } finally {
      _sudahDimuat = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Terapkan muatan izin dari server.
  ///
  /// Dipisah dari [muat] supaya penguraiannya bisa diuji tanpa jaringan.
  /// Seluruh gerbang menu untuk setiap peran bertumpu pada bagian ini, dan
  /// sampai sekarang ia tidak punya satu pun uji — sebuah kekeliruan di sini
  /// diam-diam membuka atau menyembunyikan modul bagi peran yang salah, dan
  /// tidak ada yang menangkapnya sebelum sampai ke perangkat.
  void terapkanData(Map<String, dynamic> data) {
    _role = data['role']?.toString() ?? '';
    _roleLabel = data['role_label']?.toString() ?? '';
    _izin = {
      for (final m in (data['menus'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>())
        m['kode'].toString(): Izin.fromJson(m),
    };
  }

  /// Dipanggil saat logout supaya izin pengguna sebelumnya tidak terbawa.
  void bersihkan() {
    _izin = {};
    _role = '';
    _roleLabel = '';
    _sudahDimuat = false;
    notifyListeners();
  }
}
