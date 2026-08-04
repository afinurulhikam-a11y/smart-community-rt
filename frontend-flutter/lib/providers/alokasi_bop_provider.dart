import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/bop_model.dart';

class AlokasiBopProvider extends ChangeNotifier {
  List<AlokasiBopModel> _list = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<AlokasiBopModel> get list => _list;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Total pagu untuk satu tahun, dijumlahkan dari seluruh terminnya.
  double totalPagu(int tahun) =>
      _list.where((a) => a.tahun == tahun).fold<double>(0, (s, a) => s + a.nominal);

  Future<void> fetchAlokasi({int? tahun}) async {
    _isLoading = true;
    notifyListeners();

    final response = await ApiService.get(
      ApiConstants.alokasiBop,
      queryParams: tahun != null ? {'tahun': tahun.toString()} : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _list = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AlokasiBopModel.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> create({
    required int tahun,
    required String termin,
    required double nominal,
    String? sumberDana,
    String? keterangan,
  }) async {
    final response = await ApiService.post(
      ApiConstants.alokasiBop,
      body: {
        'tahun': tahun,
        'termin': termin,
        'nominal': nominal,
        if (sumberDana != null && sumberDana.isNotEmpty) 'sumber_dana': sumberDana,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
      },
    );
    if (response['success'] == true) await fetchAlokasi();
    return response;
  }

  Future<Map<String, dynamic>> update(
    int id, {
    int? tahun,
    String? termin,
    double? nominal,
    String? sumberDana,
    String? keterangan,
  }) async {
    final response = await ApiService.put(
      ApiConstants.alokasiBopById(id),
      body: {
        if (tahun != null) 'tahun': tahun,
        if (termin != null) 'termin': termin,
        if (nominal != null) 'nominal': nominal,
        if (sumberDana != null) 'sumber_dana': sumberDana,
        if (keterangan != null) 'keterangan': keterangan,
      },
    );
    if (response['success'] == true) await fetchAlokasi();
    return response;
  }

  Future<Map<String, dynamic>> delete(int id) async {
    final response = await ApiService.delete(ApiConstants.alokasiBopById(id));
    if (response['success'] == true) await fetchAlokasi();
    return response;
  }
}
