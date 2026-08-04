import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class VisitorProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _visitors = [];
  Map<String, dynamic> _stats = {
    'tamu_hari_ini': 0,
    'sedang_di_dalam': 0,
    'tamu_menginap': 0,
    'total_semua': 0,
  };
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get visitors => _visitors;
  Map<String, dynamic> get stats => _stats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchVisitors({
    String? status,
    String? tipe,
    String? search,
    String? tanggal,
  }) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (tipe != null) queryParams['tipe'] = tipe;
    if (search != null) queryParams['search'] = search;
    if (tanggal != null) queryParams['tanggal'] = tanggal;
    final response = await ApiService.get(
      ApiConstants.visitors,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _visitors = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<void> fetchStats() async {
    final response = await ApiService.get(ApiConstants.visitorStats);
    if (response['success'] == true && response['data'] != null) {
      _stats = Map<String, dynamic>.from(response['data']);
      notifyListeners();
    }
  }

  Future<bool> createVisitor({
    required String namaTamu,
    String? noHpTamu,
    String? blokTujuan,
    String? noHpTujuan,
    String? tipeKeperluan,
    String? detailKeperluan,
    String? platNomor,
    String? jenisKendaraan,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.visitors,
      body: {
        'nama_tamu': namaTamu,
        if (noHpTamu != null) 'no_hp_tamu': noHpTamu,
        if (blokTujuan != null) 'blok_tujuan': blokTujuan,
        if (noHpTujuan != null) 'no_hp_tujuan': noHpTujuan,
        if (tipeKeperluan != null) 'tipe_keperluan': tipeKeperluan,
        if (detailKeperluan != null) 'detail_keperluan': detailKeperluan,
        if (platNomor != null) 'plat_nomor': platNomor,
        if (jenisKendaraan != null) 'jenis_kendaraan': jenisKendaraan,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchVisitors();
      await fetchStats();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkoutVisitor(int id) async {
    final response = await ApiService.put(ApiConstants.visitorCheckout(id));
    if (response['success'] == true) {
      await fetchVisitors();
      await fetchStats();
      return true;
    }
    return false;
  }

  Future<bool> deleteVisitor(int id) async {
    final response = await ApiService.delete('${ApiConstants.visitors}/$id');
    if (response['success'] == true) {
      await fetchVisitors();
      await fetchStats();
      return true;
    }
    return false;
  }
}
