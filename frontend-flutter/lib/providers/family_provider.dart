import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class FamilyProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _families = [];
  Map<String, dynamic>? _selectedFamily;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get families => _families;
  Map<String, dynamic>? get selectedFamily => _selectedFamily;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchFamilies({String? search}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (search != null) queryParams['search'] = search;
    final response = await ApiService.get(
      ApiConstants.families,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _families = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<void> fetchFamilyDetail(int id) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.get('${ApiConstants.families}/$id');
    _isLoading = false;
    if (response['success'] == true) {
      _selectedFamily = Map<String, dynamic>.from(response['data']);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> createFamily({
    required String noKk,
    required String kepalaKeluarga,
    String? alamat,
    String? rt,
    String? rw,
    String? kelurahan,
    String? kecamatan,
    List<Map<String, dynamic>>? anggota,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.families,
      body: {
        'no_kk': noKk,
        'kepala_keluarga': kepalaKeluarga,
        if (alamat != null) 'alamat': alamat,
        if (rt != null) 'rt': rt,
        if (rw != null) 'rw': rw,
        if (kelurahan != null) 'kelurahan': kelurahan,
        if (kecamatan != null) 'kecamatan': kecamatan,
        if (anggota != null) 'anggota': anggota,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchFamilies();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateFamily(int id, Map<String, dynamic> data) async {
    final response = await ApiService.put('${ApiConstants.families}/$id', body: data);
    if (response['success'] == true) {
      await fetchFamilies();
      return true;
    }
    return false;
  }

  Future<bool> deleteFamily(int id) async {
    final response = await ApiService.delete('${ApiConstants.families}/$id');
    if (response['success'] == true) {
      await fetchFamilies();
      return true;
    }
    return false;
  }
}
