import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class LogProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _total = 0;

  List<Map<String, dynamic>> get logs => _logs;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Jumlah baris yang cocok dengan penyaring — bukan jumlah yang sedang tampil.
  ///
  /// Dibutuhkan justru karena jejak audit tidak pernah dihapus: tanpa angka ini
  /// layar tidak bisa memberi tahu bahwa masih ada ribuan baris di belakang 25
  /// yang terlihat, dan pembacanya akan menyangka itulah seluruh isinya.
  int get total => _total;

  /// Tanggal dikirim sebagai `yyyy-MM-dd` dari komponen LOKAL.
  ///
  /// `toIso8601String()` mengubahnya ke UTC lebih dulu, sehingga 1 Agustus di
  /// WIB terkirim sebagai 31 Juli — sehari penuh hilang dari hasil tanpa ada
  /// yang tampak salah.
  static String? _keTanggal(DateTime? t) {
    if (t == null) return null;
    final b = t.month.toString().padLeft(2, '0');
    final h = t.day.toString().padLeft(2, '0');
    return '${t.year}-$b-$h';
  }

  Future<void> fetchLogs({
    int limit = 25,
    int offset = 0,
    String? search,
    String? tipe,
    DateTime? dari,
    DateTime? sampai,
  }) async {
    _isLoading = true;
    notifyListeners();

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (tipe != null && tipe != 'Semua') queryParams['tipe'] = tipe;

    final d = _keTanggal(dari);
    final s = _keTanggal(sampai);
    if (d != null) queryParams['dari'] = d;
    if (s != null) queryParams['sampai'] = s;

    final response = await ApiService.get(ApiConstants.activityLogs, queryParams: queryParams);

    _isLoading = false;
    if (response['success'] == true) {
      _logs = List<Map<String, dynamic>>.from(response['data'] ?? []);
      // `total` dihitung backend dengan penyaring yang sama tetapi tanpa LIMIT.
      // Kalau tidak ada, jatuhkan ke jumlah baris yang diterima supaya
      // pagination tidak melaporkan "dari 0".
      _total = (response['total'] as num?)?.toInt() ?? _logs.length;
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  // `clearLogs()` DIHAPUS dengan sengaja.
  //
  // Dulu memanggil `DELETE /api/activity-logs`, yang membuat Administrator
  // bisa melenyapkan seluruh bukti perbuatannya sendiri dan hanya menyisakan
  // satu baris "Membersihkan seluruh log" — tanpa keterangan apa pun tentang
  // isi yang dihapus.
  //
  // Endpoint-nya sudah tidak ada, dan `activity_logs` menolak DELETE maupun
  // TRUNCATE di tingkat database. Jangan ditambahkan kembali.
}
