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

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _data = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

}
