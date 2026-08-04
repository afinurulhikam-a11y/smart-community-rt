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

    final r = await ApiService.get(ApiConstants.menuAksesSaya);
    if (r['success'] == true && r['data'] != null) {
      final d = r['data'] as Map<String, dynamic>;
      _role = d['role']?.toString() ?? '';
      _roleLabel = d['role_label']?.toString() ?? '';
      _izin = {
        for (final m in (d['menus'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>())
          m['kode'].toString(): Izin.fromJson(m),
      };
      _sudahDimuat = true;
    }

    _isLoading = false;
    notifyListeners();
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
