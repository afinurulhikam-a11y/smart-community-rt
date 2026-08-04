import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
// KategoriKasModel dipakai ulang karena bentuk JSON kategori BOP identik
// (id, nama_kategori, tipe, is_aktif, jumlah_transaksi). Mengikuti preseden
// BopProvider yang memakai ulang FinanceModel. Bila kategori BOP suatu saat
// menyimpang bentuknya, barulah dibuatkan model tersendiri.
import '../models/kategori_kas_model.dart';

class KategoriBopProvider extends ChangeNotifier {
  List<KategoriKasModel> _list = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<KategoriKasModel> get list => _list;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Kategori aktif sesuai jenis transaksi yang sedang dicatat — kategori
  /// belanja tidak boleh muncul saat mencatat pemasukan.
  List<KategoriKasModel> untukTipe(String tipe) {
    final target = tipe == 'pemasukan' ? 'IN' : 'OUT';
    return _list.where((k) => k.isAktif && k.tipe == target).toList();
  }

  Future<void> fetchKategoriBop() async {
    _isLoading = true;
    notifyListeners();

    final response = await ApiService.get(ApiConstants.kategoriBop);
    _isLoading = false;
    if (response['success'] == true) {
      _list = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(KategoriKasModel.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> create({
    required String namaKategori,
    required String tipe,
    String? keterangan,
  }) async {
    final response = await ApiService.post(
      ApiConstants.kategoriBop,
      body: {
        'nama_kategori': namaKategori,
        'tipe': tipe,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
      },
    );
    if (response['success'] == true) await fetchKategoriBop();
    return response;
  }

  Future<Map<String, dynamic>> update(
    int id, {
    String? namaKategori,
    String? tipe,
    String? keterangan,
    bool? isAktif,
  }) async {
    final response = await ApiService.put(
      ApiConstants.kategoriBopById(id),
      body: {
        if (namaKategori != null) 'nama_kategori': namaKategori,
        if (tipe != null) 'tipe': tipe,
        if (keterangan != null) 'keterangan': keterangan,
        if (isAktif != null) 'is_aktif': isAktif,
      },
    );
    if (response['success'] == true) await fetchKategoriBop();
    return response;
  }

  Future<Map<String, dynamic>> delete(int id) async {
    final response = await ApiService.delete(ApiConstants.kategoriBopById(id));
    if (response['success'] == true) await fetchKategoriBop();
    return response;
  }
}
