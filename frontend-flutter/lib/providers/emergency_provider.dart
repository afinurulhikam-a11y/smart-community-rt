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

  EmergencyProvider() {
    fetchAlerts();
  }

  List<EmergencyModel> get alerts => _alerts;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

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
      await fetchAlerts();
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
      await fetchAlerts();
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchAlerts({String? status}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    final response = await ApiService.get(
      ApiConstants.emergencyAlerts,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    if (response['success'] == true) {
      final dataList = response['data'] as List<dynamic>;
      _alerts = dataList.map((j) => EmergencyModel.fromJson(j as Map<String, dynamic>)).toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    _isLoading = false;
    notifyListeners();
  }
}
