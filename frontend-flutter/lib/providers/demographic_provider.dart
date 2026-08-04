import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/constants/api_constants.dart';
import '../models/demographic_model.dart';

class DemographicProvider extends ChangeNotifier {
  DemographicData? _data;
  bool _isLoading = false;
  String? _error;

  DemographicData? get data => _data;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchDemographics() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.get(ApiConstants.demographicsSummary);
      if (response['success'] == true && response['data'] != null) {
        _data = DemographicData.fromJson(response['data']);
      } else {
        _error = response['message'] ?? 'Gagal mengambil data demografi';
      }
    } catch (e, stacktrace) {
      debugPrint('Error fetchDemographics: $e');
      debugPrint(stacktrace.toString());
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
