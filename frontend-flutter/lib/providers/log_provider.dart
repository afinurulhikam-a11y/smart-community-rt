import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class LogProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get logs => _logs;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchLogs({int limit = 25, String? search, String? tipe}) async {
    _isLoading = true;
    notifyListeners();

    final queryParams = <String, String>{'limit': limit.toString()};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (tipe != null && tipe != 'Semua') queryParams['tipe'] = tipe;

    final response = await ApiService.get(ApiConstants.activityLogs, queryParams: queryParams);

    _isLoading = false;
    if (response['success'] == true) {
      _logs = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> clearLogs() async {
    _isLoading = true;
    notifyListeners();

    final response = await ApiService.delete(ApiConstants.activityLogs);
    _isLoading = false;

    if (response['success'] == true) {
      _logs = [];
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }
}
