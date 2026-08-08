import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/emergency_model.dart';

class EmergencyProvider extends ChangeNotifier {
  List<EmergencyModel> _alerts = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  String? _successMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  EmergencyProvider() {
    fetchAlerts();
  }

  List<EmergencyModel> get alerts => _alerts;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  EmergencyModel? get activeAlert {
    try {
      return _alerts.firstWhere((a) => a.isActive);
    } catch (_) {
      return null;
    }
  }

  Future<bool> triggerAlarm({String? message, String? pin}) async {
    _isSending = true;
    _errorMessage = null;
    notifyListeners();
    final body = <String, dynamic>{};
    if (message != null) body['message'] = message;
    if (pin != null) body['pin'] = pin;

    final response = await ApiService.post(
      ApiConstants.emergencyTrigger,
      body: body,
    );
    _isSending = false;
    if (response['success'] == true) {
      _successMessage = response['message'] as String?;
      await fetchAlerts(page: _currentPage, limit: _perPage);
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> dismissAlarm(String alertId, {String? pin}) async {
    _isLoading = true;
    _errorMessage = null;

    final body = <String, dynamic>{};
    if (pin != null) body['pin'] = pin;

    final response = await ApiService.post(
      ApiConstants.emergencyDismiss(alertId),
      body: body,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _successMessage = response['message'] as String?;
      await fetchAlerts(page: _currentPage, limit: _perPage);
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchAlerts({String? status, int page = 1, int limit = 10}) async {
    _isLoading = true;
    _currentPage = page;
    _perPage = limit;
    notifyListeners();

    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (status != null) queryParams['status'] = status;

    final response = await ApiService.get(
      ApiConstants.emergencyAlerts,
      queryParams: queryParams,
    );
    if (response['success'] == true) {
      final dataList = response['data'] as List<dynamic>;
      _alerts = dataList.map((j) => EmergencyModel.fromJson(j as Map<String, dynamic>)).toList();
      _errorMessage = null;

      if (response['pagination'] != null) {
        final p = response['pagination'] as Map<String, dynamic>;
        _totalData = p['total_data'] as int? ?? _alerts.length;
        _totalPages = p['total_pages'] as int? ?? 1;
        _currentPage = p['current_page'] as int? ?? page;
        _perPage = p['per_page'] as int? ?? limit;
      } else {
        _totalData = _alerts.length;
        _totalPages = 1;
      }
    } else {
      _errorMessage = response['message'] as String?;
    }
    _isLoading = false;
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
    _alerts = [];
    _isLoading = false;
    _isSending = false;
    _errorMessage = null;
    _successMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _perPage = 10;
    notifyListeners();
  }
}
