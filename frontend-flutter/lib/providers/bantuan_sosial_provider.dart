import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class BantuanSosialProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _bantuanList = [];
  Map<String, dynamic> _stats = {'total_penerima': 0, 'aktif': 0, 'selesai': 0, 'jenis_aktif': 0};
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _wargaList = [];
  List<Map<String, dynamic>> get bantuanList => _bantuanList;
  List<Map<String, dynamic>> get wargaList => _wargaList;
  Map<String, dynamic> get stats => _stats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchBantuanSosial({
    String? tahun,
    String? jenisBantuan,
    String? status,
    String? search,
  }) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (tahun != null) queryParams['tahun'] = tahun;
    if (jenisBantuan != null) queryParams['jenis_bantuan'] = jenisBantuan;
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;
    final response = await ApiService.get(
      ApiConstants.bantuanSosial,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _bantuanList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<void> fetchStats() async {
    final response = await ApiService.get(ApiConstants.bantuanSosialStats);
    if (response['success'] == true && response['data'] != null) {
      _stats = Map<String, dynamic>.from(response['data']);
      notifyListeners();
    }
  }

  Future<void> fetchWargaList() async {
    final response = await ApiService.get('${ApiConstants.users}?role=warga');
    if (response['success'] == true) {
      _wargaList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      notifyListeners();
    }
  }

  Future<bool> createBantuanSosial({
    required String userId,
    required String jenisBantuan,
    required int tahun,
    double? nominal,
    String? keterangan,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.bantuanSosial,
      body: {
        'user_id': userId,
        'jenis_bantuan': jenisBantuan,
        'tahun': tahun,
        if (nominal != null) 'nominal': nominal,
        if (keterangan != null) 'keterangan': keterangan,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchBantuanSosial();
      await fetchStats();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateBantuanSosial(int id, Map<String, dynamic> data) async {
    final response = await ApiService.put('${ApiConstants.bantuanSosial}/$id', body: data);
    if (response['success'] == true) {
      await fetchBantuanSosial();
      await fetchStats();
      return true;
    }
    return false;
  }

  Future<bool> deleteBantuanSosial(int id) async {
    final response = await ApiService.delete('${ApiConstants.bantuanSosial}/$id');
    if (response['success'] == true) {
      await fetchBantuanSosial();
      await fetchStats();
      return true;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> fetchBantuanSosialHistory(int id) async {
    final response = await ApiService.get('${ApiConstants.bantuanSosial}/$id/history');
    if (response['success'] == true && response['data'] != null) {
      return List<Map<String, dynamic>>.from(response['data']);
    }
    return [];
  }
}
