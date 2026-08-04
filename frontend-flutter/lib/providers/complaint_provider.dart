import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class ComplaintProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get complaints => _complaints;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchComplaints({String? status, String? search}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;
    final response = await ApiService.get(
      ApiConstants.complaints,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _complaints = List<Map<String, dynamic>>.from(response['data'] ?? []);
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
}
