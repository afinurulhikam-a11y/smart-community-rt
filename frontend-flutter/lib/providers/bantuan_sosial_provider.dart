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

  // Pagination sisi server, menyamai layar lain (Kas RT, Iuran, Data Warga).
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  Future<void> fetchBantuanSosial({
    String? tahun,
    String? tanggalMulai,
    String? tanggalSelesai,
    String? jenisBantuan,
    String? status,
    String? search,
    int page = 1,
  }) async {
    _isLoading = true;
    _currentPage = page;
    notifyListeners();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': '10',
    };
    if (tahun != null) queryParams['tahun'] = tahun;
    if (tanggalMulai != null) queryParams['tanggal_mulai'] = tanggalMulai;
    if (tanggalSelesai != null) queryParams['tanggal_selesai'] = tanggalSelesai;
    if (jenisBantuan != null) queryParams['jenis_bantuan'] = jenisBantuan;
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;
    final response = await ApiService.get(
      ApiConstants.bantuanSosial,
      queryParams: queryParams,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _bantuanList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      final pag = response['pagination'] as Map<String, dynamic>?;
      if (pag != null) {
        _totalPages = pag['total_pages'] as int? ?? 1;
        _totalData = pag['total_data'] as int? ?? 0;
        _perPage = pag['per_page'] as int? ?? 10;
      }
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
    String? tanggalBantuan,
    String? tanggalMulai,
    String? tanggalSelesai,
    int? tahun,
    double? nominal,
    String? keterangan,
  }) async {
    _isLoading = true;
    notifyListeners();
    final body = <String, dynamic>{
      'user_id': userId,
      'jenis_bantuan': jenisBantuan,
      if (tanggalBantuan != null) 'tanggal_bantuan': tanggalBantuan,
      if (tanggalMulai != null) 'tanggal_mulai': tanggalMulai,
      if (tanggalSelesai != null) 'tanggal_selesai': tanggalSelesai,
      if (tahun != null) 'tahun': tahun,
      if (nominal != null) 'nominal': nominal,
      if (keterangan != null) 'keterangan': keterangan,
    };
    final response = await ApiService.post(
      ApiConstants.bantuanSosial,
      body: body,
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
    _errorMessage = response['message'] as String?;
    return false;
  }

  Future<bool> deleteBantuanSosial(int id) async {
    final response = await ApiService.delete('${ApiConstants.bantuanSosial}/$id');
    if (response['success'] == true) {
      await fetchBantuanSosial();
      await fetchStats();
      return true;
    }
    _errorMessage = response['message'] as String?;
    return false;
  }

  Future<List<Map<String, dynamic>>> fetchBantuanSosialHistory(int id) async {
    final response = await ApiService.get('${ApiConstants.bantuanSosial}/$id/history');
    if (response['success'] == true && response['data'] != null) {
      return List<Map<String, dynamic>>.from(response['data']);
    }
    return [];
  }

  void bersihkan() {
    _bantuanList = [];
    _stats = {'total_penerima': 0, 'aktif': 0, 'selesai': 0, 'jenis_aktif': 0};
    _isLoading = false;
    _errorMessage = null;
    _wargaList = [];
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _perPage = 10;
    notifyListeners();
  }
}
