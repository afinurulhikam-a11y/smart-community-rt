import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/reset_model.dart';

/// Menggerakkan layar Reset Sistem.
///
/// Seluruh keputusan tentang APA yang dihapus ada di backend; provider ini
/// hanya mengirim kode kelompok dan menampilkan jawabannya.
class ResetProvider extends ChangeNotifier {
  List<ResetGroup> _grup = [];
  bool _isLoading = false;
  bool _sedangProses = false;
  String? _error;

  List<ResetGroup> get grup => _grup;
  bool get isLoading => _isLoading;

  /// True selama pratinjau atau eksekusi berjalan — dipakai layar untuk
  /// mematikan tombol agar tidak terkirim dua kali.
  bool get sedangProses => _sedangProses;
  String? get error => _error;

  /// Kelompok selain Reset Total, untuk kartu-kartu di bagian atas.
  List<ResetGroup> get kelompokBiasa => _grup.where((g) => !g.isTotal).toList();

  ResetGroup? get grupTotal {
    for (final g in _grup) {
      if (g.isTotal) return g;
    }
    return null;
  }

  int get totalBaris => kelompokBiasa.fold<int>(0, (a, g) => a + g.jumlah);

  Future<void> muatRingkasan() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final r = await ApiService.get(ApiConstants.resetRingkasan);
    if (r['success'] == true) {
      _grup = (r['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ResetGroup.fromJson)
          .toList();
    } else {
      _error = r['message']?.toString() ?? 'Gagal memuat ringkasan.';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Hitung dampak sebuah kelompok tanpa menghapus apa pun.
  Future<ResetPreview?> pratinjau(String kode) async {
    _sedangProses = true;
    _error = null;
    notifyListeners();

    final r = await ApiService.post(ApiConstants.resetPratinjau, body: {'grup': kode});

    _sedangProses = false;
    if (r['success'] == true && r['data'] != null) {
      notifyListeners();
      return ResetPreview.fromJson(r['data'] as Map<String, dynamic>);
    }

    _error = r['message']?.toString() ?? 'Gagal menghitung dampak reset.';
    notifyListeners();
    return null;
  }

  /// Unduh berkas cadangan lewat browser, memakai tiket sekali pakai.
  ///
  /// Ini justru URL yang paling tidak boleh tercatat di log: ia menstreamkan
  /// dump mentah seluruh tabel dalam satu grup reset, data warga termasuk.
  /// `grup` tetap wajib — cadangan bersifat per-kelompok, bukan seluruh basis
  /// data, dan menghilangkannya membuat orang mengira sudah punya cadangan
  /// tepat sebelum menghapus data.
  Future<bool> unduhCadangan(String kode) async {
    final r = await ApiService.unduhDenganTiket(
      'reset.cadangan',
      parameter: {'grup': kode},
    );
    if (r['success'] != true) {
      _error = r['message']?.toString() ?? 'Gagal mengunduh cadangan.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Jalankan penghapusan.
  ///
  /// Sengaja TIDAK memakai ApiService.post: helper itu mencoba ulang sampai
  /// dua kali saat waktu habis. Untuk penghapusan, percobaan ulang berarti
  /// perintah hapus bisa terkirim lebih dari sekali dan menghasilkan dua
  /// catatan reset untuk satu tindakan. Di sini satu percobaan saja, dengan
  /// tenggat lebih panjang karena reset besar memang perlu waktu.
  Future<Map<String, dynamic>> eksekusi({
    required String kode,
    required String konfirmasi,
    required String password,
    required bool dicadangkan,
  }) async {
    _sedangProses = true;
    _error = null;
    notifyListeners();

    Map<String, dynamic> hasil;
    try {
      final res = await http
          .post(
            Uri.parse(ApiConstants.resetEksekusi),
            headers: {
              'Content-Type': 'application/json',
              if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
            },
            body: jsonEncode({
              'grup': kode,
              'konfirmasi': konfirmasi,
              'password': password,
              'dicadangkan': dicadangkan,
            }),
          )
          .timeout(const Duration(seconds: 120));
      hasil = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      // Backend membungkus penghapusan dalam satu transaksi, jadi koneksi yang
      // putus tidak meninggalkan data setengah terhapus. Yang belum pasti
      // hanyalah apakah transaksinya sempat selesai — karena itu pengguna
      // diminta memuat ulang, bukan diberi tahu bahwa reset gagal.
      hasil = {
        'success': false,
        'message':
            'Koneksi terputus sebelum server menjawab. '
            'Muat ulang halaman untuk melihat keadaan data yang sebenarnya.',
      };
    }

    _sedangProses = false;
    if (hasil['success'] != true) {
      _error = hasil['message']?.toString();
    }
    notifyListeners();

    if (hasil['success'] == true) await muatRingkasan();
    return hasil;
  }

  void bersihkanError() {
    _error = null;
    notifyListeners();
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _grup = [];
    _isLoading = false;
    _sedangProses = false;
    _error = null;
    notifyListeners();
  }

}
