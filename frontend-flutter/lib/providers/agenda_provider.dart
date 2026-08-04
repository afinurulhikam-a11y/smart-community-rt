import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class AgendaProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _agendaList = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get agendaList => _agendaList;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchAgenda({String? status, String? tipe}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (tipe != null) queryParams['tipe'] = tipe;
    final response = await ApiService.get(
      ApiConstants.agenda,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _agendaList = List<Map<String, dynamic>>.from(response['data'] ?? []);
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
      await fetchAgenda();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAgenda(int id, Map<String, dynamic> data) async {
    final response = await ApiService.put('${ApiConstants.agenda}/$id', body: data);
    if (response['success'] == true) {
      await fetchAgenda();
      return true;
    }
    return false;
  }

  Future<bool> deleteAgenda(int id) async {
    final response = await ApiService.delete('${ApiConstants.agenda}/$id');
    if (response['success'] == true) {
      await fetchAgenda();
      return true;
    }
    return false;
  }
}
