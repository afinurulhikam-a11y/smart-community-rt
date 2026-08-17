import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class FamilyProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _families = [];
  Map<String, dynamic>? _selectedFamily;
  bool _isLoading = false;
  String? _errorMessage;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;
  String? _lastSearch;

  List<Map<String, dynamic>> get families => _families;
  Map<String, dynamic>? get selectedFamily => _selectedFamily;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  Future<void> fetchFamilies({String? search, int page = 1, int limit = 10}) async {
    _lastSearch = search;
    _currentPage = page;
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    final response = await ApiService.get(
      ApiConstants.families,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _families = List<Map<String, dynamic>>.from(response['data'] ?? []);
      final pag = response['pagination'] as Map<String, dynamic>?;
      if (pag != null) {
        _currentPage = pag['current_page'] as int? ?? 1;
        _totalPages = pag['total_pages'] as int? ?? 1;
        _totalData = pag['total_data'] as int? ?? 0;
        _perPage = pag['per_page'] as int? ?? limit;
      }
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
      await fetchFamilies(search: _lastSearch, page: 1, limit: _perPage);
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
      await fetchFamilies(search: _lastSearch, page: _currentPage, limit: _perPage);
      return true;
    }
    return false;
  }

  Future<bool> deleteFamily(int id) async {
    final response = await ApiService.delete('${ApiConstants.families}/$id');
    if (response['success'] == true) {
      final targetPage = (_families.length == 1 && _currentPage > 1)
          ? _currentPage - 1
          : _currentPage;
      await fetchFamilies(search: _lastSearch, page: targetPage, limit: _perPage);
      return true;
    }
    return false;
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _families = [];
    _selectedFamily = null;
    _lastSearch = null;
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    notifyListeners();
  }

}
