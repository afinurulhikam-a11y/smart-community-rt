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

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  List<Map<String, dynamic>> get visitors => _visitors;
  Map<String, dynamic> get stats => _stats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  Future<void> fetchVisitors({
    String? status,
    String? tipe,
    String? search,
    String? tanggal,
    int page = 1,
  }) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': '10',
    };
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
      final pag = response['pagination'] as Map<String, dynamic>?;
      if (pag != null) {
        _currentPage = pag['current_page'] as int? ?? 1;
        _totalPages = pag['total_pages'] as int? ?? 1;
        _totalData = pag['total_data'] as int? ?? 0;
        _perPage = pag['per_page'] as int? ?? 10;
      } else {
        _currentPage = 1;
        _totalPages = 1;
        _totalData = _visitors.length;
        _perPage = 10;
      }
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
      await fetchVisitors(page: _currentPage);
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
      await fetchVisitors(page: _currentPage);
      await fetchStats();
      return true;
    }
    return false;
  }

  Future<bool> deleteVisitor(int id) async {
    final response = await ApiService.delete('${ApiConstants.visitors}/$id');
    if (response['success'] == true) {
      await fetchVisitors(page: _currentPage);
      await fetchStats();
      return true;
    }
    return false;
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  void bersihkan() {
    _visitors = [];
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _perPage = 10;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

}
