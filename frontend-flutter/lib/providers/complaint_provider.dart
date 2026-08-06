import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class ComplaintProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;

  List<Map<String, dynamic>> get complaints => _complaints;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;

  Future<void> fetchComplaints({String? status, String? search, int page = 1}) async {
    _isLoading = true;
    _currentPage = page;
    notifyListeners();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;
    queryParams['page'] = page.toString();
    queryParams['limit'] = '25';
    final response = await ApiService.get(
      ApiConstants.complaints,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _complaints = List<Map<String, dynamic>>.from(response['data'] ?? []);
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

  Future<bool> createComplaint({required String judul, String? deskripsi, String? kategori}) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.complaints,
      body: {
        'judul': judul,
        if (deskripsi != null) 'deskripsi': deskripsi,
        if (kategori != null) 'kategori': kategori,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchComplaints();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateComplaintStatus(int id, {required String status, String? response}) async {
    final resp = await ApiService.put(
      ApiConstants.complaintStatus(id),
      body: {'status': status, if (response != null) 'response': response},
    );
    if (resp['success'] == true) {
      await fetchComplaints();
      return true;
    }
    return false;
  }

  Future<bool> deleteComplaint(int id) async {
    final response = await ApiService.delete('${ApiConstants.complaints}/$id');
    if (response['success'] == true) {
      await fetchComplaints();
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
    _complaints = [];
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    notifyListeners();
  }

}
