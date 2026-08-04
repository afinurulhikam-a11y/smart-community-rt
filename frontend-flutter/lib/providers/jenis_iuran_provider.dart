import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/jenis_iuran_model.dart';

class JenisIuranProvider extends ChangeNotifier {
  List<JenisIuranModel> _list = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<JenisIuranModel> get list => _list;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Hanya jenis aktif — dipakai untuk dropdown filter dan dialog buat tagihan,
  /// supaya jenis yang sudah dinonaktifkan tidak bisa dipilih lagi.
  List<JenisIuranModel> get aktif => _list.where((e) => e.isAktif).toList();

  Future<void> fetchJenisIuran() async {
    _isLoading = true;
    notifyListeners();

    final response = await ApiService.get(ApiConstants.jenisIuran);
    _isLoading = false;
    if (response['success'] == true) {
      _list = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(JenisIuranModel.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> create({
    required String namaIuran,
    required double nominalDefault,
    required String periode,
    String? keterangan,
  }) async {
    final response = await ApiService.post(
      ApiConstants.jenisIuran,
      body: {
        'nama_iuran': namaIuran,
        'nominal_default': nominalDefault,
        'periode': periode,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
      },
    );
    if (response['success'] == true) await fetchJenisIuran();
    return response;
  }

  Future<Map<String, dynamic>> update(
    int id, {
    String? namaIuran,
    double? nominalDefault,
    String? periode,
    String? keterangan,
    bool? isAktif,
  }) async {
    final response = await ApiService.put(
      ApiConstants.jenisIuranById(id),
      body: {
        if (namaIuran != null) 'nama_iuran': namaIuran,
        if (nominalDefault != null) 'nominal_default': nominalDefault,
        if (periode != null) 'periode': periode,
        if (keterangan != null) 'keterangan': keterangan,
        if (isAktif != null) 'is_aktif': isAktif,
      },
    );
    if (response['success'] == true) await fetchJenisIuran();
    return response;
  }

  Future<Map<String, dynamic>> delete(int id) async {
    final response = await ApiService.delete(ApiConstants.jenisIuranById(id));
    if (response['success'] == true) await fetchJenisIuran();
    return response;
  }
}
