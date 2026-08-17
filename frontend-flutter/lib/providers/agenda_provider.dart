import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class AgendaProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _agendaList = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  String? _lastStatus;
  String? _lastTipe;

  List<Map<String, dynamic>> get agendaList => _agendaList;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;

  Future<void> fetchAgenda({String? status, String? tipe, int page = 1, bool silent = false}) async {
    _lastStatus = status;
    _lastTipe = tipe;
    _currentPage = page;

    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (tipe != null && tipe.isNotEmpty) queryParams['tipe'] = tipe;
    queryParams['page'] = page.toString();
    queryParams['limit'] = '25';
    final response = await ApiService.get(
      ApiConstants.agenda,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _agendaList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      if (response['pagination'] != null) {
        _totalPages = response['pagination']['total_pages'] ?? 1;
        _totalData = response['pagination']['total_data'] ?? 0;
      }
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> createAgenda({
    required String judul,
    required String tanggal,
    String? deskripsi,
    String? tipe,
    String? waktuMulai,
    String? waktuSelesai,
    String? lokasi,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.agenda,
      body: {
        'judul': judul,
        'tanggal': tanggal,
        if (deskripsi != null) 'deskripsi': deskripsi,
        if (tipe != null) 'tipe': tipe,
        if (waktuMulai != null) 'waktu_mulai': waktuMulai,
        if (waktuSelesai != null) 'waktu_selesai': waktuSelesai,
        if (lokasi != null) 'lokasi': lokasi,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchAgenda(status: _lastStatus, tipe: _lastTipe, page: 1);
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAgenda(int id, Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.put('${ApiConstants.agenda}/$id', body: data);
    _isLoading = false;
    if (response['success'] == true) {
      _errorMessage = null;
      await fetchAgenda(status: _lastStatus, tipe: _lastTipe, page: _currentPage);
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Gagal memperbarui agenda';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteAgenda(int id) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.delete('${ApiConstants.agenda}/$id');
    _isLoading = false;
    if (response['success'] == true) {
      _errorMessage = null;
      final targetPage = (_agendaList.length == 1 && _currentPage > 1)
          ? _currentPage - 1
          : _currentPage;
      await fetchAgenda(status: _lastStatus, tipe: _lastTipe, page: targetPage);
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Gagal menghapus agenda';
      notifyListeners();
      return false;
    }
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _agendaList = [];
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _lastStatus = null;
    _lastTipe = null;
    notifyListeners();
  }

}
