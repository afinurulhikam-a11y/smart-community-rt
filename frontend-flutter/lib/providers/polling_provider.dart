import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class PollingProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _pollingList = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentStatusFilter;

  List<Map<String, dynamic>> get pollingList => _pollingList;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchPolling({String? status}) async {
    _currentStatusFilter = status;
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (_currentStatusFilter != null && _currentStatusFilter != 'Semua') {
      queryParams['status'] = _currentStatusFilter!;
    }
    final response = await ApiService.get(
      ApiConstants.polling,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _pollingList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> createPolling({
    required String judul,
    required String tanggalMulai,
    required String tanggalSelesai,
    String? deskripsi,
    required List<String> options,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.polling,
      body: {
        'judul': judul,
        'tanggal_mulai': tanggalMulai,
        'tanggal_selesai': tanggalSelesai,
        if (deskripsi != null) 'deskripsi': deskripsi,
        'options': options,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchPolling();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> vote(int pollingId, int optionId) async {
    final response = await ApiService.post(
      ApiConstants.pollingVote(pollingId),
      body: {'option_id': optionId},
    );
    if (response['success'] == true) {
      await fetchPolling(status: _currentStatusFilter == 'Semua' ? null : _currentStatusFilter);
      return true;
    }
    _errorMessage = response['message'] as String?;
    notifyListeners();
    return false;
  }

  Future<bool> updatePollingStatus(int id, String status) async {
    final response = await ApiService.put(ApiConstants.pollingStatus(id), body: {'status': status});
    if (response['success'] == true) {
      await fetchPolling(status: _currentStatusFilter == 'Semua' ? null : _currentStatusFilter);
      return true;
    }
    _errorMessage = response['message'] as String?;
    notifyListeners();
    return false;
  }

  Future<bool> deletePolling(int id) async {
    final response = await ApiService.delete('${ApiConstants.polling}/$id');
    if (response['success'] == true) {
      await fetchPolling(status: _currentStatusFilter == 'Semua' ? null : _currentStatusFilter);
      return true;
    }
    _errorMessage = response['message'] as String?;
    notifyListeners();
    return false;
  }

  /// Jalur khusus pengujian widget.
  @visibleForTesting
  void pasangUji(List<Map<String, dynamic>> daftar, {String? galat}) {
    _pollingList = List<Map<String, dynamic>>.from(daftar);
    _isLoading = false;
    _errorMessage = galat;
    notifyListeners();
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _pollingList = [];
    _isLoading = false;
    _errorMessage = null;
    _currentStatusFilter = null;
    notifyListeners();
  }
}
